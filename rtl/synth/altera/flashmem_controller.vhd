LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY FLASHMEM_Controller IS
	PORT(
		-- Flash Memory Controller wires:
		clk         : in  std_logic;
		reset       : in  std_logic;
		reset_done  : out std_logic := '0';
		enable      : in  std_logic; -- Trigger command execution with a pulse
		ready       : out std_logic := '0'; -- Indicates when the command has finished executing
		instruction : in  integer;
		address     : in  integer;
		data_write  : in  std_logic_vector(256*8-1 downto 0); -- Smallest size that can be written is 1 page (256 bytes)
		data_read   : out std_logic_vector(256*8-1 downto 0) := (others => '0'); -- Makes sense to read a whole page at once
		status      : out std_logic_vector(7       downto 0) := (others => '0');
		
		-- SPI Output wires:
		flash_cs    : out std_logic;
		miso        : in  std_logic;
		mosi        : out std_logic;
		sck         : out std_logic
	);
END ENTITY;

ARCHITECTURE RTL OF FLASHMEM_Controller IS
	type fsm_t is (
		s_wait_reset, s_reset, s_reset_done,
		s_control,
		s_idle
	);
	signal state : fsm_t := s_wait_reset;
			
	type transaction_stage_t is (
		s_trans_null,
		s_trans_opcode,
		s_trans_addr,
		s_trans_data,
		s_trans_finish
	);
	signal trans_state : transaction_stage_t := s_trans_null;
	
	-- Instruction Constants:
	constant INSTR_READ_PAGE    : integer := 3;
	constant INSTR_READ_STATUS1 : integer := 5;
	constant INSTR_READ_STATUS2 : integer := 53;
	constant INSTR_WRITE_ENABLE : integer := 6;
	constant INSTR_WRITE_PAGE   : integer := 2;
	constant INSTR_SECTOR_ERASE : integer := 32;
	constant INSTR_CHIP_ERASE   : integer := 199;
	
	-- Size Constants:
	constant FLASH_CS_ENABLE     : std_logic := '0';
	constant FLASH_CS_DISABLE    : std_logic := '1';
	constant FLASH_OPCODE_SZ     : integer   :=  8;
	constant FLASH_ADDR_SZ       : integer   :=  24;
	constant FLASH_READBUFF_SZ   : integer   :=  8*256;
	constant FLASH_WRITE_BUFF_SZ : integer   :=  8*256;
	constant FLASH_STATUS_SZ     : integer   :=  8;
	
	-- Internal wires that drive the FPGA pinouts:
	signal iob_flash_cs   : std_logic := FLASH_CS_DISABLE; -- Falling Edge Trigger
	signal iob_mosi       : std_logic := '0';
	signal sck_en         : std_logic := '0'; -- Enable SCK
	signal sck_en_fall    : std_logic := '0'; -- Enable SCK, but on falling edge
	signal sck_sched_fall : std_logic := '0'; -- Causes the SCK to be disabled on the falling edge, but is triggered by an early rising edge cycle
	
	-- Shift registers to be sent/received through the MOSI/MISO wires:
	signal flash_opcode    : std_logic_vector(FLASH_OPCODE_SZ-1     downto 0) := (others => '0');
	signal flash_addr      : std_logic_vector(FLASH_ADDR_SZ-1       downto 0) := (others => '0');
	signal flash_readbuff  : std_logic_vector(FLASH_READBUFF_SZ-1   downto 0) := (others => '0');
	signal flash_writebuff : std_logic_vector(FLASH_WRITE_BUFF_SZ-1 downto 0) := (others => '0');
	signal flash_status    : std_logic_vector(FLASH_STATUS_SZ-1     downto 0) := (others => '0');  
	signal shift_reg_idx   : integer := 0;
	
	-- Wait for the Flash Memory to be unbusy
	signal busy_wait : boolean := false;
	
