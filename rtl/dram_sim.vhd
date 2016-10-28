LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
use IEEE.std_logic_textio.all;
use std.textio.all;
USE work.FISC_DEFINES.all;

ENTITY DRAM_Sim IS
	PORT(
		address_l1ic   : in  std_logic_vector(FISC_INTEGER_SZ-1           downto 0);
		datablock_l1ic : out std_logic_vector((L1_IC_DATABLOCKSIZE * 8)-1 downto 0)
	);
END DRAM_Sim;

ARCHITECTURE RTL OF DRAM_Sim IS
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
	
	signal dram_mem : mem_t := 
		(
		0 =>  "10001011",
		1 =>  "00011111",
		2 =>  "00000011",
		3 =>  "11111111",
		4 =>  "10001011",
		5 =>  "00011111",
		6 =>  "00000011",
		7 =>  "11111111",
		8 =>  "00010100",
		9 =>  "00000000",
		10 => "00000000",
		11 => "00000000",
		others => (others => '0')); 
		--load_dram_mem("fisc_imem.bin");
	
	function build_l1ic_datablock(
		dram_mem     : mem_t;
		address_l1ic : std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	) return std_logic_vector is
		variable aggregate     : std_logic_vector((L1_IC_DATABLOCKSIZE * 8)-1 downto 0);
		variable index_field   : integer;
		variable j             : integer := 0;
	begin
		index_field := (to_integer(unsigned(address_l1ic(L1_IC_INDEXOFF downto 6))) * L1_IC_DATABLOCKSIZE) * (to_integer(unsigned(address_l1ic(L1_IC_ADDR_WIDTH-1 downto L1_IC_ADDR_WIDTH-L1_IC_TAGWIDTH))) + 1);
		for i in index_field to index_field+L1_IC_DATABLOCKSIZE-1 loop
			aggregate((((L1_IC_DATABLOCKSIZE-j-1)+1)*8)-1 downto (L1_IC_DATABLOCKSIZE-j-1)*8) 
				:= dram_mem(i);
			j := j + 1;
		end loop;
		return aggregate;
	end build_l1ic_datablock;
BEGIN
	datablock_l1ic <= build_l1ic_datablock(dram_mem, address_l1ic);
END ARCHITECTURE RTL;
