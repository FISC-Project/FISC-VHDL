LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY ODDR2 IS
	PORT(
		clk : in std_logic;
		q   : out std_logic;
		c0  : in std_logic;
		c1  : in std_logic;
		d0  : in std_logic;
		d1  : in std_logic
	);
END ODDR2;

ARCHITECTURE RTL OF ODDR2 IS
	signal d0_reg : std_logic := '0';
	signal d1_reg : std_logic := '0';
BEGIN
	q <= d0_reg WHEN c0 = '1' AND c1 = '0' ELSE d1_reg WHEN c0 = '0' AND c1 = '1' ELSE 'X';
	
	process(clk) begin
		if clk'event and clk = '1' then
			d0_reg <= d0;
			d1_reg <= d1;
		end if;
	end process;
END ARCHITECTURE RTL;

------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY IOBUF IS
	PORT(
		O  : out   std_logic;
		IO : inout std_logic;
		I  : in    std_logic;
		T  : in    std_logic
	);
END ENTITY;

ARCHITECTURE RTL OF IOBUF IS
BEGIN
	process(IO, T) begin
		if T = '1' then -- Act as input
			IO <= 'Z';
		else -- Act as output
			IO <= I;
		end if;
		O <= IO;
	end process;
END ARCHITECTURE RTL;

------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Reference: http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller

ENTITY DRAM_Controller IS
	PORT(
		clk   : in std_logic;
		reset : in std_logic;
		
		-- Command Interface:
		cmd_ready   : out std_logic;
		cmd_en      : in  std_logic;
		cmd_wr      : in  std_logic;
		cmd_address : in  std_logic_vector(22 downto 0);
		cmd_byte_en : in  std_logic_vector(3  downto 0);
		cmd_data_in : in  std_logic_vector(31 downto 0);
		
		-- Data returned from SDRAM:
		data_out    : out std_logic_vector(31 downto 0);
		data_ready  : out std_logic;
		
		-- SDRAM Control signals:
		sdram_cke   : out   std_logic;
		sdram_clk   : out   std_logic;
		sdram_cs_n  : out   std_logic;
		sdram_we_n  : out   std_logic;
		sdram_cas_n : out   std_logic;
		sdram_ras_n : out   std_logic;
		sdram_an    : out   std_logic_vector(12 downto 0);
		sdram_ban   : out   std_logic_vector(1  downto 0);
		sdram_dqmhl : out   std_logic_vector(1  downto 0);
		sdram_dqn   : inout std_logic_vector(15 downto 0)
	);
END DRAM_Controller;

