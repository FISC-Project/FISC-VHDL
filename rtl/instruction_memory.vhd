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
	type mem_t is array (0 to 255) of std_logic_vector(7 downto 0);
	
	impure function load_imem(filename : STRING) return mem_t is
		file file_handle      : text;
		variable current_line : line;
		variable tmp_byte     : std_logic_vector(7 downto 0);
  		variable ret          : mem_t   := (others => (others => '0'));
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
	
	signal imem : mem_t := load_imem("fisc_imem.bin");
BEGIN
	instruction <= imem(to_integer(unsigned(address))) & imem(to_integer(unsigned(address + "01"))) & imem(to_integer(unsigned(address + "10"))) & imem(to_integer(unsigned(address + "11")));
END ARCHITECTURE RTL;