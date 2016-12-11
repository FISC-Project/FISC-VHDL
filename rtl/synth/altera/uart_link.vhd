LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY UART_Link IS
	PORT(
		clk               : in  std_logic; -- 48 MHz original input clock
		pll_clk           : in  std_logic; -- 130 MHz PLL output 
		pll_running       : in  std_logic;
		enable_link       : in  std_logic;
		ready             : out std_logic := '0'; -- Has the UART Link finished initialization?
		
		-- SDRAM Controller Wires:
		sdram_cmd_ready   : in  std_logic; -- Read
		sdram_cmd_en      : out std_logic; -- Drive
		sdram_cmd_wr      : out std_logic; -- Drive
		sdram_cmd_address : out std_logic_vector(22 downto 0); -- Drive
		sdram_cmd_byte_en : out std_logic_vector(3  downto 0); -- Drive
		sdram_cmd_data_in : out std_logic_vector(31 downto 0); -- Drive
		sdram_data_out    : in  std_logic_vector(31 downto 0); -- Read
		sdram_data_ready  : in  std_logic; -- Read
		
		-- CPU's SDRAM Controller Wires:
		cpu_sdram_cmd_en      : in std_logic; -- Driven by the CPU
		cpu_sdram_cmd_wr      : in std_logic; -- Driven by the CPU
		cpu_sdram_cmd_address : in std_logic_vector(22 downto 0); -- Driven by the CPU
		cpu_sdram_cmd_byte_en : in std_logic_vector(3  downto 0); -- Driven by the CPU
		cpu_sdram_cmd_data_in : in std_logic_vector(31 downto 0); -- Driven by the CPU
		
		-- Flash Memory Controller Wires:
		fmem_enable       : out std_logic; -- Drive
		fmem_ready        : in  std_logic; -- Read
		fmem_instruction  : out integer;   -- Drive
		fmem_address      : out integer;   -- Drive
		fmem_data_write   : out std_logic_vector(256*8-1 downto 0); -- Drive
		fmem_data_read    : in  std_logic_vector(4*8-1   downto 0); -- Read
		fmem_status       : in  std_logic_vector(7       downto 0); -- Read
		
		-- UART Controller Wires:
		uart_write        : out std_logic; -- Drive
		uart_writedata    : out std_logic_vector(7 downto 0); -- Drive
		uart_readdata     : in  std_logic_vector(7 downto 0); -- Read
		uart_write_irq    : in  std_logic; -- Read
		uart_read_irq     : in  std_logic  -- Read
	);
END UART_Link;

