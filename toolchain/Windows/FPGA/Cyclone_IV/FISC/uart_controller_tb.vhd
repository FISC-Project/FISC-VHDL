LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY UART_Controller_tb IS
	PORT(
		CLK   : in  std_logic;
		RXD   : out std_logic; -- RXD is OUT and !!NOT!! IN
		TXD   : in  std_logic; -- TXD IS IN  and !!NOT!! OUT
		DS_DP : out std_logic;
		DS_G  : out std_logic;
		DS_C  : out std_logic;
		DS_D  : out std_logic
	);
END UART_Controller_tb;

ARCHITECTURE RTL OF UART_Controller_tb IS
	signal z : boolean := false;
	signal reset : std_logic := '0';
	type fsm is (
		s_init,
		s_init_done,
		s_tx,
		s_idle
	);
	signal state : fsm := s_init;
	
	-- UART Controller Wires:
	signal uart_write      : std_logic := '0'; -- Drive
	signal uart_writedata  : std_logic_vector(7 downto 0) := (others => '0'); -- Drive
	signal uart_readdata   : std_logic_vector(7 downto 0); -- Read
	signal uart_write_irq  : std_logic; -- Write IRQ (Read)
	signal uart_read_irq   : std_logic; -- Read IRQ (Read)
	
	signal leds           : std_logic_vector(3 downto 0) := (others => '0');
	signal uart_save_data : std_logic_vector(7 downto 0) := (others => '0');
		
	impure function f_tx(tx_data : std_logic_vector(7 downto 0)) return boolean is
	begin
		uart_writedata <= tx_data;
		uart_write     <= '1';
		return uart_write_irq = '1';
	end function;
	
	impure function f_rx(rx_data : std_logic_vector(7 downto 0)) return boolean is
	begin
		-- Show lower 4 bits of the received data on the LEDs:
		leds <= rx_data(3 downto 0);
		-- Send the received byte back:
		uart_save_data <= rx_data;
		return true;
	end function;
BEGIN
		(DS_D, DS_C, DS_G, DS_DP) <= not leds;
		
		UART_Controller1 : ENTITY work.UART_Controller
			GENERIC MAP(
				baud            => 128000,
				clock_frequency => 48000000
			)
			PORT MAP (
				clock               => CLK,
				reset               => reset,
				data_stream_in      => uart_writedata,
				data_stream_in_stb  => uart_write,
				data_stream_in_ack  => uart_write_irq,
				data_stream_out     => uart_readdata,
				data_stream_out_stb => uart_read_irq,
				tx                  => RXD, -- Notice the twisted connections
				rx                  => TXD  -- Notice the twisted connections
			);
							
		process(CLK) 
		begin
			if rising_edge(CLK) then
				case state is
					when s_init => 
						reset <= '1';
						state <= s_init_done;
						
					when s_init_done =>
						reset <= '0';
						state <= s_idle;
					
					when s_tx =>
						if f_tx(uart_save_data) then 
							state <= s_idle;
						end if;
						
					when s_idle =>
						uart_write <= '0';
						if uart_read_irq = '1' then
							z<=f_rx(uart_readdata);
							state <= s_tx;
						end if;
						
					when others => state <= s_idle;
				end case;
			end if;
		end process;
END ARCHITECTURE RTL;