LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY MIOSystem_tb IS
	PORT(
		CLK         : in    std_logic;
		SDRAM_CKE   : out   std_logic;
		SDRAM_CLK   : out   std_logic;
		SDRAM_CS_N  : out   std_logic;
		SDRAM_WE_N  : out   std_logic;
		SDRAM_CAS_N : out   std_logic;
		SDRAM_RAS_N : out   std_logic;
		SDRAM_A0    : out   std_logic;
		SDRAM_A1    : out   std_logic;
		SDRAM_A2    : out   std_logic;
		SDRAM_A3    : out   std_logic;
		SDRAM_A4    : out   std_logic;
		SDRAM_A5    : out   std_logic;
		SDRAM_A6    : out   std_logic;
		SDRAM_A7    : out   std_logic;
		SDRAM_A8    : out   std_logic;
		SDRAM_A9    : out   std_logic;
		SDRAM_A10   : out   std_logic;
		SDRAM_A11   : out   std_logic;
		SDRAM_A12   : out   std_logic;
		SDRAM_BA0   : out   std_logic;
		SDRAM_BA1   : out   std_logic;
		SDRAM_DQML  : out   std_logic;
		SDRAM_DQMH  : out   std_logic;
		SDRAM_DQ0   : inout std_logic;
		SDRAM_DQ1   : inout std_logic;
		SDRAM_DQ2   : inout std_logic;
		SDRAM_DQ3   : inout std_logic;
		SDRAM_DQ4   : inout std_logic;
		SDRAM_DQ5   : inout std_logic;
		SDRAM_DQ6   : inout std_logic;
		SDRAM_DQ7   : inout std_logic;
		SDRAM_DQ8   : inout std_logic;
		SDRAM_DQ9   : inout std_logic;
		SDRAM_DQ10  : inout std_logic;
		SDRAM_DQ11  : inout std_logic;
		SDRAM_DQ12  : inout std_logic;
		SDRAM_DQ13  : inout std_logic;
		SDRAM_DQ14  : inout std_logic;
		SDRAM_DQ15  : inout std_logic;
		RXD         : out   std_logic; -- RXD is OUT and !!NOT!! IN
		TXD         : in    std_logic; -- TXD IS IN  and !!NOT!! OUT
		FLASH_CS    : out   std_logic; -- /SS (Drive)
		FLASH_DO    : in    std_logic; -- MISO (Read)
		FLASH_WP    : out   std_logic;
		FLASH_CLK   : out   std_logic; -- SCK (Drive)
		FLASH_DI    : out   std_logic; -- MOSI (Drive)
		DS_DP       : out   std_logic;
		DS_G        : out   std_logic;
		DS_C        : out   std_logic;
		DS_D        : out   std_logic
	);
END MIOSystem_tb;

