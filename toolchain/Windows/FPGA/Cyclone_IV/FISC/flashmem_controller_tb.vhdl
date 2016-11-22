LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY FLASHMEM_Controller_tb IS
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
END FLASHMEM_Controller_tb;

ARCHITECTURE RTL OF FLASHMEM_Controller_tb IS
	signal leds : std_logic_vector(3 downto 0) := (others => '0');
	
	-- Flash Memory Controller Wires:
	signal fmem_reset       : std_logic := '0';
	signal fmem_reset_done  : std_logic;
	signal fmem_enable      : std_logic := '0';
	signal fmem_ready       : std_logic;
	signal fmem_instruction : integer := 0;
	signal fmem_address     : integer := 0;
	signal fmem_data_write  : std_logic_vector(256*8-1 downto 0) := (others => '0');
	signal fmem_data_read   : std_logic_vector(256*8-1 downto 0);
	signal fmem_status      : std_logic_vector(7       downto 0);
	
	type fsm_t is (
		s_reset,
		s_reset_done,
		s_read_page, s_read_page_done,
		s_read_status1, s_read_status2,
		s_write_enable, s_erase_sector, s_write_page,
		s_control_wait,
		s_idle
	);
	signal state                   : fsm_t   := s_reset;
	signal wait_next_state         : fsm_t   := s_idle; -- After controling the memory and waiting, where shall the fsm state go next
	signal write_enable_next_state : fsm_t   := s_idle; -- After write enabling, should we write to a page or erase a sector?
	signal fsm_jumping             : boolean := false;
	signal returned                : boolean := false;
	
	-- Flash Memory Instruction Constants (there's more instructions, but this is all we need):
	constant INSTR_READ_PAGE    : integer := 3;
	constant INSTR_READ_STATUS1 : integer := 5;
	constant INSTR_READ_STATUS2 : integer := 53;
	constant INSTR_WRITE_ENABLE : integer := 6;
	constant INSTR_WRITE_PAGE   : integer := 2;
	constant INSTR_SECTOR_ERASE : integer := 32;
BEGIN
	(DS_D, DS_C, DS_G, DS_DP) <= not leds;
	
	FLASH_WP <= '1'; -- We don't want to mess with Write Protection

	FLASHMEM_Controller1: ENTITY work.FLASHMEM_Controller PORT MAP (
		CLK, fmem_reset, fmem_reset_done, fmem_enable, fmem_ready, fmem_instruction, fmem_address, fmem_data_write, fmem_data_read, fmem_status,
		FLASH_CS, FLASH_DO, FLASH_DI, FLASH_CLK
	);
		
	main_proc: process(CLK) begin
		if rising_edge(CLK) then	
			case state is
				-- TRIGGER RESET --
				when s_reset =>
					fmem_reset <= '1';
					state      <= s_reset_done;
				
				
				-- WAIT FOR FLASH MEMORY TO FINISH INITIALIZING/RESETTING --
				when s_reset_done =>
					fmem_reset <= '0';
					if fmem_reset_done = '1' then
						state <= s_erase_sector;
					end if;
				
					
				-- READ WHOLE PAGE --
				when s_read_page =>
					fmem_address     <= 1; -- Read from this address
					
					fmem_instruction <= INSTR_READ_PAGE;
					fmem_enable      <= '1';
					wait_next_state  <= s_read_page_done;
					state            <= s_control_wait;
				when s_read_page_done =>
					leds  <= fmem_data_read(3 downto 0);
					state <= s_idle;
				
				
				-- READ MEMORY STATUS --
				when s_read_status1 => -- We don't need to test this for now
				when s_read_status2 => -- We don't need to test this for now
				
				
				-- ENABLE MEMORY WRITING --	
				when s_write_enable =>
					fmem_instruction <= INSTR_WRITE_ENABLE;
					fmem_enable      <= '1';
					wait_next_state  <= write_enable_next_state;
					state            <= s_control_wait;
				
				
				-- WRITE WHOLE PAGE --
				when s_write_page =>
					if returned = false then
						-- We need to write enable first:
						fsm_jumping             <= true;
						write_enable_next_state <= s_write_page;
						state                   <= s_write_enable;
					else
						-- Now we can write to the page:
						fmem_address     <= 1; -- Write to this address
						fmem_data_write  <= std_logic_vector(to_unsigned(14, fmem_data_write'length)); -- Write this data
					
						fmem_instruction <= INSTR_WRITE_PAGE;
						fmem_enable      <= '1';
						returned         <= false;
						wait_next_state  <= s_read_page;
						state            <= s_control_wait;
					end if;
				
				
				-- ERASE SECTOR --
				when s_erase_sector =>
					if returned = false then
						-- We need to write enable first:
						fsm_jumping             <= true;
						write_enable_next_state <= s_erase_sector;
						state                   <= s_write_enable;
					else
						-- Now we can erase the sector:
						fmem_address     <= 0; -- Erase from this address
						
						fmem_instruction <= INSTR_SECTOR_ERASE;
						fmem_enable      <= '1';
						returned         <= false;
						wait_next_state  <= s_write_page;
						state            <= s_control_wait;
					end if;
				
				
				-- WAIT FOR THE COMMAND TO FINISH EXECUTING --
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
					
				when s_idle => fmem_enable <= '0'; -- Do nothing
				when others => state <= s_idle;
			end case;
		end if;
	end process;
	
END ARCHITECTURE RTL;