ARCHITECTURE RTL OF DRAM_Controller IS
	constant sdram_column_bits   : natural := 8;
	constant sdram_address_width : natural := 22;
	constant sdram_startup_cycles: natural := 10; --10100;
	constant cycles_per_refresh  : natural := (64000*100)/4196-1;

	-- SDRAM Supported Commands (fmt: CS | RAS | CAS | WE):
	constant CMD_UNSELECTED    : std_logic_vector(3 downto 0)  := "1000";
	constant CMD_NOP           : std_logic_vector(3 downto 0)  := "0111";
	constant CMD_ACTIVE        : std_logic_vector(3 downto 0)  := "0011";
	constant CMD_READ          : std_logic_vector(3 downto 0)  := "0101";
	constant CMD_WRITE         : std_logic_vector(3 downto 0)  := "0100";
	constant CMD_TERMINATE     : std_logic_vector(3 downto 0)  := "0110";
	constant CMD_PRECHARGE     : std_logic_vector(3 downto 0)  := "0010";
	constant CMD_REFRESH       : std_logic_vector(3 downto 0)  := "0001";
	constant CMD_LOAD_MODE_REG : std_logic_vector(3 downto 0)  := "0000";
	constant MODE_REG          : std_logic_vector(12 downto 0) := 
    -- Reserved, wr bust, OpMode, CAS Latency (2), Burst Type, Burst Length (2)
         "000" &   "0"  &  "00"  &    "010"      &     "0"    &   "001";
	
	-- Physical DRAM Pins:
	signal iob_cmd     : std_logic_vector(3 downto 0)  := CMD_NOP;
	signal iob_address : std_logic_vector(12 downto 0) := (others => '0');
	signal iob_data    : std_logic_vector(15 downto 0) := (others => '0');
	signal iob_dqm     : std_logic_vector(1 downto 0)  := (others => '0');
	signal iob_cke     : std_logic := '0';
	signal iob_bank    : std_logic_vector(1 downto 0)  := (others => '0');
	
	-- Data capturing signals:
	signal iob_data_next      : std_logic_vector(15 downto 0) := (others => '0');
	signal captured_data      : std_logic_vector(15 downto 0) := (others => '0');
	signal captured_data_last : std_logic_vector(15 downto 0) := (others => '0');
	signal sdram_din          : std_logic_vector(15 downto 0);
	signal iob_dq_hiz         : std_logic := '1';
	
	type fsm_state is (
		s_startup,
		s_idle_in_9, s_idle_in_8, s_idle_in_7,
		s_idle_in_6, s_idle_in_5, s_idle_in_4,
		s_idle_in_3, s_idle_in_2, s_idle_in_1,
		s_idle,
		s_open_in_2, s_open_in_1,
		s_write_1, s_write_2, s_write_3,
		s_read_1, s_read_2, s_read_3, s_read_4,
		s_precharge
	);
	
	-- Current state of the DRAM Controller:
	signal state : fsm_state := s_startup; -- Startup state
	attribute FSM_ENCODING : string;
	attribute FSM_ENCODING of state : signal is "ONE-HOT";
   
	-- Refresh Signals:
	-- dual purpose counter, it counts up during the startup phase, then is used to trigger refreshes.
	constant startup_refresh_max   : unsigned(13 downto 0) := (others => '1');  
	signal   startup_refresh_count : unsigned(13 downto 0) := startup_refresh_max-to_unsigned(sdram_startup_cycles, 14);
	signal   pending_refresh       : std_logic := '0'; -- Preload value 'startup_refresh_count' asserts this signal
	signal   forcing_refresh       : std_logic := '0';
	
	-- Addressing Signals which derive from the 22 bit address:
	signal addr_row  : std_logic_vector(12 downto 0) := (others => '0');
	signal addr_col  : std_logic_vector(12 downto 0) := (others => '0');
	signal addr_bank : std_logic_vector(1  downto 0) := (others => '0');
	signal dqm_sr    : std_logic_vector(3  downto 0) := (others => '1'); -- an extra two bits in case CAS=3 

	-- Signals to hold the requested transaction:
	signal save_wr          : std_logic := '0';
	signal save_row         : std_logic_vector(12 downto 0);
	signal save_bank        : std_logic_vector(1  downto 0);
	signal save_col         : std_logic_vector(12 downto 0);
	signal save_d_in        : std_logic_vector(31 downto 0);
	signal save_byte_enable : std_logic_vector(3  downto 0);
	
	-- Transaction Control Signals:
	signal data_ready_delay : std_logic_vector(3 downto 0);
	signal ready_for_new    : std_logic := '0';
	signal got_transaction  : std_logic := '0';
	signal can_back_to_back : std_logic := '0';
	
	-- Bit indexes used when splitting the address into row/colum/bank.
	constant start_of_col  : natural := 0;
	constant end_of_col    : natural := sdram_column_bits-2;
	constant start_of_bank : natural := sdram_column_bits-1;
	constant end_of_bank   : natural := sdram_column_bits;
	constant start_of_row  : natural := sdram_column_bits+1;
	constant end_of_row    : natural := sdram_address_width-2;
	constant prefresh_cmd  : natural := 10;
	
	-- Misc Wires:
	constant zero    : std_logic := '0';
	constant one     : std_logic := '1';
	signal   not_clk : std_logic;
