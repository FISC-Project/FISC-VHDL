LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY FLASHMEM_Controller IS
	PORT(
		-- Flash Memory Controller wires:
		clk        : in  std_logic;
		reset      : in  std_logic;
		reset_done : out std_logic := '0';
		
		-- SPI Output wires:
		flash_cs   : out std_logic;
		miso       : in  std_logic;
		mosi       : out std_logic;
		sck        : out std_logic;
		
		debug_leds : out std_logic_vector(3 downto 0)
	);
END ENTITY;

ARCHITECTURE RTL OF FLASHMEM_Controller IS
	signal iob_debug_leds : std_logic_vector(3 downto 0) := (others => '0');
	
	type fsm_t is (
		s_wait_reset, s_reset, s_reset_done,
		s_testbench,
		s_read_status1,
		s_read_status2,
		s_read_byte,
		s_write_enable, s_write_page,
		s_write_enable_sector, s_sector_erase,
		s_write_wait, s_sector_erase_wait,
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
	constant INSTR_READ_BYTE    : integer := 3;
	constant INSTR_READ_STATUS1 : integer := 5;
	constant INSTR_READ_STATUS2 : integer := 53;
	constant INSTR_WRITE_ENABLE : integer := 6;
	constant INSTR_WRITE_PAGE   : integer := 2;
	constant INSTR_SECTOR_ERASE : integer := 32;
	
	-- Constants:
	constant FLASH_CS_ENABLE     : std_logic := '0';
	constant FLASH_CS_DISABLE    : std_logic := '1';
	constant FLASH_OPCODE_SZ     : integer   :=  8;
	constant FLASH_ADDR_SZ       : integer   :=  24;
	constant FLASH_READBUFF_SZ   : integer   :=  8;
	constant FLASH_WRITE_BUFF_SZ : integer   :=  8*256;
	constant FLASH_STATUS_SZ     : integer   :=  8;
	
	-- Internal wires that drive the FPGA pinouts:
	signal iob_flash_cs   : std_logic := FLASH_CS_DISABLE; -- Falling Edge Trigger
	signal iob_mosi       : std_logic := '0';
	signal sck_en         : std_logic := '0'; -- Enable SCK
	signal sck_en_fall    : std_logic := '0'; -- Enable SCK, but on falling edge
	signal sck_sched_fall : std_logic := '0'; -- Causes the SCK to be disabled on the falling edge, but is triggered by an early rising edge cycle
	signal sck_ctr        : integer   :=  0;
	
	-- Shift registers to be sent/received through the MOSI/MISO wires:
	signal flash_opcode    : std_logic_vector(FLASH_OPCODE_SZ-1     downto 0) := (others => '0');
	signal flash_addr      : std_logic_vector(FLASH_ADDR_SZ-1       downto 0) := (others => '0');
	signal flash_readbuff  : std_logic_vector(FLASH_READBUFF_SZ-1   downto 0) := (others => '0');
	signal flash_writebuff : std_logic_vector(FLASH_WRITE_BUFF_SZ-1 downto 0) := (others => '0');
	signal flash_status    : std_logic_vector(FLASH_STATUS_SZ-1     downto 0) := (others => '0');  
	signal shift_reg_idx   : integer := 0;
		
	procedure flash_ctrl
	(
		instruction            : in    integer;
		addr                   : in    integer;
		data_write             : in    integer;
		busy_wait              : in    boolean;
		signal flash_status    : inout std_logic_vector(FLASH_STATUS_SZ-1 downto 0);
		signal flash_opcode    : out   std_logic_vector(FLASH_OPCODE_SZ-1 downto 0);
		signal flash_addr      : out   std_logic_vector(FLASH_ADDR_SZ-1   downto 0);
		signal iob_flash_cs    : out   std_logic;
		signal trans_state     : inout transaction_stage_t;
		signal shift_reg_idx   : inout integer;
		signal sck_en          : out   std_logic;
		signal sck_sched_fall  : out   std_logic;
		signal flash_readbuff  : inout std_logic_vector(FLASH_READBUFF_SZ-1   downto 0);
		signal flash_writebuff : out   std_logic_vector(FLASH_WRITE_BUFF_SZ-1 downto 0);
		signal miso            : in    std_logic;
		signal iob_debug_leds  : inout std_logic_vector(3 downto 0);
		signal state           : out   fsm_t;
		busy_state             : in    fsm_t;
		next_state             : in    fsm_t
	) is begin
		if trans_state = s_trans_null then
			flash_opcode    <=  std_logic_vector(to_unsigned(instruction, flash_opcode'length));
			flash_addr      <=  std_logic_vector(to_unsigned(addr, flash_addr'length));
			flash_writebuff <=  std_logic_vector(to_unsigned(data_write, flash_writebuff'length));
			iob_flash_cs    <= FLASH_CS_ENABLE;
			trans_state     <= s_trans_opcode;
		else
			case trans_state is
				when s_trans_opcode => -- Send opcode/instruction
					if shift_reg_idx = flash_opcode'high then
						if instruction = INSTR_WRITE_ENABLE then
							trans_state    <= s_trans_finish;
							sck_sched_fall <= '1';
						else
							shift_reg_idx  <= 0;
							if instruction = INSTR_READ_STATUS1 or instruction = INSTR_READ_STATUS2 then
								trans_state <= s_trans_data;
							else
								trans_state <= s_trans_addr;
							end if;
						end if;
					else
						shift_reg_idx <= shift_reg_idx + 1;
						sck_en        <= '1';
					end if;
					-- Opcode is being sent on the falling edge
								
				when s_trans_addr => -- Send 24-bit address (may depend on the instruction)
					if shift_reg_idx = flash_addr'high then
						if instruction = INSTR_SECTOR_ERASE then
							trans_state   <= s_trans_finish;
						else
							shift_reg_idx <= 0;
							trans_state   <= s_trans_data;
						end if;
					else
						shift_reg_idx <= shift_reg_idx + 1;
					end if;
					-- Address is being sent on the falling edge
					
				when s_trans_data => -- Receive/Transmit data (1 byte every 8 clk cycles on every rising edge)
					if (instruction = INSTR_READ_BYTE   and shift_reg_idx = flash_readbuff'high) or
						((instruction = INSTR_READ_STATUS1 or instruction = INSTR_READ_STATUS2) and shift_reg_idx = flash_status'high) or 
						(instruction = INSTR_WRITE_PAGE  and shift_reg_idx = flash_writebuff'high) 
					then
						trans_state    <= s_trans_finish;
						sck_sched_fall <= '1';
					else
						shift_reg_idx <= shift_reg_idx + 1;
					end if;
					
					-- Read the data (or not):
					if instruction = INSTR_READ_BYTE then
						-- Read single bit (from MISO) and insert it into the data buffer (on every clk rising edge, since we're in mode 0)
						flash_readbuff(flash_readbuff'high - shift_reg_idx) <= miso;
					elsif instruction = INSTR_READ_STATUS1 or instruction = INSTR_READ_STATUS2 then
						-- Read single bit (from MISO) and insert it into the status data buffer (on every clk rising edge, since we're in mode 0)
						flash_status(flash_status'high - shift_reg_idx) <= miso;
					else
						-- The Page is being sent on the falling edge
					end if;
				
				when s_trans_finish =>
					-- We're done with the transaction!
					iob_flash_cs    <= FLASH_CS_DISABLE;
					sck_en          <= '0';
					sck_sched_fall  <= '0';
					shift_reg_idx   <=  0;
					trans_state     <= s_trans_null;
				
					if busy_wait and flash_status(0) = '1' and instruction = INSTR_READ_STATUS1 then
						-- It seems the memory is still busy, we shall keep reading its status register, and then we'll continue
						state <= busy_state;
					else
						if instruction = INSTR_READ_BYTE then
							iob_debug_leds <= flash_readbuff(3 downto 0);
						elsif instruction = INSTR_READ_STATUS1 or instruction = INSTR_READ_STATUS2 then
							iob_debug_leds <= flash_status(3 downto 0);
						end if;
						state <= next_state;
					end if;

				when others => -- Ignore this
			end case;
		end if;
	end procedure;
BEGIN

	-----------------
	-- ASSIGNMENTS --
	-----------------
	debug_leds <= iob_debug_leds;
	flash_cs   <= iob_flash_cs;
	mosi       <= iob_mosi;
	sck        <= clk WHEN (sck_en = '1' and sck_en_fall = '1') ELSE '0'; -- We'll just route the original clk for now
	
	---------------
	-- BEHAVIOUR --
	---------------
	main_proc_rising: process(clk) begin
		if rising_edge(clk) then	
			if reset = '1' then
				state <= s_reset;
			end if;
			
			if sck_en = '1' then
				sck_ctr <= sck_ctr + 1;
			else
				sck_ctr <= 0;
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
					state      <= s_testbench;
	
				when s_idle => -- Do nothing
				
				----------------------------------
				----------------------------------
				---- Make all tests down here ----
				----------------------------------
				----------------------------------
				when s_testbench =>
					state <= s_write_enable_sector; -- We're doing a read status for now
				
				---------------------------------------------------
				-- READ THE TWO STATUS REGISTERS FROM THE FLASH: --
				---------------------------------------------------
				when s_read_status1 =>
					flash_ctrl(
						INSTR_READ_STATUS1, 0, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_read_byte
					);
				when s_read_status2 =>
					flash_ctrl(
						INSTR_READ_STATUS2, 0, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_idle
					);
					
				-----------------------------------------------
				-- READ A SINGLE BYTE FROM THE FLASH MEMORY: --
				-----------------------------------------------
				when s_read_byte =>
					flash_ctrl(
						INSTR_READ_BYTE, 1279, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_idle
					);
				
				------------------------------------------
				-- WAIT FOR THE FLASH WHILE IT IS BUSY: --
				------------------------------------------
				when s_write_wait =>
					flash_ctrl(
						INSTR_READ_STATUS1, 0, 0,
						true, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_read_byte
					);
				when s_sector_erase_wait =>
					flash_ctrl(
						INSTR_READ_STATUS1, 0, 0,
						true, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_sector_erase_wait,
						s_write_enable
					);
				
				------------------------------------
				-- ENABLE WRITING OF FLASH MEMORY --
				------------------------------------
				when s_write_enable => 
					flash_ctrl(
						INSTR_WRITE_ENABLE, 0, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_write_page
					);
				when s_write_enable_sector =>
					flash_ctrl(
						INSTR_WRITE_ENABLE, 0, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_sector_erase
					);
				
				--------------------------------------------------------
				-- WRITE A WHOLE PAGE (256 BYTES) TO THE FLASH MEMORY --
				--------------------------------------------------------
				when s_write_page =>
					flash_ctrl(
						INSTR_WRITE_PAGE, 1024, 12,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_write_wait
					);	
				
				when s_sector_erase =>
					flash_ctrl(
						INSTR_SECTOR_ERASE, 0, 0,
						false, flash_status, flash_opcode, flash_addr, iob_flash_cs, trans_state, shift_reg_idx, sck_en, sck_sched_fall, flash_readbuff, flash_writebuff, miso, iob_debug_leds, state, s_write_wait,
						s_sector_erase_wait
					);	
				
				when others => state <= s_idle;				
			end case;
		end if;
	end process;
	
	main_proc_falling: process(clk) begin
		if falling_edge(clk) then		
			-- Write to MOSI on Falling Edge:
			case trans_state is
				when s_trans_opcode => 
					iob_mosi <= flash_opcode(flash_opcode'high - shift_reg_idx);
				when s_trans_addr =>
					iob_mosi <= flash_addr(flash_addr'high - shift_reg_idx);
				when s_trans_data =>
					if state = s_write_page then
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