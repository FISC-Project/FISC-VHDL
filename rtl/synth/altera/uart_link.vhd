LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY UART_Link IS
	PORT(
		leds        : out std_logic_vector(3 downto 0) := (others => '0'); -- TODO: TEMPORARY
		clk         : in std_logic; -- 48 MHz original input clock
		pll_clk     : in std_logic; -- 130 MHz PLL output 
		pll_running : in std_logic;
		enable_link : in std_logic;
		
		-- SDRAM Controller Wires:
		sdram_cmd_ready   : in  std_logic; -- Read
		sdram_cmd_en      : out std_logic; -- Drive
		sdram_cmd_wr      : out std_logic; -- Drive
		sdram_cmd_address : out std_logic_vector(22 downto 0); -- Drive
		sdram_cmd_byte_en : out std_logic_vector(3  downto 0); -- Drive
		sdram_cmd_data_in : out std_logic_vector(31 downto 0); -- Drive
		sdram_data_out    : in  std_logic_vector(31 downto 0); -- Read
		sdram_data_ready  : in  std_logic; -- Read
		
		-- UART Controller Wires:
		uart_write     : out std_logic; -- Drive
		uart_writedata : out std_logic_vector(7 downto 0); -- Drive
		uart_readdata  : in  std_logic_vector(7 downto 0); -- Read
		uart_write_irq : in  std_logic; -- Read
		uart_read_irq  : in  std_logic  -- Read
	);

END UART_Link;

ARCHITECTURE RTL OF UART_Link IS
	signal uart_save_data : std_logic_vector(7 downto 0) := (others => '0'); -- Save UART Data when a Read IRQ occurs
	
	-- SDRAM Controller IOB wires:
	signal iob_sdram_cmd_en      : std_logic := '0';
	signal iob_sdram_cmd_wr      : std_logic := '0';
	signal iob_sdram_cmd_address : std_logic_vector(22 downto 0) := (others => '0');
	signal iob_sdram_cmd_byte_en : std_logic_vector(3  downto 0) := (others => '0');
	signal iob_sdram_cmd_data_in : std_logic_vector(31 downto 0) := (others => '0');
	
	-- UART Controller IOB Wires:
	signal iob_uart_write     : std_logic := '0';
	signal iob_uart_writedata : std_logic_vector(7 downto 0) := (others => '0');
	
	-- UART FIFO Wires:
	signal uart_fifo_data_out : std_logic_vector(7 downto 0); -- Read
	signal uart_fifo_data_in  : std_logic_vector(7 downto 0) := (others => '0'); -- Drive
	signal uart_fifo_rd       : std_logic := '0'; -- Drive
	signal uart_fifo_wr       : std_logic := '0'; -- Drive
	signal uart_fifo_alm_full : std_logic; -- Read
	signal uart_fifo_empty    : std_logic; -- Read
	signal uart_fifo_full     : std_logic; -- Read
BEGIN
	-------------------------
	-------------------------
	------ Assignments ------
	-------------------------
	-------------------------
	
	-- SDRAM Controller Wire Assignments:
	sdram_cmd_en      <= iob_sdram_cmd_en;
	sdram_cmd_wr      <= iob_sdram_cmd_wr;
	sdram_cmd_address <= iob_sdram_cmd_address;
	sdram_cmd_byte_en <= iob_sdram_cmd_byte_en;
	sdram_cmd_data_in <= iob_sdram_cmd_data_in;
	
	-- UART Controller Wire Assignments:
	uart_write        <= iob_uart_write;
	uart_writedata    <= iob_uart_writedata;
	
	UART_FIFO1 : ENTITY work.uart_fifo PORT MAP (
		clock	      => clk,
		data	      => uart_fifo_data_in,
		rdreq	      => uart_fifo_rd,
		wrreq	      => uart_fifo_wr,
		almost_full => uart_fifo_alm_full,
		empty       => uart_fifo_empty,
		full        => uart_fifo_full,
		q	         => uart_fifo_data_out
	);
	
	------------------------
	------------------------
	------ Behaviours ------
	------------------------
	------------------------
	sdram_ctrl: process(pll_clk) is
	begin
		if rising_edge(pll_clk) then
			if pll_running = '1' then
				------------------------
				-- Control SDRAM here --
				------------------------
				
			end if;
		end if;
	end process;
		
	comm_parse: process(clk) is
	begin
		if rising_edge(clk) then
			if enable_link = '1' then
				-----------------------------------------------------------------------------
				-- Receive, Parse/Interpret, Control and Transmit Back Communications here --
				-----------------------------------------------------------------------------
				
				leds <= "1011";
			end if;
		end if;	
	end process;
	
	system_ctrl: process(clk) is
	begin
		if rising_edge(clk) then
			-------------------------------------------------------------------------
			-- Control Anything else that is unrelated to UART (like the CPU) here --
			-------------------------------------------------------------------------
			-- <NOTHING TO DO FOR NOW...>
		end if;
	end process;
	
END ARCHITECTURE RTL;