ARCHITECTURE RTL OF UART_Link IS
	-----------------------------------
	-- EXTREMELY IMPORTANT CONSTANTS:
	-- In case you want to save a considerable amount of FPGA resources (approx. 240 logic elements), 
	-- you can just set the following boolean to false, but you'll lose the ability to receive packets from the FPGA, 
	-- so be careful and make sure your software doesn't rely on acknowledgments
	constant tx_enable          : boolean := false;
	-- In case you want to write directly to SDRAM through UART, set the following boolean to true.
	-- This is EXTREMELY important, because it saves a tremendous amount of resources. Also, it might make sense
	-- to disable this on release day, since it's not the UART/PC's job to load up the SDRAM.
	constant sdram_write_enable : boolean := false;
	-- If you don't want to write to flash memory from UART (ever), and want to save a lot of FPGA space, turn the following boolean false:
	constant fmem_write_enable  : boolean := false;
	
	-- !!!! RECOMMENDATIONS !!!!
	-- There are 4 modes that will be used on the system:
	-- 1- Release Mode: All the previous booleans are false. This means the UART Link only redirects normal UART Communication to the CPU/IRQ Controller
	-- 2- Debug Full Mode: All the previous booleans are true. This means we get all the controls for every single device through UART
	-- 3- Debug Half Mode: The configuration of the booleans is respectively: false | true | true. This means we can still write to both SDRAM and Flash Memory, but can't read them into the UART Comm
	-- 4- Debug Minimal Mode: The configuration of the booleans is respectively: false | false | true. This means we can't read or write anything except write the Flash Memory. This is so that we can change the boot code
	------------------------------------
	
	-- SDRAM Controller IOB wires:
	signal iob_sdram_cmd_en      : std_logic := '0';
	signal iob_sdram_cmd_wr      : std_logic := '0';
	signal iob_sdram_cmd_address : std_logic_vector(22 downto 0) := (others => '0');
	signal iob_sdram_cmd_byte_en : std_logic_vector(3  downto 0) := (others => '0');
	signal iob_sdram_cmd_data_in : std_logic_vector(31 downto 0) := (others => '0');
	
	-- Flash Memory Controller IOB Wires:
	signal iob_fmem_enable       : std_logic := '0';
	signal iob_fmem_instruction  : integer   :=  0;
	signal iob_fmem_address      : std_logic_vector(23 downto 0) := (others => '0');
	signal iob_fmem_data_write   : std_logic_vector(31 downto 0) := (others => '0');
		
	-- UART Controller IOB Wires:
	signal iob_uart_write        : std_logic := '0';
	signal iob_uart_writedata    : std_logic_vector(7 downto 0) := (others => '0');
		
	-- Algorithm FSM:
	type fsm_t is (
		s_init, s_init_done,   -- Initialize UART Link
		s_load_fmem,           -- Load Flash Memory into SDRAM. This happens everytime the FPGA is initialized
		s_listen,              -- Stay idle and wait for reception of packets
		s_rxing,               -- An SOT byte was received and now we're fetching bytes and building up the single packet until the byte EOT comes up
		s_txing,               -- We acted on the rx'd packet and now we're sending a response. Could be an ack or multi-packet response / transaction. Then, we listen for new packets / stay idle
		s_ctrl_switch,         -- Decide what state to go whenever a packet is received
		-- System Control states:
		s_sdram_write,         -- This state triggers a write command on the SDRAM
		s_sdram_write_wait,    -- This state waits for the SDRAM to finish writing
		s_sdram_read,          -- This state triggers a read command on the SDRAM
		s_sdram_read_wait,     -- This state waits for the SDRAM to finish reading
		s_fmem_read_page,      -- This state triggers the read of Flash Memory onto a buffer, and is transmitted back through UART
		s_fmem_read_page_done, -- This state waits and finishes for the Flash Memory's page read to complete
		s_fmem_write_enable,   -- This state enables writing onto the Flash Memory. This state must be executed always before erasing a sector or writing a page
		s_fmem_write_page,     -- This state writes a page (256 bytes) onto the Flash Memory
		s_fmem_erase_sector,   -- This state erases a sector from Flash Memory, which is equal to 4KB 
		s_fmem_control_wait    -- This state waits for the Flash Memory to finish its command execution
		-- TODO: We'll add more states here whenever we want to control a new device, such as the Flash Memory using SPI
	);
	signal state : fsm_t := s_init;
	
	-- Communication tokens:
	constant SOT : signed(7 downto 0) := "10000001"; -- Start of Transmission byte
	constant EOT : signed(7 downto 0) := "10000010"; -- End   of Transmission byte
	
	-- Packet Reception/Transmission buffer variables:
	constant carrier_buffer_sz       : integer := 7; -- Size of the carrier buffer, in bytes
	constant data_buffer_max_sz      : integer := 8; -- Max size of the data buffer, in bytes. This value is fixed.
	signal   data_buffer_sz          : integer := 0; -- Size of the data buffer, in bytes. This can vary.
	signal   data_buffer_sz_latch    : integer := 0; -- The latched version of the signal 'data_buffer_sz'
	
	signal   carrier_buffer_fill_ctr : integer := 0; -- This counter must reach 'carrier_buffer_sz'
	signal   data_buffer_fill_ctr    : integer := 0; -- This counter must reach 'data_buffer_sz'
	
	type     carrier_buffer_t is array(carrier_buffer_sz-1 downto 0) of std_logic_vector(7 downto 0);
	signal   carrier_buffer : carrier_buffer_t := (others => (others => '0'));
	signal   data_buffer    : std_logic_vector(data_buffer_max_sz*8-1 downto 0) := (others => '0');
	
	constant carrier_magic     : std_logic_vector(15 downto 0) := "1100101011111110"; -- 0xCAFE in hexadecimal
	constant carrier_magic_top : std_logic_vector(7 downto 0)  := "11001010"; -- 0xCA
	constant carrier_magic_bot : std_logic_vector(7 downto 0)  := "11111110"; -- 0xFE
	signal   carrier_magic_ctr : std_logic := '0';
	
	signal   rx_fsm_state : std_logic_vector(1 downto 0) := "00"; -- Are we receiving into the carrier or data buffer? (00- Just received 1st byte, 01- Receiving into Carrier, 10- Receiving into Data buffer, 11- Reception completed)
	signal   tx_fsm_state : std_logic_vector(1 downto 0) := "00"; -- What are we transferring? (00- Transferring SOT, 01 - Transferring Carrier, 10- Transferring the Data/Payload, 11- Transferring EOT)
	
	-- Carrier Index Constants:
	constant CARRIER_TOTAL_SIZE    : integer := 0; -- Total size of the packet (excluding SOT and EOT)
	constant CARRIER_PACKAGE_SIZE  : integer := 1; -- Total amount of packets that constitute the transaction/package
	constant CARRIER_PACKET_ID     : integer := 2; -- The ID of this packet
	constant CARRIER_PORT          : integer := 3; -- The port of this packet. This determines to which device the packet must go
	constant CARRIER_TYPE          : integer := 4; -- The type of the packet.
	constant CARRIER_MAG_BOT       : integer := 5; -- Magic number (bottom half)
	constant CARRIER_MAG_TOP       : integer := 6; -- Magic number (top half)
	
	-- Packet Types:
	constant PCKT_NULL             : integer := 0;
	constant PCKT_SDRAM_WRITE      : integer := 1;
	constant PCKT_SDRAM_READ       : integer := 2;
	constant PCKT_SDRAM_READ_ACK   : integer := 3;
	constant PCKT_SDRAM_WRITE_ACK  : integer := 4;
	constant PCKT_FMEM_READPAGE    : integer := 5;
	constant PCKT_FMEM_WRITEPAGE   : integer := 6;
	constant PCKT_FMEM_ERASESECTOR : integer := 7;
	constant PCKT_FMEM_READPAG_ACK : integer := 8;
	constant PCKT_FMEM_WRITEPA_ACK : integer := 9;
	constant PCKT_FMEM_ERASE_S_ACK : integer := 10;
	constant PCKT_INVAL            : integer := 11;
	
	signal uart_controlling        : boolean := false; -- When a device is controlled, who requested it? The UART or the CPU? If this is true, then the UART Controller did. Otherwise, it was the CPU.
	
	-- SDRAM Control variables:
	signal   sdram_write_wait_ctr  : integer := 2; -- We need to wait 2 Clock cycles whenever we write to SDRAM (could be a bug on the dram controller...)
	signal   sdram_save_data       : std_logic_vector(31 downto 0) := (others => '0'); -- Save SDRAM Data when a Read IRQ occurs

	-- Flash Memory Control Constants and Variables:
	constant FLASH_MEM_BUFF_SIZE          : integer :=  4 * 8;   -- How many bits do we want to load from flash memory
	signal   fmem_wait_next_state         : fsm_t   := s_listen; -- After controling the memory and waiting, where shall the fsm state go next
	signal   fmem_write_enable_next_state : fsm_t   := s_listen; -- After write enabling, should we write to a page or erase a sector?
	signal   fmem_fsm_jumping             : boolean := false;    -- Will we jump erase/write->write_enable->ctrl_wait->erase/write ?
	signal   fmem_returned                : boolean := false;    -- Have we finished jumping erase/write->write_enable->ctrl_wait->erase/write ?
	signal   fmem_save_data               : std_logic_vector(FLASH_MEM_BUFF_SIZE-1 downto 0) := (others => '0'); -- Save Flash Memory Data
	signal   fmem_pages_loaded            : integer := 0; -- How many pages have we loaded so far?
	-- Flash Memory Instruction Constants (there's more instructions, but this is all we need):
	constant INSTR_READ_PAGE              : integer := 3;
	constant INSTR_WRITE_ENABLE           : integer := 6;
	constant INSTR_WRITE_PAGE             : integer := 2;
	constant INSTR_SECTOR_ERASE           : integer := 32;
	constant INSTR_CHIP_ERASE             : integer := 199;
	
	-- Memory Loading (Flash Memory -> SDRAM) Constants and variables:
	constant loadmem_wordcount_max        : integer := 512;   -- How many words (32 bits) do we want to load from Flash Memory
	signal   loadmem_wordcount            : integer := 0;     -- How many words have we loaded so far
	signal   loading_memory               : boolean := false; -- Are we currently loading memory?
	type load_mem_fsm_t is (
		s_loadmem_rd_page, 
		s_loadmem_write_sdram
	);
	signal load_mem_fsm : load_mem_fsm_t := s_loadmem_rd_page;
	
BEGIN
	-------------------------
	-------------------------
	------ Assignments ------
	-------------------------
	-------------------------
	
	-- SDRAM Controller Wire Assignments:
	--Multiplex these IOB wires between the CPU and the UART Link, so that we don't have to instantiate 2 SDRAM Controllers
	sdram_cmd_en      <= iob_sdram_cmd_en      WHEN uart_controlling ELSE cpu_sdram_cmd_en;
	sdram_cmd_wr      <= iob_sdram_cmd_wr      WHEN uart_controlling ELSE cpu_sdram_cmd_wr;
	sdram_cmd_address <= iob_sdram_cmd_address WHEN uart_controlling ELSE cpu_sdram_cmd_address;
	sdram_cmd_byte_en <= iob_sdram_cmd_byte_en WHEN uart_controlling ELSE cpu_sdram_cmd_byte_en;
	sdram_cmd_data_in <= iob_sdram_cmd_data_in WHEN uart_controlling ELSE cpu_sdram_cmd_data_in;
	
	-- Flash Memory Wire Assignments:
	fmem_enable       <= iob_fmem_enable;
	fmem_instruction  <= iob_fmem_instruction;
	fmem_address      <= to_integer(unsigned(iob_fmem_address));
	fmem_data_write   <= std_logic_vector(resize(unsigned(iob_fmem_data_write), fmem_data_write'length));
		
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
					---------------------------
					-- Initialize UART Link: --
					---------------------------
					when s_init => 
						loading_memory <= true;
						state          <= s_load_fmem;
					
					when s_init_done =>
						ready          <= '1';
						loading_memory <= false;
						state          <= s_listen; -- Now listen for UART Packets (if the feature is enabled)
						
					
					-------------------------------------------
					-- Load the Flash Memory into the SDRAM: --
					-------------------------------------------
					when s_load_fmem =>
						-- * Steps: *
						-- 1- Load a single page (at a time) from flash memory into 'fmem_save_data'
						-- 2- Return, then write from 'fmem_save_data' to 'data_buffer' (which will be used by the sdram write fsm state)
						-- 3- Repeat steps 1 and 2
						
						if loadmem_wordcount = loadmem_wordcount_max then
							-- We're finished loading all the words into SDRAM.
							state <= s_init_done;
						else
							case load_mem_fsm is
								when s_loadmem_rd_page =>
									-- Set from which aligned address we want to read from flash memory
									data_buffer(23 downto 0) <= std_logic_vector(to_unsigned(fmem_pages_loaded * 4, 24));
									fmem_pages_loaded        <= fmem_pages_loaded + 1;
									load_mem_fsm             <= s_loadmem_write_sdram; -- After reading it, we'll write this page into the SDRAM
									state                    <= s_fmem_read_page;      -- Go read the page
									
								when s_loadmem_write_sdram =>
									-- Set the SDRAM address:
									data_buffer(22 downto 0)  <= std_logic_vector(to_unsigned(loadmem_wordcount, 23));
									-- Set the Data:
									data_buffer(63 downto 32) <= fmem_save_data;
									loadmem_wordcount         <= loadmem_wordcount + 1;
									load_mem_fsm              <= s_loadmem_rd_page;
									
									-- Let's now write this data into the SDRAM:
									state <= s_sdram_write;
									
								when others => -- Ignore this
							end case;
						end if;
						
										
					-------------------------
					-- Listen for Packets: --
					-------------------------
					when s_listen =>
						uart_controlling <= false;
						iob_uart_write   <= '0';
						if uart_read_irq = '1' then
							-- TODO: Redirect this received byte from UART into the IRQ Controller of the CPU
							if (tx_enable or sdram_write_enable or fmem_write_enable) then -- If none of these 'OR conditions's are true, then the UART Link Debugging features are offline and we're in Release Mode 
								if uart_readdata = std_logic_vector(SOT) then
									state <= s_rxing;
								end if;
							end if;
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
											data_buffer <= (others => '0'); -- Clear out the data buffer
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
										data_buffer((data_buffer_fill_ctr+1)*8-1 downto data_buffer_fill_ctr*8) <= uart_readdata; -- Store this byte into the buffer
										data_buffer_fill_ctr <= data_buffer_fill_ctr + 1;
									else
										data_buffer_fill_ctr <= 0;
										rx_fsm_state <= "00";
										-- We've finished writing into the data buffer. Now we should expect an EOT byte:
										if uart_readdata = std_logic_vector(EOT) then
											-- Success! The received packet is good and ready to be used
											state            <= s_ctrl_switch;
											uart_controlling <= true;
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
								iob_uart_writedata <= data_buffer((data_buffer_fill_ctr+1)*8-1 downto data_buffer_fill_ctr*8);
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
						--	TODO: We'll want to parse a packet to enable an ACK packet whenever we write to the memory
				
						case carrier_buffer(CARRIER_TYPE) is
							when "00000000" => state <= s_listen; -- NULL Packet, ignore it
							when "00000001" => -- ** SDRAM WRITE ** --
								if sdram_write_enable then
									state <= s_sdram_write; -- Write to SDRAM Packet
								else -- SDRAM is disabled for UART communications
									state <= s_listen;
								end if;
								
							when "00000010" => -- ** SDRAM READ ** --
								if tx_enable then
									state <= s_sdram_read; -- Read from SDRAM Packet
								else 
									-- Transmission is disabled (or the SDRAM). Why even read if there's nowhere to send the data to? In this case, just go back to listening
									state <= s_listen;
								end if;
								
							when "00000101" => -- ** FLASH MEMORY READ PAGE ** --
								if tx_enable then
									state <= s_fmem_read_page;
								end if;
								
							when "00000110" => -- ** FLASH MEMORY WRITE PAGE ** --
								if fmem_write_enable then
									state <= s_fmem_write_page;
								end if;
								
							when "00000111" => -- ** FLASH MEMORY ERASE SECTOR ** --
								if fmem_write_enable then
									state <= s_fmem_erase_sector;
								end if;			
							
							when others => state <= s_listen; -- Unrecognized packet, ignore it
						end case;
					
					
					-----------------------------
					-- **** SDRAM CONTROL **** --
					-----------------------------
					when s_sdram_write =>
						-- Write word to SDRAM:
						iob_sdram_cmd_address <= data_buffer(22 downto 0);
						iob_sdram_cmd_data_in <= data_buffer(63 downto 32);
						iob_sdram_cmd_byte_en <= (others => '1');
						iob_sdram_cmd_wr      <= '1';
						iob_sdram_cmd_en      <= '1';
						state                 <= s_sdram_write_wait;
					
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
								if loading_memory then
									state <= s_load_fmem;
								else
									state <= s_listen;
								end if;
								-- TODO: In case the TX irq is enabled, instead of jumping to 's_listen', jump to 's_txing'
							end if;
						end if;
						
					when s_sdram_read =>
						iob_sdram_cmd_address <= data_buffer(22 downto 0);
						iob_sdram_cmd_data_in <= (others => '0');
						iob_sdram_cmd_byte_en <= (others => '1');
						iob_sdram_cmd_wr      <= '0';
						iob_sdram_cmd_en      <= '1';
						state                 <= s_sdram_read_wait;
					
					when s_sdram_read_wait =>
						iob_sdram_cmd_en <= '0';
						iob_sdram_cmd_byte_en <= (others => '0');
						if sdram_data_ready = '1' then
							-- TODO: For now, we'll just send this data through UART,
							-- in the future, we might want to send it to the CPU instead
							sdram_save_data <= sdram_data_out;
							
							-- Build and Transmit the received data back:
							data_buffer(31 downto 0)           <= sdram_data_out;
							carrier_buffer(CARRIER_TOTAL_SIZE) <= std_logic_vector(to_unsigned(carrier_buffer_sz + 4, 8));
							carrier_buffer(CARRIER_TYPE)       <= std_logic_vector(to_unsigned(PCKT_SDRAM_READ_ACK, 8));							
							carrier_buffer(CARRIER_MAG_TOP)    <= carrier_magic_top;
							carrier_buffer(CARRIER_MAG_BOT)    <= carrier_magic_bot;
							
							state <= s_txing; -- Send the data!
						end if;
						
				
					------------------------------------
					-- **** FLASH MEMORY CONTROL **** --
					------------------------------------
					when s_fmem_read_page =>
						iob_fmem_address     <= data_buffer(23 downto 0);
						
						iob_fmem_instruction <= INSTR_READ_PAGE;
						iob_fmem_enable      <= '1';
						fmem_wait_next_state <= s_fmem_read_page_done;
						state                <= s_fmem_control_wait;
						
					when s_fmem_read_page_done =>
						fmem_save_data <= fmem_data_read;
						
						if tx_enable and uart_controlling then
							-- Build and Transmit the received data back:
							data_buffer(31 downto 0)           <= fmem_data_read(31 downto 0);
							carrier_buffer(CARRIER_TOTAL_SIZE) <= std_logic_vector(to_unsigned(carrier_buffer_sz + 4, 8));
							carrier_buffer(CARRIER_TYPE)       <= std_logic_vector(to_unsigned(PCKT_FMEM_READPAG_ACK, 8));							
							carrier_buffer(CARRIER_MAG_TOP)    <= carrier_magic_top;
							carrier_buffer(CARRIER_MAG_BOT)    <= carrier_magic_bot;
							
							state <= s_txing; -- Send the data!
						else
							if loading_memory then
								state <= s_load_fmem;
							else
								state <= s_listen;
							end if;
						end if;
					
					when s_fmem_write_enable =>
							iob_fmem_instruction <= INSTR_WRITE_ENABLE;
							iob_fmem_enable      <= '1';
							fmem_wait_next_state <= fmem_write_enable_next_state;
							state                <= s_fmem_control_wait;
					
					when s_fmem_write_page =>
						if fmem_returned = false then
							-- We need to enable writing first:
							fmem_fsm_jumping             <= true;
							fmem_write_enable_next_state <= s_fmem_write_page;
							state                        <= s_fmem_write_enable;
						else
							-- Now we can write to the page:
							iob_fmem_address     <= data_buffer(23 downto 0);  -- Write to this address
							iob_fmem_data_write  <= data_buffer(63 downto 32); -- Write this data
							iob_fmem_instruction <= INSTR_WRITE_PAGE;
							iob_fmem_enable      <= '1';
							fmem_returned        <= false;
							fmem_wait_next_state <= s_listen; -- After writing and waiting for the write to finish, we'll return to listening to more UART packets
							-- TODO: In case the TX irq is enabled, instead of jumping to 's_listen', jump to 's_txing'
							state                <= s_fmem_control_wait;
						end if;
					
					when s_fmem_erase_sector =>
						if fmem_returned = false then
							-- We need to write enable first:
							fmem_fsm_jumping             <= true;
							fmem_write_enable_next_state <= s_fmem_erase_sector;
							state                        <= s_fmem_write_enable;
						else
							-- Now we can erase the sector:
							iob_fmem_address     <= data_buffer(23 downto 0); -- Erase from this address
							iob_fmem_instruction <= INSTR_SECTOR_ERASE;
							iob_fmem_enable      <= '1';
							fmem_returned        <= false;
							fmem_wait_next_state <= s_listen; -- After erasing and waiting for the command to finish, we'll return to listening to more UART packets
							-- TODO: In case the TX irq is enabled, instead of jumping to 's_listen', jump to 's_txing'
							state                <= s_fmem_control_wait;
						end if;
					
					when s_fmem_control_wait =>
						iob_fmem_enable <= '0';
						if fmem_ready = '1' then
							-- The memory instruction has finished:
							state <= fmem_wait_next_state;
							if fmem_fsm_jumping then
								fmem_returned    <= true;
								fmem_fsm_jumping <= false;
							end if;
						end if;
					
					when others => -- Invalid state!
				end case;
			end if;
		end if;	
	end process;	
END ARCHITECTURE RTL;