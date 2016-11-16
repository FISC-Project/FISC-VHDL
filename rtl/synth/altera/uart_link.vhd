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
	
	-- Algorithm FSM:
	type fsm_t is (
		s_listen,   -- Stay idle and wait for reception of packets
		s_rxing,    -- An SOT byte was received and now we're fetching bytes and building up the single packet until the byte EOT comes up
		s_act_wait, -- Wait for the control process to finish
		s_txing     -- We acted on the rx'd packet and now we're sending a response. Could be an ack or multi-packet response / transaction. Then, we listen for new packets / stay idle
	);
	signal state : fsm_t := s_listen;
	
	constant SOT : signed(7 downto 0) := "10000001"; -- Start of Transmission byte
	constant EOT : signed(7 downto 0) := "10000010"; -- End of Transmission byte
	
	-- Packet Reception/Transmission variables:
	constant carrier_buffer_sz  : integer := 7; -- Size of the carrier buffer, in bytes
	constant data_buffer_max_sz : integer := 8; -- Max size of the data buffer, in bytes. This value is fixed.
	signal data_buffer_sz       : integer := 0; -- Size of the data buffer, in bytes. This can vary.
	signal data_buffer_sz_latch : integer := 0; -- The latched version of the signal 'data_buffer_sz'
	
	signal carrier_buffer_fill_ctr : integer := 0; -- This counter must reach 'carrier_buffer_sz'
	signal data_buffer_fill_ctr    : integer := 0; -- This counter must reach 'data_buffer_sz'
	
	type carrier_buffer_t is array(carrier_buffer_sz -1 downto 0) of std_logic_vector(7 downto 0);
	type data_buffer_t    is array(data_buffer_max_sz-1 downto 0) of std_logic_vector(7 downto 0);
	signal carrier_buffer : carrier_buffer_t := (others => (others => '0'));
	signal data_buffer    : data_buffer_t    := (others => (others => '0'));
	
	constant carrier_magic     : std_logic_vector(15 downto 0) := "1100101011111110"; -- 0xCAFE in hexadecimal
	constant carrier_magic_top : std_logic_vector(7 downto 0)  := "11001010"; -- 0xCA
	constant carrier_magic_bot : std_logic_vector(7 downto 0)  := "11111110"; -- 0xFE
	signal carrier_magic_ctr   : std_logic := '0';
	
	signal rx_dst   : std_logic_vector(1 downto 0) := "00"; -- Are we receiving into the carrier or data buffer? (00- Just received 1st byte, 01- Receiving into Carrier, 10- Receiving into Data buffer, 11- Reception completed)
	signal tx_token : std_logic_vector(1 downto 0) := "00"; -- What are we transferring? (00- Transferring SOT, 01 - Transferring Carrier, 10- Transferring the Data/Payload, 11- Transferring EOT)
	
	-- Transmission Scheduling wires:
	signal tx_schedule          : std_logic; -- Schedule transmission by the controlled device
	signal tx_schedule_drv      : std_logic := '0'; -- Drive the previous wire using this instead
	signal carrier_buffer_sched : carrier_buffer_t := (others => (others => '0'));
	signal data_buffer_sched    : data_buffer_t    := (others => (others => '0'));
	signal data_buffer_sched_sz : integer := 0;
	
	-- Carrier Index Constants:
	constant CARRIER_TOTAL_SIZE   : integer := 0;
	constant CARRIER_PACKAGE_SIZE : integer := 1;
	constant CARRIER_PACKET_ID    : integer := 2;
	constant CARRIER_PORT         : integer := 3;
	constant CARRIER_TYPE         : integer := 4;
	constant CARRIER_MAG_BOT      : integer := 5;
	constant CARRIER_MAG_TOP      : integer := 6;
	
	-- Packet types:
	constant PCKT_NULL            : integer := 0;
	constant PCKT_SDRAM_WRITE     : integer := 1;
	constant PCKT_SDRAM_READ      : integer := 2;
	constant PCKT_SDRAM_READ_ACK  : integer := 3;
	constant PCKT_SDRAM_WRITE_ACK : integer := 4;
	constant PCKT_INVAL           : integer := 5;
	
	-- System Control variables:
	signal ctrl_start       : std_logic := '0'; -- Trigger the Master controller to begin controlling a specific device
	signal ctrl_done        : std_logic := '0'; -- Flag that indicates when the Master controller has finished controlling
	signal master_ctrl_done : std_logic := '0'; -- Flag controlled by every single device on the system, which tells the Master controller when a particular device has finished
	signal ctrling          : std_logic := '0'; -- Is the Master Controller currently waiting for the device to finish?
		
	-- SDRAM Control variables:
	signal sdram_write_en   : std_logic := '0';
	signal sdram_write_wait : std_logic := '0';
	signal sdram_write_wait_ctr : integer := 2; -- We need to wait 2 Clock cycles whenever we write to SDRAM (could be a bug on the dram controller...)
	signal sdram_read_en    : std_logic := '0';
	signal sdram_read_wait  : std_logic := '0';
	signal sdram_done       : std_logic := '0';
	signal sdram_save_data  : std_logic_vector(31 downto 0) := (others => '0'); -- Save SDRAM Data when a Read IRQ occurs
	signal sdram_tx_sched_drv : std_logic := '0';
	signal sdram_tx_sched_drv_cleardelay : std_logic := '0';
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
			
	tx_schedule <= (sdram_tx_sched_drv) and tx_schedule_drv; -- No 2 processes can drive 1 single signal, therefore, we need this assignment
	
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
	
	--------------------------------
	-- UART COMMUNICATION PROCESS --
	--------------------------------
	comm_parse: process(clk) is
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
						ctrl_start     <= '0'; -- When we listen for packets, we do not control the system
						if uart_read_irq = '1' and uart_readdata = std_logic_vector(SOT) then
							state <= s_rxing;
						end if;
					
					--------------------------------------
					-- Wait, receive and collect bytes: --
					--------------------------------------
					when s_rxing =>
						if uart_read_irq = '1' then 
							-- We got a byte. Let's decide what to do with it:
							case rx_dst is
								when "00" =>
									data_buffer_sz_latch <= data_buffer_sz;
									-- We just received the very first byte of the Carrier, which contains the total size of the packet
									if data_buffer_sz > 0 and data_buffer_sz <= data_buffer_max_sz then
										carrier_buffer(0) <= uart_readdata; -- Store this byte into the buffer
										carrier_buffer_fill_ctr <= 1;
										rx_dst <= "01";
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
											rx_dst <= "10";								
										else
											-- The packet is invalid because the magic does not match. Drop it and restart the FSM:
											-- TODO: Handle this error						
											rx_dst <= "00";
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
										rx_dst <= "00";
										-- We've finished writing into the data buffer. Now we should expect an EOT byte:
										if uart_readdata = std_logic_vector(EOT) then
											-- Success! The received packet is good and ready to be used
											ctrl_start      <= '1';
											tx_schedule_drv <= '1'; -- Allow transmission schedulings to occurr
											state           <= s_act_wait;
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
						case tx_token is
							when "00" => -- Transfer SOT (1 byte)
								carrier_buffer_fill_ctr <= 0;
								data_buffer_fill_ctr    <= 0;
								iob_uart_writedata <= std_logic_vector(SOT);
								iob_uart_write <= '1';
								if uart_write_irq = '1' then
									tx_token <= "01";
								end if;	
								
							when "01" => -- Transfer Carrier (7 bytes)
								iob_uart_writedata <= carrier_buffer(carrier_buffer_fill_ctr);
								if uart_write_irq = '1' then
									carrier_buffer_fill_ctr <= carrier_buffer_fill_ctr + 1;
									if carrier_buffer_fill_ctr = carrier_buffer_sz-1 then
										tx_token <= "10";
									end if;
								end if;
								
							when "10" => -- Transfer Payload (varies, but can't be 0 size)
								iob_uart_writedata <= data_buffer(data_buffer_fill_ctr);
								if uart_write_irq = '1' then
									data_buffer_fill_ctr <= data_buffer_fill_ctr + 1;
									if data_buffer_fill_ctr = to_integer(unsigned(std_logic_vector(unsigned(carrier_buffer(0)) - to_unsigned(carrier_buffer_sz, 8)))) then
										tx_token <= "11";
									end if;
								end if;
								
							when "11" => -- Transfer EOT (1 byte)
								iob_uart_writedata <= std_logic_vector(EOT);
								if uart_write_irq = '1' then
									carrier_buffer_fill_ctr <= 0;
									data_buffer_fill_ctr    <= 0;
									tx_token <= "00";
									state    <= s_listen; -- Now that we're done transmitting, we're going to listen for a response
								end if;
							end case;
										
					-------------------------------
					-- Use the Received Packets: --
					-------------------------------			
					when s_act_wait => -- We received a valid packet! Now use it, and maybe send a response, depending on what the packet contains						
						-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						-- BIG TODO: Remove the multiple processes to save FPGA Resources.
						-- We'll need to put everything in this process so that we can drive any wire
						-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						ctrl_start <= '0';
						if ctrl_done = '1' then
							if tx_schedule = '1' then
								-- We're gonna have to send 1 (or more) packets back.
								tx_schedule_drv <= '0'; -- Disable tx scheduling for now
								carrier_buffer  <= carrier_buffer_sched;
								data_buffer     <= data_buffer_sched;
								state           <= s_txing;	
					   	else -- No packets to send back
								state <= s_listen;
							end if;
						end if;
											
					when others => state <= s_listen;
				end case;
			end if;
		end if;	
	end process;
	
	----------------------------
	-- SYSTEM CONTROL PROCESS --
	----------------------------
	system_ctrl: process(clk) is
	begin
		if rising_edge(clk) then
			if ctrling = '0' and master_ctrl_done = '0' then
				-------------------------------------------------------------------------
				-- Control Anything else that is unrelated to UART (like the CPU) here --
				-------------------------------------------------------------------------
				ctrl_done <= '0';
					
				if ctrl_start = '1' then
					-- Use the received packed, by parsing the carrier and sending the data buffer into the next process
					case carrier_buffer(CARRIER_TYPE) is
						when "00000000" => ctrl_done <= '1'; -- NULL Packet
						
						when "00000001" => -- Write to SDRAM Packet
							sdram_write_en <= '1';
							ctrling        <= '1';
						when "00000010" => -- Read from SDRAM Packet
							sdram_read_en  <= '1';
							ctrling        <= '1';
							
						when others => ctrl_done <= '1'; -- Unrecognized packet
					end case;
				end if;
			else
				-- We're controlling and we're not allowed to proceed until the device has finished
				
				-- Clear out all the triggers:
				sdram_write_en <= '0';
				sdram_read_en  <= '0';
				if master_ctrl_done = '1' then
					-- We're done controlling, stop waiting now
					ctrling   <= '0';
					ctrl_done <= '1';
				end if;
			end if;
		end if;
	end process;
	
	master_ctrl_done <= sdram_done; -- We'll need to OR all these signals with different types of devices, not just SDRAM
	
	---------------------------
	-- SDRAM CONTROL PROCESS --
	---------------------------
	sdram_ctrl: process(clk) is
	begin
		if rising_edge(clk) then
			if pll_running = '1' then
				------------------------
				-- Control SDRAM here --
				------------------------
				-- TODO: Maybe in the future we might want to integrate this process with the CPU			
				--	TODO: Also, for the SDRAM, we'll want to parse a packet to enable an ACK packet whenever we write to the memory
				
				sdram_done <= '0';
				if sdram_tx_sched_drv_cleardelay = '0' then
					sdram_tx_sched_drv <= '0';
				else
					sdram_tx_sched_drv_cleardelay <= '0';
				end if;
				
				-- This process is controlled by the process 'system_ctrl'
				if sdram_write_en = '1' or sdram_write_wait = '1' then
					if sdram_write_wait = '0' then
						-- Write word to SDRAM:
						iob_sdram_cmd_address <= data_buffer(2)(6 downto 0) & data_buffer(1) & data_buffer(0);
						iob_sdram_cmd_data_in <= data_buffer(7) & data_buffer(6) & data_buffer(5) & data_buffer(4);
						iob_sdram_cmd_byte_en <= (others => '1'); -- TODO: We will need to change the width of the SDRAM operation (8 bits, 16 bits and 32 bits)
						iob_sdram_cmd_wr <= '1';
						iob_sdram_cmd_en <= '1';
						sdram_write_wait <= '1';
					else
						iob_sdram_cmd_en <= '0';
						iob_sdram_cmd_wr <= '0';
						iob_sdram_cmd_byte_en <= (others => '0');
						if sdram_cmd_ready = '1' then
							if sdram_write_wait_ctr /= 0 then
								-- We need to wait twice when we write to SDRAM:
								sdram_write_wait_ctr <= sdram_write_wait_ctr - 1;
							else
								-- We're done writing!
								sdram_done           <= '1';
								sdram_write_wait     <= '0';
								sdram_write_wait_ctr <= 2;
							end if;
						end if;
					end if;
					
				elsif sdram_read_en = '1' or sdram_read_wait = '1' then
					-- Read word from SDRAM and send it back through UART 
					if sdram_read_wait = '0' then
						iob_sdram_cmd_address <= data_buffer(2)(6 downto 0) & data_buffer(1) & data_buffer(0);
						iob_sdram_cmd_data_in <= (others => '0');
						iob_sdram_cmd_byte_en <= (others => '1'); -- TODO: We will need to change the width of the SDRAM operation (8 bits, 16 bits and 32 bits)
						iob_sdram_cmd_wr <= '0';
						iob_sdram_cmd_en <= '1';
						sdram_read_wait  <= '1';
					else
						iob_sdram_cmd_en <= '0';
						iob_sdram_cmd_byte_en <= (others => '0');
						if sdram_data_ready = '1' then
							-- TODO: For now, we'll just send this data through UART,
							-- in the future, we might want to send it to the CPU instead
							sdram_done      <= '1';
							sdram_read_wait <= '0';
							sdram_save_data <= sdram_data_out;
							
							-- Schedule transmission:
							sdram_tx_sched_drv <= '1';
							sdram_tx_sched_drv_cleardelay <= '1';
							data_buffer_sched(0) <= sdram_data_out(7 downto 0);
							data_buffer_sched(1) <= sdram_data_out(15 downto 8);
							data_buffer_sched(2) <= sdram_data_out(23 downto 16);
							data_buffer_sched(3) <= sdram_data_out(31 downto 24);
							carrier_buffer_sched(CARRIER_TOTAL_SIZE) <= std_logic_vector(to_unsigned(carrier_buffer_sz + 4, 8));
							carrier_buffer_sched(CARRIER_TYPE)       <= std_logic_vector(to_unsigned(PCKT_SDRAM_READ_ACK, 8));							
							carrier_buffer_sched(CARRIER_MAG_TOP)    <= carrier_magic_top;
							carrier_buffer_sched(CARRIER_MAG_BOT)    <= carrier_magic_bot;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;
	
END ARCHITECTURE RTL;