ARCHITECTURE RTL OF MIOSystem_tb IS
	signal z : boolean := false;
	signal leds : std_logic_vector(3 downto 0) := (others => '0'); -- Drive
	
	-- Restart System Wire:
	signal restart_system : std_logic := '0'; -- Drive
	
	-- PLL:
	signal pll_running : std_logic := '0';
	signal pll_out_clk : std_logic := '0';
	signal pll_reset   : std_logic := '0';
	
	-- FSM:
	type fsm_t is (
		s_init_pll,
		s_init,
		s_init_wait,
		s_idle
	);
	signal state : fsm_t := s_init_pll;
	attribute FSM_ENCODING : string;
	attribute FSM_ENCODING of state : signal is "ONE-HOT";
	
	-----------------------
	------- SDRAM ---------
	-----------------------
	-- SDRAM Controller Wires:
	signal sdram_cmd_ready   : std_logic; -- Read
	signal sdram_cmd_en      : std_logic; -- Drive
	signal sdram_cmd_wr      : std_logic; -- Drive
	signal sdram_cmd_address : std_logic_vector(22 downto 0); -- Drive
	signal sdram_cmd_byte_en : std_logic_vector(3  downto 0); -- Drive
	signal sdram_cmd_data_in : std_logic_vector(31 downto 0); -- Drive
	signal sdram_data_out    : std_logic_vector(31 downto 0); -- Read
	signal sdram_data_ready  : std_logic; -- Read
	
	-- Physical SDRAM Wires:
	signal sdram_an    : std_logic_vector(12 downto 0);
	signal sdram_ban   : std_logic_vector(1  downto 0);
	signal sdram_dqmhl : std_logic_vector(1  downto 0);
	signal sdram_dqn   : std_logic_vector(15 downto 0);
	------------------------------------------------------
	------------------------------------------------------
	
	-----------------------------------------
	------- Flash Memory Controller ---------
	-----------------------------------------
	signal fmem_reset_done  : std_logic;
	signal fmem_enable      : std_logic;
	signal fmem_ready       : std_logic;
	signal fmem_instruction : integer;
	signal fmem_address     : integer;
	signal fmem_data_write  : std_logic_vector(256*8-1 downto 0);
	signal fmem_data_read   : std_logic_vector(4*8-1   downto 0);
	signal fmem_status      : std_logic_vector(7       downto 0);
	------------------------------------------------------
	------------------------------------------------------
	
	---------------------------------
	------- UART Controller ---------
	---------------------------------
	signal uart_write     : std_logic; -- Drive
	signal uart_writedata : std_logic_vector(7 downto 0); -- Drive
	signal uart_readdata  : std_logic_vector(7 downto 0); -- Read
	signal uart_write_irq : std_logic; -- Write IRQ (Read)
	signal uart_read_irq  : std_logic; -- Read  IRQ (Read)
	------------------------------------------------------
	------------------------------------------------------

	---------------------------
	------- UART Link ---------
	---------------------------
	signal uart_link_enable : std_logic := '0';
	signal uart_link_ready  : std_logic := '0';
	------------------------------------------------------
	------------------------------------------------------
	
	-- Dummy CPU Wires: --
	signal dummy_sdram_cmd_en      : std_logic := '0';
	signal dummy_sdram_cmd_wr      : std_logic := '0';
	signal dummy_sdram_cmd_address : std_logic_vector(22 downto 0) := (others => '0');
	signal dummy_sdram_cmd_byte_en : std_logic_vector(3  downto 0) := (others => '0');
	signal dummy_sdram_cmd_data_in : std_logic_vector(31 downto 0) := (others => '0');

