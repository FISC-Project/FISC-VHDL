LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
use IEEE.std_logic_textio.all;
use std.textio.all;
USE work.FISC_DEFINES.all;

ENTITY DRAM_Controller_Sim IS
	PORT(
		clk           : in  std_logic;
		reset         : in  std_logic;
		cmd_en        : in  std_logic;
		cmd_wr        : in  std_logic;
		cmd_ready     : out std_logic;
		address       : in  std_logic_vector(22 downto 0);
		data_in       : in  std_logic_vector(31 downto 0);
		data_ready    : out std_logic;
		data_out      : out std_logic_vector(31 downto 0)
	);
END DRAM_Controller_Sim;

ARCHITECTURE RTL OF DRAM_Controller_Sim IS
	type mem_t is array (0 to 255) of std_logic_vector(7 downto 0);
	
	impure function load_dram_mem(filename : STRING) return mem_t is
		file file_handle      : text;
		variable current_line : line;
		variable tmp_byte     : std_logic_vector(7 downto 0);
  		variable ret          : mem_t := (others => (others => '0'));
  	begin
		file_open (file_handle, filename, READ_MODE);
		for i in mem_t'range loop
			if not ENDFILE(file_handle) then
				readline(file_handle, current_line);
				read(current_line, tmp_byte);
				ret(i) := tmp_byte;
			end if;
		end loop;
		return ret;
	end function;
	
	signal dram_mem : mem_t := load_dram_mem("fisc_imem.bin");
BEGIN
	process(clk) 
		variable index_field : integer := 0;
		variable address_append : std_logic_vector(40 downto 0) := (others => '0');
		variable address_fixed  : std_logic_vector(63 downto 0);
	begin
		if clk'event and clk = '1' then
			if cmd_en = '1' then
				address_fixed := address_append & address;
				index_field   := to_integer(unsigned(address(4 downto 0))) + (to_integer(unsigned(address_fixed(L1_IC_INDEXOFF downto 6))) * L1_IC_DATABLOCKSIZE) * (to_integer(unsigned(address_fixed(L1_IC_ADDR_WIDTH-1 downto L1_IC_ADDR_WIDTH-L1_IC_TAGWIDTH))) + 1);
				if cmd_wr = '0' then 
					-- Read from Memory:
					data_out(7  downto 0)  <= dram_mem(index_field + 3);
					data_out(15 downto 8)  <= dram_mem(index_field + 2);
					data_out(23 downto 16) <= dram_mem(index_field + 1);
					data_out(31 downto 24) <= dram_mem(index_field);
				else
					-- Write to Memory:
					dram_mem(index_field + 3) <= data_in(7  downto 0);
					dram_mem(index_field + 2) <= data_in(15 downto 8);
					dram_mem(index_field + 1) <= data_in(23 downto 16);
					dram_mem(index_field)     <= data_in(31 downto 24);
				end if;
				cmd_ready  <= '1';
				data_ready <= '1';
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;
