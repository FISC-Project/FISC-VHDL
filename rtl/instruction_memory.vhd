LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
use IEEE.std_logic_textio.all;
use std.textio.all;
USE work.FISC_DEFINES.all;

-- NOTE: The name 'instruction memory' will be temporary for simplicity and debugging purposes. It will be later renamed to L1 I-Cache.

ENTITY Instruction_Memory IS
	PORT(
		address     : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
		instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0)
	);
END;

ARCHITECTURE RTL OF Instruction_Memory IS
	signal instruction_reg : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');

	type mem_t is array (0 to 255) of std_logic_vector(7 downto 0);
	
	impure function load_imem(filename : STRING) return mem_t is
		file file_handle      : text;
		variable current_line : line;
		variable tmp_word     : std_logic_vector(31 downto 0);
  		variable ret          : mem_t   := (others => (others => '0'));
  		variable skip         : integer := 0;
	begin
		file_open (file_handle, filename, READ_MODE);
		for i in mem_t'range loop
			if not ENDFILE(file_handle) and skip = 0 then
				readline(file_handle, current_line);
				hread(current_line, tmp_word);
				ret(i+3) := tmp_word(31 downto 24);
				ret(i+2) := tmp_word(23 downto 16);
				ret(i+1) := tmp_word(15 downto 8);
				ret(i)   := tmp_word(7  downto 0);
				skip := 4;
			end if;
			if skip > 0 then
				skip := skip - 1;
			end if;
		end loop;
		
		return ret;
	end function;
	
	signal imem : mem_t := load_imem("fisc_imem.bin");
BEGIN
	instruction <= imem(to_integer(unsigned(address + "11"))) & imem(to_integer(unsigned(address + "10"))) & imem(to_integer(unsigned(address + "01"))) & imem(to_integer(unsigned(address)));
END ARCHITECTURE RTL;