BEGIN
	(DS_D, DS_C, DS_G, DS_DP) <= not leds;
	
	-- PLL Instantiation:
	pll_inst : ENTITY work.pll PORT MAP (
		areset => pll_reset,
		inclk0 => CLK, -- PLL Input is a 48 MHz Clock signal
		c0	    => pll_out_clk -- PLL Output is a 130 MHz Clock signal
	);
	
	-- SDRAM Controller Instantiation:
	DRAM_Controller1 : ENTITY work.DRAM_Controller 
		PORT MAP(
			pll_out_clk, restart_system, sdram_cmd_ready, sdram_cmd_en, 
			sdram_cmd_wr, sdram_cmd_address, sdram_cmd_byte_en, 
			sdram_cmd_data_in, sdram_data_out, sdram_data_ready, 
			sdram_cke, sdram_clk, sdram_cs_n, sdram_we_n, sdram_cas_n,
			sdram_ras_n, sdram_an, sdram_ban, sdram_dqmhl, sdram_dqn
		);
	
	-- SDRAM Wire Assignments (it's organized in this confusing way on purpose because it's compact):
	sdram_a0 <= sdram_an(0); sdram_a1 <= sdram_an(1); sdram_a2 <= sdram_an(2); sdram_a3 <= sdram_an(3);
	sdram_a4 <= sdram_an(4); sdram_a5 <= sdram_an(5); sdram_a6 <= sdram_an(6); sdram_a7 <= sdram_an(7);
	sdram_a8 <= sdram_an(8); sdram_a9 <= sdram_an(9); sdram_a10 <= sdram_an(10); sdram_a11 <= sdram_an(11);
	sdram_a12 <= sdram_an(12); SDRAM_DQMH <= sdram_dqmhl(0); SDRAM_DQML <= sdram_dqmhl(1); SDRAM_BA0 <= sdram_ban(0);
	SDRAM_BA1 <= sdram_ban(1); sdram_dq0 <= sdram_dqn(0); sdram_dq1 <= sdram_dqn(1); sdram_dq2 <= sdram_dqn(2);
	sdram_dq3 <= sdram_dqn(3); sdram_dq4 <= sdram_dqn(4); sdram_dq5 <= sdram_dqn(5); sdram_dq6 <= sdram_dqn(6);
	sdram_dq7 <= sdram_dqn(7); sdram_dq8 <= sdram_dqn(8); sdram_dq9 <= sdram_dqn(9); sdram_dq10 <= sdram_dqn(10);
	sdram_dq11 <= sdram_dqn(11); sdram_dq12 <= sdram_dqn(12); sdram_dq13 <= sdram_dqn(13); sdram_dq14 <= sdram_dqn(14); sdram_dq15 <= sdram_dqn(15);
	
	-- Flash Memory Instantiation:
	FLASHMEM_Controller1: ENTITY work.FLASHMEM_Controller PORT MAP (
		CLK, restart_system, fmem_reset_done, fmem_enable, fmem_ready, fmem_instruction, fmem_address, fmem_data_write, fmem_data_read, fmem_status,
		FLASH_CS, FLASH_DO, FLASH_DI, FLASH_CLK
	);
	
	FLASH_WP <= '1'; -- We don't want to mess with Write Protection
	
	-- UART Controller Instantiation:
	UART_Controller1 : ENTITY work.UART_Controller
		GENERIC MAP(
			baud            => 128000,  -- Set the Baud Rate to 128Kbits/s
			clock_frequency => 48000000 -- We'll use the orginal 48MHz clock
		)
		PORT MAP (
			clock               => CLK,
			reset               => restart_system,
			data_stream_in      => uart_writedata,
			data_stream_in_stb  => uart_write,
			data_stream_in_ack  => uart_write_irq,
			data_stream_out     => uart_readdata,
			data_stream_out_stb => uart_read_irq,
			tx                  => RXD, -- Notice the twisted connections
			rx                  => TXD  -- Notice the twisted connections
		);
	
	-- UART Link Instantiation:
	UART_Link1: ENTITY work.UART_Link
		PORT MAP (
			CLK, pll_out_clk, pll_running, uart_link_enable, uart_link_ready,
			sdram_cmd_ready, sdram_cmd_en, sdram_cmd_wr, sdram_cmd_address, sdram_cmd_byte_en, sdram_cmd_data_in, sdram_data_out, sdram_data_ready,
			dummy_sdram_cmd_en, dummy_sdram_cmd_wr, dummy_sdram_cmd_address, dummy_sdram_cmd_byte_en, dummy_sdram_cmd_data_in,
			fmem_enable, fmem_ready, fmem_instruction, fmem_address, fmem_data_write, fmem_data_read, fmem_status,
			uart_write, uart_writedata, uart_readdata, uart_write_irq, uart_read_irq
		);
	
	-------------------------
	-- Top level behaviour --
	-------------------------
	process(CLK) begin
		if rising_edge(CLK) then
			if pll_out_clk = '1' then
				pll_running <= '1';
			end if;
			
			-- System Initialization FSM Algorithm: --
			case state is
				when s_init_pll => -- Initialize PLL output clock
					pll_reset <= '1';
					state     <= s_init;
					
				when s_init => -- Initialize everything else
					restart_system <= '1';
					pll_reset      <= '0';
					state          <= s_init_wait;
					
				when s_init_wait => -- Wait for system startup to finish
					restart_system <= '0';
					-- Wait for the SDRAM and Flash Memory to initialize:
					if sdram_cmd_ready = '1' and fmem_reset_done = '1' then
						uart_link_enable <= '1'; -- Let the UART Link module initialize
						if uart_link_ready = '1' then
							-- The UART Link is now ready to receive, transmit and control devices through UART Communication
							state <= s_idle; -- Enter idle state and let the components make transactions with each other 
						end if;
					end if;
					
				when s_idle => -- Do nothing
				when others => state <= s_idle;
			end case;
		end if;
	end process;

END ARCHITECTURE RTL;