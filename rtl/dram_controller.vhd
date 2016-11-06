LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

--------------------------------------------------------------------------------------
-- Reference: http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller --
--------------------------------------------------------------------------------------

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
		data_out    : out std_logic_vector(31 downto 0) := (others => '0');
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
   -- From page 37 of MT48LC16M16A2 Datasheet:
   -- Name (Function)       CS# RAS# CAS# WE# DQM  Addr    Data
   -- COMMAND INHIBIT (NOP)  H   X    X    X   X     X       X
   -- NO OPERATION (NOP)     L   H    H    H   X     X       X
   -- ACTIVE                 L   L    H    H   X  Bank/row   X
   -- READ                   L   H    L    H  L/H Bank/col   X
   -- WRITE                  L   H    L    L  L/H Bank/col Valid
   -- BURST TERMINATE        L   H    H    L   X     X     Active
   -- PRECHARGE              L   L    H    L   X   Code      X
   -- AUTO REFRESH           L   L    L    H   X     X       X 
   -- LOAD MODE REGISTER     L   L    L    L   X  Op-code    X 
   -- Write enable           X   X    X    X   L     X     Active
   -- Write inhibit          X   X    X    X   H     X     High-Z

   -- Here are the commands mapped to constants:   
   constant CMD_UNSELECTED    : std_logic_vector(3 downto 0) := "1000";
   constant CMD_NOP           : std_logic_vector(3 downto 0) := "0111";
   constant CMD_ACTIVE        : std_logic_vector(3 downto 0) := "0011";
   constant CMD_READ          : std_logic_vector(3 downto 0) := "0101";
   constant CMD_WRITE         : std_logic_vector(3 downto 0) := "0100";
   constant CMD_TERMINATE     : std_logic_vector(3 downto 0) := "0110";
   constant CMD_PRECHARGE     : std_logic_vector(3 downto 0) := "0010";
   constant CMD_REFRESH       : std_logic_vector(3 downto 0) := "0001";
   constant CMD_LOAD_MODE_REG : std_logic_vector(3 downto 0) := "0000";

   constant MODE_REG          : std_logic_vector(12 downto 0) := 
    -- Reserved, wr bust, OpMode, CAS Latency (2), Burst Type, Burst Length (2)
         "000" &   "0"  &  "00"  &    "010"      &     "0"    &   "001";

   signal iob_command : std_logic_vector( 3 downto 0) := CMD_NOP;
   signal iob_address : std_logic_vector(12 downto 0) := (others => '0');
   signal iob_data    : std_logic_vector(15 downto 0) := (others => '0');
   signal iob_dqm     : std_logic_vector( 1 downto 0) := (others => '0');
   signal iob_cke     : std_logic := '0';
   signal iob_bank    : std_logic_vector( 1 downto 0) := (others => '0');
    
   signal captured_data      : std_logic_vector(15 downto 0) := (others => '0');
   signal captured_data_last : std_logic_vector(15 downto 0) := (others => '0');
   signal sdram_din          : std_logic_vector(15 downto 0);
   
   type fsm_state is (
		s_startup,
      s_idle_in_9, s_idle_in_8, s_idle_in_7, s_idle_in_6,   
      s_idle_in_5, s_idle_in_4, s_idle_in_3, s_idle_in_2, 
		s_idle_in_1, s_idle,
      s_open_in_2, s_open_in_1,
      s_write_1, s_write_2, s_write_3,
      s_read_1,  s_read_2,  s_read_3,  s_read_4,  
      s_precharge
   );

   signal state : fsm_state := s_startup;
	attribute FSM_ENCODING : string;
	attribute FSM_ENCODING of state : signal is "ONE-HOT";
   signal startup_wait_count : unsigned(15 downto 0) := to_unsigned(10100,16);
   
   signal refresh_count   : unsigned(9 downto 0) := (others => '0');
   signal pending_refresh : std_logic := '0';
   constant refresh_max   : unsigned(9 downto 0) := to_unsigned(3200000/8192-1,10);  -- 8192 refreshes every 64ms (@ 100MHz)
   
   signal addr_row        : std_logic_vector(12 downto 0);
   signal addr_col        : std_logic_vector(12 downto 0);
   signal addr_bank       : std_logic_vector( 1 downto 0);
   
   -- signals to hold the requested transaction
   signal save_wr         : std_logic := '0';
   signal save_row        : std_logic_vector(12 downto 0);
   signal save_bank       : std_logic_vector( 1 downto 0);
   signal save_col        : std_logic_vector(12 downto 0);
   signal save_d_in       : std_logic_vector(31 downto 0);
   signal save_byte_en    : std_logic_vector( 3 downto 0);
   
   signal iob_dq_hiz      : std_logic_vector(15 downto 0) := (others => '0');

   -- signals for when to read the data off of the bus
   signal data_ready_delay : std_logic_vector(4 downto 0);
   
   signal ready_for_new    : std_logic := '0';
   signal got_transaction  : std_logic := '0';
	
	-- Misc Wires:
	constant zero    : std_logic := '0';
	constant one     : std_logic := '1';
