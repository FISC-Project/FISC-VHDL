LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY UART_Link IS
	PORT(
		leds        : out std_logic_vector(3 downto 0) := (others => '0'); -- TODO: REMOVE THIS LATER
		clk         : in  std_logic; -- 48 MHz original input clock
		pll_clk     : in  std_logic; -- 130 MHz PLL output 
		pll_running : in  std_logic;
		enable_link : in  std_logic;
		
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
	signal iob_leds : std_logic_vector(3 downto 0) := "0000";

	-----------------------------------
	-- IMPORTANT CONSTANT:
	-- In case you want to save a considerable amount of FPGA resources (approx. 240 logic elements), 
	-- you can just set this to false, but you'll lose the ability to receive packets from the FPGA, 
	-- so be careful and make sure your software doesn't rely on acknowledgments
	constant tx_enable : boolean := true;
	------------------------------------
	
	-- SDRAM Controller IOB wires:
	signal iob_sdram_cmd_en      : std_logic := '0';
	signal iob_sdram_cmd_wr      : std_logic := '0';
	signal iob_sdram_cmd_address : std_logic_vector(22 downto 0) := (others => '0');
	signal iob_sdram_cmd_byte_en : std_logic_vector(3  downto 0) := (others => '0');
	signal iob_sdram_cmd_data_in : std_logic_vector(31 downto 0) := (others => '0');
	
	-- UART Controller IOB Wires:
	signal iob_uart_write     : std_logic := '0';
	signal iob_uart_writedata : std_logic_vector(7 downto 0) := (others => '0');
		
	-- Algorithm FSM:
	type fsm_t is (
		s_listen,           -- Stay idle and wait for reception of packets
		s_rxing,            -- An SOT byte was received and now we're fetching bytes and building up the single packet until the byte EOT comes up
		s_txing,            -- We acted on the rx'd packet and now we're sending a response. Could be an ack or multi-packet response / transaction. Then, we listen for new packets / stay idle
		s_ctrl_switch,      -- Decide what state to go whenever a packet is received
		s_sdram_write,      -- This state triggers a write command on the SDRAM
		s_sdram_write_wait, -- This state waits for the SDRAM to finish writing
		s_sdram_read,       -- This state triggers a read command on the SDRAM
		s_sdram_read_wait   -- This state waits for the SDRAM to finish reading
		-- TODO: We'll add more states here whenever we want to control a new device, such as the Flash Memory using SPI
	);
	signal state : fsm_t := s_listen;
	
	constant SOT : signed(7 downto 0) := "10000001"; -- Start of Transmission byte
	constant EOT : signed(7 downto 0) := "10000010"; -- End of Transmission byte
	
	-- Packet Reception/Transmission buffer variables:
	constant carrier_buffer_sz    : integer := 7; -- Size of the carrier buffer, in bytes
	constant data_buffer_max_sz   : integer := 8; -- Max size of the data buffer, in bytes. This value is fixed.
	signal   data_buffer_sz       : integer := 0; -- Size of the data buffer, in bytes. This can vary.
	signal   data_buffer_sz_latch : integer := 0; -- The latched version of the signal 'data_buffer_sz'
	
	signal carrier_buffer_fill_ctr : integer := 0; -- This counter must reach 'carrier_buffer_sz'
	signal data_buffer_fill_ctr    : integer := 0; -- This counter must reach 'data_buffer_sz'
	
	type   carrier_buffer_t is array(carrier_buffer_sz -1 downto 0) of std_logic_vector(7 downto 0);
	type   data_buffer_t    is array(data_buffer_max_sz-1 downto 0) of std_logic_vector(7 downto 0);
	signal carrier_buffer : carrier_buffer_t := (others => (others => '0'));
	signal data_buffer    : data_buffer_t    := (others => (others => '0'));
	
	constant carrier_magic     : std_logic_vector(15 downto 0) := "1100101011111110"; -- 0xCAFE in hexadecimal
	constant carrier_magic_top : std_logic_vector(7 downto 0)  := "11001010"; -- 0xCA
	constant carrier_magic_bot : std_logic_vector(7 downto 0)  := "11111110"; -- 0xFE
	signal   carrier_magic_ctr : std_logic := '0';
	
	signal rx_fsm_state : std_logic_vector(1 downto 0) := "00"; -- Are we receiving into the carrier or data buffer? (00- Just received 1st byte, 01- Receiving into Carrier, 10- Receiving into Data buffer, 11- Reception completed)
	signal tx_fsm_state : std_logic_vector(1 downto 0) := "00"; -- What are we transferring? (00- Transferring SOT, 01 - Transferring Carrier, 10- Transferring the Data/Payload, 11- Transferring EOT)
	
	-- Carrier Index Constants:
	constant CARRIER_TOTAL_SIZE   : integer := 0; -- Total size of the packet (excluding SOT and EOT)
	constant CARRIER_PACKAGE_SIZE : integer := 1; -- Total amount of packets that constitute the transaction/package
	constant CARRIER_PACKET_ID    : integer := 2; -- The ID of this packet
	constant CARRIER_PORT         : integer := 3; -- The port of this packet. This determines to which device the packet must go
	constant CARRIER_TYPE         : integer := 4; -- The type of the packet.
	constant CARRIER_MAG_BOT      : integer := 5; -- Magic number (bottom half)
	constant CARRIER_MAG_TOP      : integer := 6; -- Magic number (top half)
	
	-- Packet Types:
	constant PCKT_NULL            : integer := 0;
	constant PCKT_SDRAM_WRITE     : integer := 1;
	constant PCKT_SDRAM_READ      : integer := 2;
	constant PCKT_SDRAM_READ_ACK  : integer := 3;
	constant PCKT_SDRAM_WRITE_ACK : integer := 4;
	constant PCKT_INVAL           : integer := 5;
	
	-- SDRAM Control variables:
	signal sdram_write_wait_ctr : integer := 2; -- We need to wait 2 Clock cycles whenever we write to SDRAM (could be a bug on the dram controller...)
	signal sdram_save_data      : std_logic_vector(31 downto 0) := (others => '0'); -- Save SDRAM Data when a Read IRQ occurs
BEGIN
	leds <= iob_leds; -- TODO: REMOVE THIS LATER

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
	
	data_buffer_sz    <= to_integer(unsigned(std_logic_vector(unsigned(uart_readdata) - to_unsigned(carrier_buffer_sz, 8))));

	------------------------
	------------------------
	------ Behaviours ------
	------------------------
	------------------------
	
	--------------------------------
	--------- MAIN PROCESS ---------
	--------------------------------
	main_proc: process(clk) is
	begin
		if rising_edge(clk) then
			if enable_link = '1' then
				----------------------------------------------------------------------------------------
				-- Algorithm: Receive, Parse/Interpret, Control and Transmit Back Communications here --
				----------------------------------------------------------------------------------------
				case state is
					-------------------------
					-- Listen for Packets: --
					-------------------------
					when s_listen => 
						iob_uart_write <= '0';
						if uart_read_irq = '1' and uart_readdata = std_logic_vector(SOT) then
							state <= s_rxing;
						end if;
					
					--------------------------------------
					-- Wait, receive and collect bytes: --
					--------------------------------------
					when s_rxing =>
						if uart_read_irq = '1' then 
							-- We got a byte. Let's decide what to do with it:
							case rx_fsm_state is
								when "00" =>
									data_buffer_sz_latch <= data_buffer_sz;
									-- We just received the very first byte of the Carrier, which contains the total size of the packet
									if data_buffer_sz > 0 and data_buffer_sz <= data_buffer_max_sz then
										carrier_buffer(0) <= uart_readdata; -- Store this byte into the buffer
										carrier_buffer_fill_ctr <= 1;
										rx_fsm_state <= "01";
									else
										-- We received a malformed packet...
										-- TODO: Handle this error									
										state <= s_listen;
									end if;
									
								when "01" => 
									-- Write the remaining 6 bytes into the carrier buffer:
									carrier_buffer(carrier_buffer_fill_ctr) <= uart_readdata; -- Store this byte into the buffer
									carrier_buffer_fill_ctr <= carrier_buffer_fill_ctr + 1;
									
									-- See if we need to check for the Magic value:
									if carrier_buffer_fill_ctr = carrier_buffer_sz - 2 and uart_readdata = carrier_magic(7 downto 0) then
										carrier_magic_ctr <= '1';
									end if;
									
									if carrier_buffer_fill_ctr = carrier_buffer_sz - 1 then
										if uart_readdata = carrier_magic(15 downto 8) and carrier_magic_ctr = '1' then
											-- Only write into the next buffer if the carrier was valid (if the magic is correct):
											data_buffer <= (others => (others => '0')); -- Clear out the data buffer
											carrier_magic_ctr <= '0';
											rx_fsm_state <= "10";								
										else
											-- The packet is invalid because the magic does not match. Drop it and restart the FSM:
											-- TODO: Handle this error						
											rx_fsm_state <= "00";
											state  <= s_listen;
										end if;
									end if;
									
								when "10" =>
									if data_buffer_fill_ctr < data_buffer_sz_latch then
										-- Write the rest of the packet into the data buffer:
										data_buffer(data_buffer_fill_ctr) <= uart_readdata; -- Store this byte into the buffer
										data_buffer_fill_ctr <= data_buffer_fill_ctr + 1;
									else
										data_buffer_fill_ctr <= 0;
										rx_fsm_state <= "00";
										-- We've finished writing into the data buffer. Now we should expect an EOT byte:
										if uart_readdata = std_logic_vector(EOT) then
											-- Success! The received packet is good and ready to be used
											state <= s_ctrl_switch;
										else
											-- The byte following the data buffer was NOT an EOT signal, meaning, the transmission is invalid, and the packet shall be dropped
											-- TODO: Handle this error
											state <= s_listen;
										end if;
									end if;
									
								when "11" => -- We might not even get here
							end case;
						end if;
	
	
					------------------------
					-- Send Packets back: --
					------------------------
					when s_txing =>
						-- ** How to send a Packet back: **
						-- Step 1: Set the signal 'carrier_buffer' with the proper values
						-- Step 2: Set the signal 'data_buffer' with the data you want to send
						-- Step 3: Set the FSM state to s_txing.
						-- And that's it!
						case tx_fsm_state is
							when "00" => -- Transfer SOT (1 byte)
								carrier_buffer_fill_ctr <= 0;
								data_buffer_fill_ctr    <= 0;
								iob_uart_writedata <= std_logic_vector(SOT);
								iob_uart_write <= '1';
								if uart_write_irq = '1' then
									tx_fsm_state <= "01";
								end if;	
								
							when "01" => -- Transfer Carrier (7 bytes)
								iob_uart_writedata <= carrier_buffer(carrier_buffer_fill_ctr);
								if uart_write_irq = '1' then
									carrier_buffer_fill_ctr <= carrier_buffer_fill_ctr + 1;
									if carrier_buffer_fill_ctr = carrier_buffer_sz-1 then
										tx_fsm_state <= "10";
									end if;
								end if;
								
							when "10" => -- Transfer Payload (varies, but can't be 0 size)
								iob_uart_writedata <= data_buffer(data_buffer_fill_ctr);
								if uart_write_irq = '1' then
									data_buffer_fill_ctr <= data_buffer_fill_ctr + 1;
									if data_buffer_fill_ctr = to_integer(unsigned(std_logic_vector(unsigned(carrier_buffer(0)) - to_unsigned(carrier_buffer_sz, 8)))) then
										tx_fsm_state <= "11";
									end if;
								end if;
								
							when "11" => -- Transfer EOT (1 byte)
								iob_uart_writedata <= std_logic_vector(EOT);
								if uart_write_irq = '1' then
									carrier_buffer_fill_ctr <= 0;
									data_buffer_fill_ctr    <= 0;
									tx_fsm_state <= "00";
									-- Now that we're done transmitting, we're going to listen for a response
									-- Also, it's important to note that if we want to send multiple packets, we can't return to s_listen, we must return
									-- instead to the previous state that got us here
									state    <= s_listen;
								end if;
							end case;
					
					--------------------
					-- CONTROL SWITCH --
					--------------------
					when s_ctrl_switch =>
						-- Use the received packed, by parsing the carrier and sending the data buffer into the next process
						-- TODO: Maybe in the future we might want to integrate this process with the CPU			
						--	TODO: Also, for the SDRAM, we'll want to parse a packet to enable an ACK packet whenever we write to the memory
				
						case carrier_buffer(CARRIER_TYPE) is
							when "00000000" => state <= s_listen;      -- NULL Packet, ignore it
							when "00000001" => state <= s_sdram_write; -- Write to  SDRAM Packet
							when "00000010" => 
								if tx_enable then
									state <= s_sdram_read;  -- Read from SDRAM Packet
								else 
									-- Transmission is disabled, why even read if there's nowhere to send the data to? In this case, just go back to listening
									state <= s_listen;
								end if;
							when others => state <= s_listen; -- Unrecognized packet, ignore it
						end case;
						
					when s_sdram_write =>
						-- Write word to SDRAM:
						iob_sdram_cmd_address <= data_buffer(2)(6 downto 0) & data_buffer(1) & data_buffer(0);
						iob_sdram_cmd_data_in <= data_buffer(7) & data_buffer(6) & data_buffer(5) & data_buffer(4);
						iob_sdram_cmd_byte_en <= (others => '1'); -- TODO: We will need to change the width of the SDRAM operation (8 bits, 16 bits and 32 bits)
						iob_sdram_cmd_wr <= '1';
						iob_sdram_cmd_en <= '1';
						state <= s_sdram_write_wait;
						
					when s_sdram_write_wait =>
						iob_sdram_cmd_en <= '0';
						iob_sdram_cmd_wr <= '0';
						iob_sdram_cmd_byte_en <= (others => '0');
						if sdram_cmd_ready = '1' then
							if sdram_write_wait_ctr /= 0 then
								-- We need to wait twice when we write to SDRAM:
								sdram_write_wait_ctr <= sdram_write_wait_ctr - 1;
							else
								-- We're done writing!
								sdram_write_wait_ctr <= 2;
								state <= s_listen;
								-- TODO: In case the TX irq is enabled, instead of jumping to 's_listen', jump to 's_txing' instead
							end if;
						end if;
						
					when s_sdram_read =>
						iob_sdram_cmd_address <= data_buffer(2)(6 downto 0) & data_buffer(1) & data_buffer(0);
						iob_sdram_cmd_data_in <= (others => '0');
						iob_sdram_cmd_byte_en <= (others => '1'); -- TODO: We will need to change the width of the SDRAM operation (8 bits, 16 bits and 32 bits)
						iob_sdram_cmd_wr <= '0';
						iob_sdram_cmd_en <= '1';
						state <= s_sdram_read_wait;
						
					when s_sdram_read_wait =>
						iob_sdram_cmd_en <= '0';
						iob_sdram_cmd_byte_en <= (others => '0');
						if sdram_data_ready = '1' then
							-- TODO: For now, we'll just send this data through UART,
							-- in the future, we might want to send it to the CPU instead
							sdram_save_data <= sdram_data_out;
							
							-- Build and Transmit the received data back:
							data_buffer(0)                     <= sdram_data_out(7  downto 0);
							data_buffer(1)                     <= sdram_data_out(15 downto 8);
							data_buffer(2)                     <= sdram_data_out(23 downto 16);
							data_buffer(3)                     <= sdram_data_out(31 downto 24);
							carrier_buffer(CARRIER_TOTAL_SIZE) <= std_logic_vector(to_unsigned(carrier_buffer_sz + 4, 8));
							carrier_buffer(CARRIER_TYPE)       <= std_logic_vector(to_unsigned(PCKT_SDRAM_READ_ACK, 8));							
							carrier_buffer(CARRIER_MAG_TOP)    <= carrier_magic_top;
							carrier_buffer(CARRIER_MAG_BOT)    <= carrier_magic_bot;
							
							state <= s_txing; -- Send the data!
						end if;

					when others => state <= s_listen; -- Invalid state!
				end case;
			end if;
		end if;	
	end process;	
END ARCHITECTURE RTL;