LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY Flash_Memory_Loader IS
	PORT(
		CLK       : in  std_logic;
		FLASH_CS  : out std_logic; -- /SS (Drive)
		FLASH_DO  : in  std_logic; -- MISO (Read)
		FLASH_WP  : out std_logic;
		FLASH_CLK : out std_logic; -- SCK (Drive)
		FLASH_DI  : out std_logic; -- MOSI (Drive)
		DS_DP     : out std_logic;
		DS_G      : out std_logic;
		DS_C      : out std_logic;
		DS_D      : out std_logic
	);
END ENTITY Flash_Memory_Loader;

ARCHITECTURE RTL OF Flash_Memory_Loader IS
	signal leds : std_logic_vector(3 downto 0) := (others => '0');
	
	type fsm_t is (
		-- Core FSM states:
		s_init, s_init_done,
		s_erase_chip, s_load,
		s_finish, s_error,
		-- Flash Memory Controller States:
		s_write_enable, s_write_page,
		s_control_wait
	);
	signal state                   : fsm_t   := s_init;
	signal wait_next_state         : fsm_t   := s_init; -- After controling the memory and waiting, where shall the fsm state go next
	signal write_enable_next_state : fsm_t   := s_init; -- After write enabling, should we write to a page or erase the chip?
	signal fsm_jumping             : boolean := false;
	signal returned                : boolean := false;
	
	-- Flash Memory Controller Constants and Wires:
	constant FLASH_MEM_PAGE_COUNT   : integer   :=  16384; -- We have in total 16384 pages in this Flash Memory
	constant FLASH_MEM_PAGE_SIZE    : integer   :=  256; -- How many bytes do we need to load from ROM to the flash memory buffer
	constant FLASH_MEM_BUFF_SIZE    : integer   :=  FLASH_MEM_PAGE_SIZE * 8; -- Each page is 256 bytes, therefore, we need 2048 bits
	signal   fmem_reset             : std_logic := '0';
	signal   fmem_reset_done        : std_logic;
	signal   fmem_enable            : std_logic := '0';
	signal   fmem_ready             : std_logic;
	signal   fmem_instruction       : integer   :=  0;
	signal   fmem_address           : integer   :=  0;
	signal   fmem_data_write        : std_logic_vector(FLASH_MEM_BUFF_SIZE-1 downto 0) := (others => '0');
	signal   fmem_data_read         : std_logic_vector(FLASH_MEM_BUFF_SIZE-1 downto 0);
	signal   fmem_status            : std_logic_vector(7 downto 0);
	
	signal   fmem_data_write_fill_ctr : integer := 0; -- Which byte out of the 256 bytes are we currently writing into?
	signal   fmem_pages_loaded        : integer := 0; -- How many pages have we loaded so far?
	
	-- Flash Memory Instruction Constants (there's more instructions, but this is all we need):
	constant INSTR_READ_PAGE     : integer := 3;
	constant INSTR_READ_STATUS1  : integer := 5;
	constant INSTR_READ_STATUS2  : integer := 53;
	constant INSTR_WRITE_ENABLE  : integer := 6;
	constant INSTR_WRITE_PAGE    : integer := 2;
	constant INSTR_SECTOR_ERASE  : integer := 32;
	constant INSTR_CHIP_ERASE    : integer := 199;
	
	-- ROM Constants and Wires:
	constant ROM_TOTAL_BYTECOUNT : integer := 8192; -- The ROM's total size is 8192 bytes
	signal   rom_bytecount_ctr   : integer := 0;    -- How many bytes we've loaded so far
	signal   rom_address         : std_logic_vector(12 downto 0) := (others => '0');
	signal   rom_data            : std_logic_vector(7  downto 0);
	
	-- ROM 'void bytes' bug fix's variables (I need to fix this...):
	signal   first_cycle : boolean := false;
	signal   skipping    : boolean := false;
	signal   skip_ctr    : integer := 0;
	constant skip_max    : integer := 13; -- For every 16 bytes, we need to skip the following 13 bytes
	constant nonskip_max : integer := 16; -- Whenever we're not skipping, how many bytes shall we fetch?
BEGIN
	(DS_D, DS_C, DS_G, DS_DP) <= not leds;
	
	FLASH_WP <= '1'; -- We don't want to mess with Write Protection
	
	FLASHMEM_Controller1: ENTITY work.FLASHMEM_Controller PORT MAP (
		CLK, fmem_reset, fmem_reset_done, fmem_enable, fmem_ready, fmem_instruction, fmem_address, fmem_data_write, fmem_data_read, fmem_status,
		FLASH_CS, FLASH_DO, FLASH_DI, FLASH_CLK
	);
	
	rom_inst : ENTITY work.rom_8x8192 PORT MAP (
		address => rom_address,
		clock	  => CLK,
		q	     => rom_data
	);
	
	rom_address <= std_logic_vector(to_unsigned(rom_bytecount_ctr, rom_address'length));
					
	main_proc: process(CLK) is
	begin
		if rising_edge(CLK) then		
			case state is
				when s_init =>
					fmem_reset <= '1';
					state      <= s_init_done;
				
				
				when s_init_done =>
					fmem_reset <= '0';
					if fmem_reset_done = '1' then
						state <= s_erase_chip;
					end if;
				
				
				when s_erase_chip =>
					leds <= "0001";
					-- We're going to erase the whole chip:
					if returned = false then
						-- We need to write enable first:
						fsm_jumping             <= true;
						write_enable_next_state <= s_erase_chip;
						state                   <= s_write_enable;
					else
						-- Only now we can erase the chip:
						wait_next_state  <= s_load;
						fmem_instruction <= INSTR_CHIP_ERASE;
						fmem_enable      <= '1';
						returned         <= false;
						state            <= s_control_wait;
					end if;
				
				
				when s_load =>
					leds              <= "0011";
					rom_bytecount_ctr <= rom_bytecount_ctr + 1;
					
					if first_cycle = true then
						-- ** Algorithm: **
						-- Load 1 byte into the buffer 'fmem_data_write'.
						-- For every 256 bytes loaded, write the buffer into the flash memory with an aligned address
						-- Also, for every 16 bytes we iterate, skip 13 more, then load more 16 bytes (this is a bug from a malformed hex file, but it'll work for now)
						if rom_bytecount_ctr = ROM_TOTAL_BYTECOUNT-1 or fmem_pages_loaded = FLASH_MEM_PAGE_COUNT-1 then
							-- We're done loading memory, we can quit this state now
							state <= s_finish;
						else
							if skipping = false then
								fmem_data_write((fmem_data_write_fill_ctr+1)*8-1 downto fmem_data_write_fill_ctr*8) <= rom_data;
								fmem_data_write_fill_ctr <= fmem_data_write_fill_ctr + 1;
								
								if fmem_data_write_fill_ctr = FLASH_MEM_PAGE_SIZE-1 then
									-- We've filled the buffer, it's time to write it into the aligned address
									fmem_address             <= fmem_pages_loaded * FLASH_MEM_PAGE_SIZE;
									state                    <= s_write_page;
									fmem_data_write_fill_ctr <= 0;
									fmem_pages_loaded        <= fmem_pages_loaded + 1;
								end if;
								
								skip_ctr <= skip_ctr + 1;
								if skip_ctr = nonskip_max-1 then
									skipping <= true;
									skip_ctr <= 0;
								end if;
							else
								-- We're currently skipping 13 bytes
								skip_ctr <= skip_ctr + 1;
								if skip_ctr = skip_max-1 then
									skipping <= false;
									skip_ctr <= 0;
								end if;
							end if;
						end if;
					else
						first_cycle <= true;
					end if;
			
			
				when s_write_enable =>
					fmem_instruction <= INSTR_WRITE_ENABLE;
					fmem_enable      <= '1';
					wait_next_state  <= write_enable_next_state;
					state            <= s_control_wait;
				
				
				when s_write_page =>
					if returned = false then
						-- We need to write enable first:
						fsm_jumping             <= true;
						write_enable_next_state <= s_write_page;
						state                   <= s_write_enable;
					else
						-- Now we can write to the page:
						fmem_instruction <= INSTR_WRITE_PAGE;
						fmem_enable      <= '1';
						returned         <= false;
						wait_next_state  <= s_load; -- Go back to loading the rest of the memory
						state            <= s_control_wait;
					end if;
				
				
				when s_control_wait =>
					fmem_enable <= '0';
					if fmem_ready = '1' then
						-- The memory instruction has finished:
						state <= wait_next_state;
						if fsm_jumping then
							returned    <= true;
							fsm_jumping <= false;
						end if;
					end if;
				
				
				when s_finish => 
					-- Show up success on leds
					leds <= "0111";
									
				when s_error =>  -- Show up error on leds
				when others => state <= s_error;
			end case;
			
		end if;
	end process;
END ARCHITECTURE RTL;