begin   
	-- Tell the outside world when we can accept a new transaction:
   cmd_ready <= ready_for_new;

   ----------------------------------------------------------------------------
   -- Separate the address into row / bank / address
   -- fot the x16 part, columns are addr(8:0).
   -- for 32 bit (2 word bursts), the lowest bit will be controlled by the FSM
   ----------------------------------------------------------------------------
   addr_row  <= cmd_address(21 downto  9);  
   addr_bank <= cmd_address( 8 downto  7);
   addr_col  <= "00000" & cmd_address( 6 downto  0) & '0';

   -------------------------------------------------------------------
   -- Forward the SDRAM clock to the SDRAM chip - 180 degrees
   -- out of phase with the control signals (ensuring setup and holdup 
   --------------------------------------------------------------------
   sdram_clk <= not clk;
 
   -----------------------------------------------
   --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   --!! Ensure that all outputs are registered. !!
   --!! Check the pinout report to be sure      !!
   --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   -----------------------------------------------
   sdram_cke   <= iob_cke;
   sdram_CS_n  <= iob_command(3);
   sdram_RAS_n <= iob_command(2);
   sdram_CAS_n <= iob_command(1);
   sdram_WE_n  <= iob_command(0);
   sdram_dqmhl <= iob_dqm;
   sdram_ban   <= iob_bank;
   sdram_an    <= iob_address;  
	iob_dq_iob : ENTITY work.iobuf 
		PORT MAP(iob_data, iob_dq_hiz, sdram_dqn, sdram_din); 

-- Data capture FROM SDRAM Process:		
capture_proc: process(clk) 
   begin
     if clk'event and clk = '0' then
         captured_data <= sdram_din;
      end if;
   end process;

-- Main Process:
main_proc: process(clk) 
   begin
      if clk'event and clk = '1' then
         captured_data_last <= captured_data;
      
         ------------------------------------------------
         -- Default state is to do nothing --------------
         ------------------------------------------------
         iob_command <= CMD_NOP;
         iob_address <= (others => '0');
         iob_bank    <= (others => '0');
         iob_dqm     <= (others => '1');  

         -- Countdown for initialisation:
         startup_wait_count <= startup_wait_count-1;
         
         -- Logic to decide when to refresh:
         if refresh_count /= refresh_max then
            refresh_count <= refresh_count + 1;
         else
            refresh_count <= (others => '0');
            if state /= s_startup then
               pending_refresh <= '1';
            end if;
         end if;
         
         ---------------------------------------------
         -- If we are ready for a new transaction 
         -- and one is being presented, then accept it
         -- remember what we are reading or writing
         ---------------------------------------------
         if ready_for_new = '1' and cmd_en = '1' then
            save_row         <= addr_row;
            save_bank        <= addr_bank;
            save_col         <= addr_col;
            save_wr          <= cmd_wr; 
            save_d_in        <= cmd_data_in;
            save_byte_en     <= cmd_byte_en;
            got_transaction  <= '1';
            ready_for_new    <= '0';
         end if;

         ------------------------------------------------
         -- Read transactions are completed when the last
         -- word of data has been latched. Writes are 
         -- completed when the data has been sent
         ------------------------------------------------
         data_ready <= '0';
         if data_ready_delay(0) = '1' then
            data_out <= captured_data & captured_data_last;
            data_ready <= '1';
         end if;

         -- Update shift registers used to present data read from memory
         data_ready_delay <= '0' & data_ready_delay(data_ready_delay'high downto 1);
         
         -- Algorithm with FSM:
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
               
               if startup_wait_count = 21 then      
                   -- ensure all rows are closed
                  iob_command     <= CMD_PRECHARGE;
                  iob_address(10) <= '1';  -- all banks
                  iob_bank        <= (others => '0');
               elsif startup_wait_count = 18 then   
                  -- these refreshes need to be at least tREF (66ns) apart
                  iob_command     <= CMD_REFRESH;
               elsif startup_wait_count = 11 then
                  iob_command     <= CMD_REFRESH;
               elsif startup_wait_count = 4 then    
                  -- Now load the mode register
                  iob_command     <= CMD_LOAD_MODE_REG;
                  iob_address     <= MODE_REG;
               else
                  iob_command     <= CMD_NOP;
               end if;

               pending_refresh    <= '0';

               if startup_wait_count = 0 then
                  state           <= s_idle;
                  ready_for_new   <= '1';
                  got_transaction <= '0';
               end if;
            when s_idle_in_9 => state <= s_idle_in_8;
            when s_idle_in_8 => state <= s_idle_in_7;
            when s_idle_in_7 => state <= s_idle_in_6;
            when s_idle_in_6 => state <= s_idle_in_5;
            when s_idle_in_5 => state <= s_idle_in_4;
            when s_idle_in_4 => state <= s_idle_in_3;
            when s_idle_in_3 => state <= s_idle_in_2;
            when s_idle_in_2 => state <= s_idle_in_1;
            when s_idle_in_1 => state <= s_idle;

            when s_idle =>
               -- Priority is to issue a refresh if one is outstanding
               if pending_refresh = '1' then
                 ------------------------------------------------------------------------
                  -- Start the refresh cycle. 
                  -- This tasks tRFC (66ns), so 6 idle cycles are needed @ 100MHz
                  ------------------------------------------------------------------------
                  state            <= s_idle_in_6;
                  iob_command      <= CMD_REFRESH;
                  pending_refresh  <= '0';
               elsif got_transaction = '1' then
                  --------------------------------
                  -- Start the read or write cycle. 
                  -- First task is to open the row
                  --------------------------------
                  state       <= s_open_in_2;
                  iob_command <= CMD_ACTIVE;
                  iob_address <= save_row;
                  iob_bank    <= save_bank;
               end if;               
            ------------------------------------------
            -- Opening the row ready for read or write
            ------------------------------------------
            when s_open_in_2 => state <= s_open_in_1;

            when s_open_in_1 =>
               -- still waiting for row to open
               if save_wr = '1' then
                  state           <= s_write_1;
                  iob_dq_hiz      <= (others => '1');
                  iob_data        <= save_d_in(15 downto 0); -- get the DQ bus out of HiZ early
               else
                  iob_dq_hiz      <= (others => '0');
                  state           <= s_read_1;
                  ready_for_new   <= '1'; -- we will be ready for a new transaction next cycle!
                  got_transaction <= '0';
               end if;

            ----------------------------------
            -- Processing the read transaction
            ----------------------------------
            when s_read_1 =>
               state           <= s_read_2;
               iob_command     <= CMD_READ;
               iob_address     <= save_col; 
               iob_address(10) <= '0'; -- A10 actually matters - it selects auto prefresh
               iob_bank        <= save_bank;
               
               -- Schedule reading the data values off the bus
               data_ready_delay(data_ready_delay'high) <= '1';
               
               -- Set the data masks to read all bytes
               iob_dqm         <= (others => '0'); -- For CAS = 2
               
            when s_read_2 =>
               state           <= s_read_3;
               -- Set the data masks to read all bytes
               iob_dqm         <= (others => '0'); -- For CAS = 2 or CAS = 3

            when s_read_3 => state <= s_read_4;
            when s_read_4 => state <= s_precharge;

            -------------------------------------------------------------------
            -- Processing the write transaction
            -------------------------------------------------------------------
            when s_write_1 =>
               state           <= s_write_2;
               iob_command     <= CMD_WRITE;
               iob_address     <= save_col; 
               iob_address(10) <= '0'; -- A10 actually matters - it selects auto prefresh
               iob_bank        <= save_bank;
               iob_dqm         <= NOT save_byte_en(1 downto 0);    
               iob_data        <= save_d_in(15 downto 0);
               ready_for_new   <= '1';
               got_transaction <= '0';
					
            when s_write_2 =>
               state           <= s_write_3;
               iob_dqm         <= NOT save_byte_en(3 downto 2);    
               iob_data        <= save_d_in(31 downto 16);
         
            when s_write_3 =>  -- must wait tRDL, hence the extra idle state
               iob_dq_hiz      <= (others => '0');
               state           <= s_precharge;

            -------------------------------------------------------------------
            -- Closing the row off (this closes all banks)
            -------------------------------------------------------------------
            when s_precharge =>
               state           <= s_idle_in_9;
               iob_command     <= CMD_PRECHARGE;
               iob_address(10) <= '1'; -- A10 actually matters - it selects all banks or just one

            -------------------------------------------------------------------
            -- We should never get here, but if we do then reset the memory
            -------------------------------------------------------------------
            when others => 
               state <= s_startup;
               ready_for_new      <= '0';
               startup_wait_count <= to_unsigned(10100,16);
         end case;
         
         -- Sync reset
         if reset = '1' then
            state              <= s_startup;
            ready_for_new      <= '0';
            startup_wait_count <= to_unsigned(10100,16);
         end if;
      end if;      
   end process;
END ARCHITECTURE RTL;