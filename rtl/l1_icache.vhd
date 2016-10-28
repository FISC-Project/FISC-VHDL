LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY L1_ICache_Way IS
	PORT(
		clk        : in  std_logic;
		way_idx_in : in  integer;
		tag_in     : in  std_logic_vector(L1_IC_TAGWIDTH - 1 downto 0);
		hit        : out std_logic;
		data_out   : out std_logic_vector((L1_IC_DATABLOCKSIZE * 8) - 1 downto 0);
		data_in    : in  std_logic_vector((L1_IC_DATABLOCKSIZE * 8) - 1 downto 0);
		wr         : in  std_logic;
		wr_way     : in  integer
	);
END L1_ICache_Way;

ARCHITECTURE RTL OF L1_ICache_Way IS
	signal valid   : std_logic := '0';
	signal tag     : std_logic_vector(L1_IC_TAGWIDTH - 1 downto 0) := (others => '0');
	signal data    : std_logic_vector((L1_IC_DATABLOCKSIZE * 8) - 1 downto 0) := (others => '0');
	signal hit_reg : std_logic := '0';
BEGIN
	hit_reg  <= '1'  WHEN tag_in = tag AND valid = '1' ELSE '0';
	hit      <= hit_reg;
	data_out <= data WHEN hit_reg = '1' ELSE (others => 'Z');
	
	process(clk) begin
		if clk'event and clk = '1' then
			if wr = '1' and wr_way = way_idx_in then
				tag   <= tag_in;
				data  <= data_in;
				valid <= '1';
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;

-------------------------------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE ieee.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY L1_ICache_Set IS
	PORT(
		clk        : in  std_logic;
		set_idx_in : in  integer;
		tag_in     : in  std_logic_vector(L1_IC_TAGWIDTH - 1 downto 0); -- Compare this tag with every Way in this set
		hit        : out std_logic;
		data_out   : out std_logic_vector((L1_IC_DATABLOCKSIZE * 8) - 1 downto 0);
		data_in    : in  std_logic_vector((L1_IC_DATABLOCKSIZE * 8) - 1 downto 0);   
		wr         : in  std_logic;
		wr_way     : in  integer;
		wr_set     : in  integer;
		sel_set    : in  std_logic_vector(L1_IC_INDEXWIDTH-1 downto 0)  -- Selected Set on the bus
	);
END L1_ICache_Set;

ARCHITECTURE RTL OF L1_ICache_Set IS
	signal hitbus         : std_logic_vector(L1_IC_WAYCOUNT-1 downto 0);
	signal wide_data_out  : std_logic_vector((L1_IC_DATABLOCKSIZE * L1_IC_WAYCOUNT * 8) - 1 downto 0); -- Huge aggregated data bus from all the ways in each set
	signal wr_ways_enable : std_logic;
BEGIN
	GEN_WAYS:
	for i in 0 to L1_IC_WAYCOUNT-1 generate
		WAYX: ENTITY work.L1_ICache_Way 
			PORT MAP(clk, i, tag_in, hitbus(i), wide_data_out(((i+1) * L1_IC_DATABLOCKSIZE * 8)-1 downto i * L1_IC_DATABLOCKSIZE * 8), data_in, wr_ways_enable, wr_way);	
	end generate GEN_WAYS;
	
	-- Enable or disable writting to this Set's Ways
	wr_ways_enable <= '1' WHEN wr = '1' AND wr_set = set_idx_in ELSE '0';
	
	-- Select the data from the ways based on the hit bus (TODO: Use generate on the statements below):
	data_out <= 
		wide_data_out((1 * L1_IC_DATABLOCKSIZE * 8)-1 downto 0)                             WHEN hitbus = "01" ELSE
		wide_data_out((2 * L1_IC_DATABLOCKSIZE * 8)-1 downto (1 * L1_IC_DATABLOCKSIZE * 8)) WHEN hitbus = "10" ELSE
		(others => 'Z');
		
	hit <= '1' WHEN to_integer(unsigned(hitbus)) > 0 AND to_integer(unsigned(sel_set)) = set_idx_in ELSE '0';
END ARCHITECTURE RTL;

-------------------------------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE ieee.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY L1_ICache IS
	PORT(
		clk            : in  std_logic;
		request_data   : in  std_logic; -- Trigger the search for the data using the specified address on the L1 Instruction Cache
		address        : in  std_logic_vector(L1_IC_ADDR_WIDTH-1 downto 0);
		hit            : out std_logic;
		miss           : out std_logic;
		data           : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		data_src       : out std_logic := '0'
	);
END L1_ICache;