BEGIN
	not_clk   <= not clk;
	
	-- Indicate the need to refresh when the counter is 2048,
	-- Force a refresh when the counter is 4096 - (if a refresh is forced, 
	-- multiple refresshes will be forced until the counter is below 2048
	pending_refresh <= startup_refresh_count(11);
	forcing_refresh <= startup_refresh_count(12);
	
	-- Indicate the CPU when the complete data transaction has completed:
	cmd_ready <= ready_for_new;
	
   ----------------------------------------------------------------------------
   -- Seperate the address into row / bank / address
   ----------------------------------------------------------------------------
   addr_row(end_of_row-start_of_row downto 0) <= cmd_address(end_of_row  downto start_of_row);       -- 12:0 <=  22:10
   addr_bank                                  <= cmd_address(end_of_bank downto start_of_bank);      -- 1:0  <=  9:8
   addr_col(sdram_column_bits-1 downto 0)     <= cmd_address(end_of_col  downto start_of_col) & '0'; -- 8:0  <=  7:0 & '0'
	
	-- Shift and Forward SDRAM's clk signal by 180º out of phase:
	sdram_clk_forward : ENTITY work.ODDR2 PORT MAP(clk, sdram_clk, clk, not_clk, zero, one);	
	
	-- Assign SDRAM physical pins to iob pins:
	sdram_cke   <= iob_cke;
	sdram_cs_n  <= iob_cmd(3);
	sdram_ras_n <= iob_cmd(2);
	sdram_cas_n <= iob_cmd(1);
	sdram_we_n  <= iob_cmd(0);
	sdram_dqmhl <= iob_dqm;
	sdram_ban   <= iob_bank;
	sdram_an    <= iob_address;
	-- Generate bidirectional data signals:
	iob_dq_g: for i in 0 to 15 generate
	begin
		iob_dq_iob : ENTITY work.IOBUF PORT MAP(sdram_din(i), sdram_dqn(i), iob_data(i), iob_dq_hiz);
	end generate;
	
	-- Main process:
	main_proc:
	process(clk) begin
		if clk'event and clk = '1' then
			captured_data      <= sdram_din;
			captured_data_last <= captured_data;
			
			-- Set default state:
			iob_cmd     <= CMD_NOP;
			iob_address <= (others => '0');
			iob_bank    <= (others => '0');
			
			-- Update refresh counter:
			startup_refresh_count <= startup_refresh_count + 1;
				
			-------------------------------------------------------------------
			-- If we are ready for a new transaction and one is being presented
			-- then accept it. Also remember what we are reading or writing,
			-- and if it can be back-to-backed with the last transaction
			-------------------------------------------------------------------
			if ready_for_new = '1' and cmd_en = '1' then
				if save_bank = addr_bank and save_row = addr_row then
					can_back_to_back <= '1';
				else
					can_back_to_back <= '0';
				end if;
				save_row         <= addr_row;
				save_bank        <= addr_bank;
				save_col         <= addr_col;
				save_wr          <= cmd_wr; 
				save_d_in        <= cmd_data_in;
				save_byte_enable <= cmd_byte_en;
				got_transaction  <= '1';
				ready_for_new    <= '0';		
			end if;
			
			------------------------------------------------
			-- Handle the data coming back from the 
			-- SDRAM for the Read transaction
			------------------------------------------------
			data_ready <= '0';
			if data_ready_delay(0) = '1' then
				data_out   <= captured_data & captured_data_last; -- Concat two 16 bit numbers into a 32 bit number
				data_ready <= '1'; -- The data is ready to be read by the CPU
			end if;
			
			----------------------------------------------------------------------------
			-- Update shift registers used to choose when to present data to/from memory
			----------------------------------------------------------------------------
			data_ready_delay <= '0' & data_ready_delay(data_ready_delay'high downto 1);
			iob_dqm          <= dqm_sr(1 downto 0);
			dqm_sr           <= "11" & dqm_sr(dqm_sr'high downto 2);
			
			-- Handle the Algorithm using the FSM states:
			case state is
				when s_startup =>
					------------------------------------------------------------------------
					-- This is the initial startup state, where we wait for at least 100us
					-- before starting the start sequence
					-- 
					-- The initialisation is sequence is 
					--  * de-assert SDRAM_CKE
					--  * 100us wait, 
					--  * assert SDRAM_CKE
					--  * wait at least one cycle, 
					--  * PRECHARGE
					--  * wait 2 cycles
					--  * REFRESH, 
					--  * tREF wait
					--  * REFRESH, 
					--  * tREF wait 
					--  * LOAD_MODE_REG 
					--  * 2 cycles wait
					------------------------------------------------------------------------
					iob_CKE <= '1';
					
					-- All the commands during the startup are NOPS, except these
					if startup_refresh_count = startup_refresh_max-31 then      
						-- ensure all rows are closed
						iob_cmd                   <= CMD_PRECHARGE;
						iob_address(prefresh_cmd) <= '1';  -- all banks
						iob_bank                  <= (others => '0');
					elsif startup_refresh_count = startup_refresh_max-23 then   
						-- these refreshes need to be at least tREF (66ns) apart
						iob_cmd                   <= CMD_REFRESH;
					elsif startup_refresh_count = startup_refresh_max-15 then
						iob_cmd                   <= CMD_REFRESH;
					elsif startup_refresh_count = startup_refresh_max-7 then    
						-- Now load the mode register
						iob_cmd                   <= CMD_LOAD_MODE_REG;
						iob_address               <= MODE_REG;
					end if;
					
					------------------------------------------------------
					-- if startup is complete then go into idle mode,
					-- get prepared to accept a new command, and schedule
					-- the first refresh cycle
					------------------------------------------------------
					if startup_refresh_count = 0 then
						state           <= s_idle;
						ready_for_new   <= '1';
						got_transaction <= '0';
						startup_refresh_count <= to_unsigned(2048 - cycles_per_refresh+1,14);
					end if;
			
				when s_idle_in_6 => state <= s_idle_in_5;
				when s_idle_in_5 => state <= s_idle_in_4;
				when s_idle_in_4 => state <= s_idle_in_3;
				when s_idle_in_3 => state <= s_idle_in_2;
				when s_idle_in_2 => state <= s_idle_in_1;
				when s_idle_in_1 => state <= s_idle;
				when s_idle =>
					-- Priority is to issue a refresh if one is outstanding
					if pending_refresh = '1' or forcing_refresh = '1' then
						------------------------------------------------------------------------
						-- Start the refresh cycle. 
						-- This tasks tRFC (66ns), so 6 idle cycles are needed @ 100MHz
						------------------------------------------------------------------------
						state       <= s_idle_in_6;
						iob_cmd     <= CMD_REFRESH;
						startup_refresh_count <= startup_refresh_count - cycles_per_refresh+1;
					elsif got_transaction = '1' then
						--------------------------------
						-- Start the read or write cycle. 
						-- First task is to open the row
						--------------------------------
						state       <= s_open_in_2;
						iob_cmd     <= CMD_ACTIVE;
						iob_address <= save_row;
						iob_bank    <= save_bank;
					end if;
				
				--------------------------------------------
				-- Opening the row ready for reads or writes
				--------------------------------------------
				when s_open_in_2 => state <= s_open_in_1;
				when s_open_in_1 =>
					-- still waiting for row to open
					if save_wr = '1' then
						state       <= s_write_1;
						iob_dq_hiz  <= '0';
						iob_data    <= save_d_in(15 downto 0); -- get the DQ bus out of HiZ early
					else
						iob_dq_hiz  <= '1';
						state       <= s_read_1;
					end if;
					-- we will be ready for a new transaction next cycle!
					ready_for_new   <= '1'; 
					got_transaction <= '0';

				----------------------------------
				-- Processing the Read Transaction
				----------------------------------
				when s_read_1 =>
					state           <= s_read_2;
					iob_cmd         <= CMD_READ;
					iob_address     <= save_col; 
					iob_bank        <= save_bank;
					iob_address(prefresh_cmd) <= '0'; -- A10 actually matters - it selects auto precharge
					  
					-- Schedule reading the data values off the bus
					data_ready_delay(data_ready_delay'high)   <= '1';
					  
					-- Set the data masks to read all bytes
					iob_dqm            <= (others => '0');
					dqm_sr(1 downto 0) <= (others => '0');
               
				when s_read_2 =>
					state <= s_read_3;
					if forcing_refresh = '0' and got_transaction = '1' and can_back_to_back = '1' then
						if save_wr = '0' then
							state           <= s_read_1;
							ready_for_new   <= '1'; -- we will be ready for a new transaction next cycle!
							got_transaction <= '0';
						end if;
					end if;
				
				when s_read_3 =>
					state <= s_read_4;
					if forcing_refresh = '0' and got_transaction = '1' and can_back_to_back = '1' then
						if save_wr = '0' then
							state           <= s_read_1;
							ready_for_new   <= '1'; -- we will be ready for a new transaction next cycle!
							got_transaction <= '0';
						end if;
					end if;
				
				when s_read_4 =>
					state <= s_precharge;
					-- can we do back-to-back read?
					if forcing_refresh = '0' and got_transaction = '1' and can_back_to_back = '1' then
						if save_wr = '0' then
							state           <= s_read_1;
							ready_for_new   <= '1'; -- we will be ready for a new transaction next cycle!
							got_transaction <= '0';
						else
							state <= s_open_in_2; -- we have to wait for the read data to come back before we swutch the bus into HiZ
						end if;
					end if;
	
				----------------------------------
				-- Processing the Write Transaction
				----------------------------------
				when s_write_1 =>
					state              <= s_write_2;
					iob_cmd            <= CMD_WRITE;
					iob_address        <= save_col; 
					iob_address(prefresh_cmd) <= '0'; -- A10 actually matters - it selects auto precharge
					iob_bank           <= save_bank;
					iob_dqm            <= NOT save_byte_enable(1 downto 0);    
					dqm_sr(1 downto 0) <= NOT save_byte_enable(3 downto 2);    
					iob_data           <= save_d_in(15 downto 0);
					iob_data_next      <= save_d_in(31 downto 16);

				when s_write_2 =>
					state    <= s_write_3;
					iob_data <= iob_data_next;
					-- can we do a back-to-back write?
					if forcing_refresh = '0' and got_transaction = '1' and can_back_to_back = '1' then
						if save_wr = '1' then
							-- back-to-back write?
							state           <= s_write_1;
							ready_for_new   <= '1';
							got_transaction <= '0';
						end if;
						-- Although it looks right in simulation you can't go write-to-read 
						-- here due to bus contention, as iob_dq_hiz takes a few ns.
					end if;
					
				when s_write_3 =>
					-- back to back transaction?
					if forcing_refresh = '0' and got_transaction = '1' and can_back_to_back = '1' then
						if save_wr = '1' then
							-- back-to-back write?
							state           <= s_write_1;
							ready_for_new   <= '1';
							got_transaction <= '0';
						else
							-- write-to-read switch?
							state           <= s_read_1;
							iob_dq_hiz      <= '1';
							ready_for_new   <= '1'; -- we will be ready for a new transaction next cycle!
							got_transaction <= '0';                  
						end if;
					else
						iob_dq_hiz         <= '1';
						state              <= s_precharge;
					end if;

				-------------------------------------------------------------------
				-- Closing the row off (this closes all banks)
				-------------------------------------------------------------------
				when s_precharge =>
					state                     <= s_idle_in_3;
					iob_cmd                   <= CMD_PRECHARGE;
					iob_address(prefresh_cmd) <= '1'; -- A10 actually matters - it selects all banks or just one 
				
				-------------------------------------------------------------------
				-- We should never get here, but if we do then reset the memory
				-------------------------------------------------------------------
				when others => 
					state                 <= s_startup;
					ready_for_new         <= '0';
					startup_refresh_count <= startup_refresh_max - to_unsigned(sdram_startup_cycles, 14);
			end case;
			
			-- Handle reset trigger:
			if reset = '1' then
				state                 <= s_startup;
				ready_for_new         <= '0';
				startup_refresh_count <= startup_refresh_max - to_unsigned(sdram_startup_cycles, 14);
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;