BEGIN

	-----------------
	-- ASSIGNMENTS --
	-----------------
	flash_cs <= iob_flash_cs;
	mosi     <= iob_mosi;
	sck      <= clk WHEN (sck_en = '1' and sck_en_fall = '1') ELSE '0'; -- We'll just route the original clk for now
	
	---------------
	-- BEHAVIOUR --
	---------------
	main_proc: process(clk) begin
		if rising_edge(clk) then
			if reset = '1' then
				state <= s_reset;
			end if;
								
			case state is
				when s_wait_reset =>
					-- Wait for the top level to trigger reset
					reset_done <= '0';
				
				when s_reset =>
					iob_flash_cs <= FLASH_CS_ENABLE;
					state        <= s_reset_done;
			
				when s_reset_done => 
					-- Wait for the device to initialize (in this case we can initialize it in only 1 cycle)
					iob_flash_cs <= FLASH_CS_DISABLE;

					-- And then move on:
					reset_done <= '1';
					state      <= s_idle;
				
				when s_idle =>
					-- Wait for the top entity to trigger the command execution:
					ready  <= '0';
					status <= (others => '0');
					if enable = '1' then
						state <= s_control;
					end if;
					
				when s_control =>
					if trans_state = s_trans_null then
						if busy_wait = false then
							flash_opcode    <= std_logic_vector(to_unsigned(instruction, flash_opcode'length));
						end if;
						flash_addr      <= std_logic_vector(to_unsigned(address, flash_addr'length));
						flash_writebuff <= data_write;
						iob_flash_cs    <= FLASH_CS_ENABLE;
						trans_state     <= s_trans_opcode;
					else
						case trans_state is
							-- Send opcode/instruction:
							when s_trans_opcode =>
								-- Opcode is being sent on the clk falling edge (through MOSI)
								if shift_reg_idx = flash_opcode'high then
									if flash_opcode = std_logic_vector(to_unsigned(INSTR_WRITE_ENABLE, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_CHIP_ERASE, flash_opcode'length)) then
										trans_state    <= s_trans_finish;
										sck_sched_fall <= '1';
									else
										shift_reg_idx  <= 0;
										if flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS2, flash_opcode'length)) then
											trans_state <= s_trans_data;
										else
											trans_state <= s_trans_addr;
										end if;
									end if;
								else
									shift_reg_idx <= shift_reg_idx + 1;
									sck_en        <= '1';
								end if;
							
							
							-- Send 24-bit address (may depend on the instruction):
							when s_trans_addr =>
								-- Address is being sent on the clk falling edge (through MOSI)
								if shift_reg_idx = flash_addr'high then
									if flash_opcode = std_logic_vector(to_unsigned(INSTR_SECTOR_ERASE, flash_opcode'length)) then
										trans_state    <= s_trans_finish;
										sck_sched_fall <= '1';
									else
										shift_reg_idx <= 0;
										trans_state   <= s_trans_data;
									end if;
								else
									shift_reg_idx <= shift_reg_idx + 1;
								end if;
							
							
							-- Receive/Transmit data (1 byte every 8 clk cycles on every rising edge):
							when s_trans_data =>
								if (flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_PAGE, flash_opcode'length)) and shift_reg_idx = flash_readbuff'high) or
									((flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS2, flash_opcode'length))) and shift_reg_idx = flash_status'high) or 
									(flash_opcode = std_logic_vector(to_unsigned(INSTR_WRITE_PAGE, flash_opcode'length)) and shift_reg_idx = flash_writebuff'high) 
								then
									trans_state    <= s_trans_finish;
									sck_sched_fall <= '1';
								else
									shift_reg_idx <= shift_reg_idx + 1;
								end if;
								
								-- Read the data (or not):
								if flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_PAGE, flash_opcode'length)) then
									-- Read single bit (from MISO) and insert it into the data buffer (on every clk rising edge, since we're in mode 0)
									flash_readbuff(flash_readbuff'high - shift_reg_idx) <= miso;
								elsif (flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS2, flash_opcode'length))) then
									-- Read single bit (from MISO) and insert it into the status data buffer (on every clk rising edge, since we're in mode 0)
									flash_status(flash_status'high - shift_reg_idx) <= miso;
								else
									-- The Page is being sent on the falling edge
								end if;
							
							
							-- We're done with the transaction:
							when s_trans_finish =>
								iob_flash_cs   <= FLASH_CS_DISABLE;
								sck_en         <= '0';
								sck_sched_fall <= '0';
								shift_reg_idx  <=  0;
								trans_state    <= s_trans_null;
							
								if busy_wait then
									if flash_status(0) = '1' and flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length)) then
										-- It seems the memory is still busy, we shall keep reading its status register, and then we'll continue
										state        <= s_control;
										flash_status <= (others => '0');
									else
										-- We're done waiting for the memory
										busy_wait <= false;
										ready     <= '1';
										state     <= s_idle;
									end if;
								else
									if (flash_opcode = std_logic_vector(to_unsigned(INSTR_WRITE_PAGE, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_SECTOR_ERASE, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_CHIP_ERASE, flash_opcode'length))) then
										flash_opcode <= std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length));
										busy_wait    <= true;
										state        <= s_control; -- After writing occurs, we should wait for the memory to be unbusy
									else
										if flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_PAGE, flash_opcode'length)) then
											data_read <= flash_readbuff;
										elsif flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS1, flash_opcode'length)) or flash_opcode = std_logic_vector(to_unsigned(INSTR_READ_STATUS2, flash_opcode'length)) then
											status    <= flash_status;
										end if;
										busy_wait    <= false;
										ready        <= '1';
										state        <= s_idle;
									end if;		
								end if;
							
							when others => -- Ignore this
						end case;
					end if;
					
				when others => state <= s_idle;
			end case;
		end if;
	end process;
	
	-- Main process on falling edge:
	main_proc_falling: process(clk) begin
		if falling_edge(clk) then
			-- Write to MOSI on Falling Edge:
			case trans_state is
				when s_trans_opcode => 
					iob_mosi <= flash_opcode(flash_opcode'high - shift_reg_idx);
				when s_trans_addr =>
					iob_mosi <= flash_addr(flash_addr'high - shift_reg_idx);
				when s_trans_data =>
					if flash_opcode = std_logic_vector(to_unsigned(INSTR_WRITE_PAGE, flash_opcode'length)) then
						iob_mosi <= flash_writebuff(flash_writebuff'high - shift_reg_idx);
					else
						iob_mosi <= '0';
					end if;
				when others => -- Don't write to MOSI
			end case;
			
			-- See if we need to disable SCK on falling edge:
			if sck_sched_fall = '0' then
				sck_en_fall <= '1';
			else
				sck_en_fall <= '0';
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;