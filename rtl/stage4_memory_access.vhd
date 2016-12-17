LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage4_Memory_Access IS
	PORT(
		clk                   : in  std_logic;
		address               : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_in               : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- data_in is just the output of the main memory. This stage will only pipeline this wire into data_out
		data_out              : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Pipeline data output
		-- Pipeline (data) outputs:
		mem_address           : out std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
		ifidex_instruction    : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		ifidexmem_instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		ifidex_pc_out         : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
		ifidexmem_pc_out      : out std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
		idex_regwrite         : in  std_logic;
		idex_memtoreg         : in  std_logic;
		idexmem_regwrite      : out std_logic := '0';
		idexmem_memtoreg      : out std_logic := '0';
		-- Pipeline flush/freeze:
		mem_flush             : in  std_logic;
		mem_freeze            : in  std_logic
	);
END Stage4_Memory_Access;

ARCHITECTURE RTL OF Stage4_Memory_Access IS	
BEGIN
	----------------
	-- Behaviour: --
	----------------
	main_proc: process(clk) begin
		if falling_edge(clk) then
			if mem_freeze = '0' then
				if mem_flush = '0' then			
					-- Move the Memory Access Stage's Inner Pipeline Forward:
					data_out              <= data_in;
					mem_address           <= address;
					ifidexmem_instruction <= ifidex_instruction;
					ifidexmem_pc_out      <= ifidex_pc_out;
					-- Move the controls:
					idexmem_regwrite      <= idex_regwrite;
					idexmem_memtoreg      <= idex_memtoreg;
				else
					-- Stall the pipeline (preserve the data):
					idexmem_regwrite      <= '0';
					idexmem_memtoreg      <= '0';
				end if;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;