ARCHITECTURE RTL OF L1_ICache IS
	signal hitwidebus          : std_logic_vector(L1_IC_SETCOUNT-1 downto 0);
	signal super_wide_data_out : std_logic_vector((L1_IC_DATABLOCKSIZE * L1_IC_SETCOUNT * 8) - 1 downto 0); -- Huge aggregated data bus from all the sets' output
	signal hit_reg             : std_logic := '0';
	signal data_ready          : std_logic := '0';
	signal data_reg            : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	
	signal DRAM_datablock_out  : std_logic_vector((L1_IC_DATABLOCKSIZE * 8)-1 downto 0);
	
	-- Write data to Cache signals:
	signal cache_wr            : std_logic := '0';
	signal cache_wr_way        : integer   :=  0;
	signal cache_wr_set        : integer   :=  0;
		
	function data_output_handle
	(
		hit_reg             : std_logic;
		address             : std_logic_vector(L1_IC_ADDR_WIDTH-1 downto 0);
		DRAM_datablock_out  : std_logic_vector((L1_IC_DATABLOCKSIZE * 8)-1 downto 0);
		super_wide_data_out : std_logic_vector((L1_IC_DATABLOCKSIZE * L1_IC_SETCOUNT * 8) - 1 downto 0)
	) return std_logic_vector is
		variable data_ret                   : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		variable super_wide_data_out_offset : integer := 0;
		variable wordoff_field              : integer;
		variable index_field                : std_logic_vector(L1_IC_INDEXOFF-L1_IC_BYTE_OFF downto 0) := (others => '0');
	begin 
		if hit_reg = '0' then
			wordoff_field := to_integer(unsigned(address(L1_IC_WORDOFF-1 downto 2))) * FISC_INSTRUCTION_SZ;
			data_ret := DRAM_datablock_out(DRAM_datablock_out'length-wordoff_field-1 downto DRAM_datablock_out'length-wordoff_field-FISC_INSTRUCTION_SZ);
		else
			index_field   := address(L1_IC_INDEXOFF downto L1_IC_BYTE_OFF);
			wordoff_field := to_integer(unsigned(address(L1_IC_WORDOFF-1 downto 2)));
			super_wide_data_out_offset := (to_integer(unsigned(index_field)) + 1) * L1_IC_DATABLOCKSIZE * 8 - (wordoff_field * FISC_INSTRUCTION_SZ);
			data_ret := super_wide_data_out(super_wide_data_out_offset-1 downto super_wide_data_out_offset-FISC_INSTRUCTION_SZ);
		end if;
		return data_ret;
	end data_output_handle;
BEGIN
	DRAM_Sim1 : ENTITY work.DRAM_Sim PORT MAP(address, DRAM_datablock_out);

	-- Generate all the Sets in the Cache:
	GEN_SETS:
	for i in 0 to L1_IC_SETCOUNT-1 generate
		SETX: ENTITY work.L1_ICache_Set 
			PORT MAP(clk, i, address(L1_IC_ADDR_WIDTH-1 downto L1_IC_ADDR_WIDTH-L1_IC_TAGWIDTH), hitwidebus(i), super_wide_data_out(((i+1) * L1_IC_DATABLOCKSIZE * 8)-1 downto i * L1_IC_DATABLOCKSIZE * 8), DRAM_datablock_out, cache_wr, cache_wr_way, cache_wr_set, address(L1_IC_INDEXOFF downto L1_IC_BYTE_OFF));
	end generate GEN_SETS;
	
	data     <= data_output_handle(hit_reg, address, DRAM_datablock_out, super_wide_data_out);	
	hit_reg  <= '0' WHEN to_integer(unsigned(hitwidebus)) = 0 ELSE '1';
	hit      <= hit_reg or data_ready;
	miss     <= not hit_reg;
	
	process(clk, request_data)
		variable wordoff_field  : integer;
		variable index_field    : std_logic_vector(L1_IC_INDEXOFF-L1_IC_BYTE_OFF downto 0) := (others => '0');
		variable super_wide_data_out_offset : integer := 0;
	begin
		if clk'event and clk = '1' and request_data = '1' then
			if hit_reg = '0' then -- It's a miss...
				-- Algorithm:
				-- Fetch a data block from main memory using the address and store it in the cache. Also, output the data in parallel into the CPU Core.
				
				-- Now write this received block into Cache:
				index_field := address(L1_IC_INDEXOFF downto L1_IC_BYTE_OFF);
				
				cache_wr_way <= 0; -- TODO: Use algorithm to decide in which way to put this block
				cache_wr_set <= to_integer(unsigned(index_field)); -- The set field is always fixed in set associative caches
				cache_wr <= '1';
				
				-- Make the data ready:
				data_ready <= '1'; -- TODO: In the future it will take multiple cycles for this flag to be '1' because of the DRAM Controller
				data_src   <= '1'; -- The data came from Main Memory
			else -- It's a hit!
				-- Note: the data is already being outputted in parallel due to the assignment and the function data_output_handle()
				
				-- We're not writing to cache anymore:
				cache_wr <= '0';
			
				-- Make the data ready:
				data_ready <= '0';
				data_src   <= '0'; -- The data came from Cache
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;