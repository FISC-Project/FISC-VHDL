LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

------------------------------------------------------------------------------------------------
-- Information:
-- The Module Memory Handler's purpose is to simply bypass (or not, it's a choice) the L1 Caches
------------------------------------------------------------------------------------------------

ENTITY Memory_Handler IS
	PORT(
		clk               : in  std_logic;
		start_trans       : in  std_logic; -- Trigger memory fetch / memory write
		address           : in  std_logic_vector(L1_IC_ADDR_WIDTH-1 downto 0);
		memory_busy       : out std_logic := '0'; -- Are we currently fetching memory?
		data_out          : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		-- SDRAM Controls:
		sdram_cmd_ready   : in  std_logic;
		sdram_cmd_en      : out std_logic := '0';
		sdram_cmd_wr      : out std_logic := '0';
		sdram_cmd_address : out std_logic_vector(22 downto 0) := (others => '0');
		sdram_cmd_byte_en : out std_logic_vector(3  downto 0) := (others => '0');
		sdram_cmd_data_in : out std_logic_vector(31 downto 0) := (others => '0');
		sdram_data_out    : in  std_logic_vector(31 downto 0);
		sdram_data_ready  : in  std_logic
	);
END Memory_Handler;

ARCHITECTURE RTL OF Memory_Handler IS
	signal memory_busy_reg : std_logic := '0';
BEGIN
	memory_busy <= memory_busy_reg;
	
	-------------------------------
	-- Memory Handler Behaviour: --
	-------------------------------
	main_proc: process(clk, start_trans) is
	begin
		if rising_edge(clk) then
			if memory_busy_reg = '1' and sdram_data_ready = '1' then
				-- We're done fetching memory:	
				memory_busy_reg <= '0';
				sdram_cmd_en    <= '0';	
				data_out        <= sdram_data_out;
			elsif start_trans = '1' and memory_busy_reg = '0' then
				-- Requesting Memory transaction (read or write):
				sdram_cmd_address <= address(22 downto 0); -- The SDRAM's address is only 23 bits long
				sdram_cmd_wr      <= '0'; -- SDRAM in read mode
				sdram_cmd_byte_en <= (others => '1'); -- TODO: Allow different sizes of memory to be accessed
				sdram_cmd_en      <= '1'; -- Enable SDRAM Controller (trigger request)
				memory_busy_reg   <= '1'; -- This will stall the CPU until the Fetch cycle has finished
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;