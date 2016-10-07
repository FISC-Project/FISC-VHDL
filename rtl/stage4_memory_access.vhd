LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
use IEEE.std_logic_textio.all;
use std.textio.all;
USE work.FISC_DEFINES.all;

-- NOTE: The name 'data memory' will be temporary for simplicity and debugging purposes. It will be later renamed to L1 D-Cache.

ENTITY Data_Memory IS
	PORT(
		clk      : in  std_logic;
		address  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_in  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_out : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		memwrite : in  std_logic;
		memread  : in  std_logic
	);
END Data_Memory;

ARCHITECTURE RTL OF Data_Memory IS
	type mem_t is array (0 to 255) of std_logic_vector(7 downto 0);
	
	impure function load_dmem(filename : STRING) return mem_t is
		file file_handle      : text;
		variable current_line : line;
		variable tmp_dword    : std_logic_vector(63 downto 0);
  		variable ret          : mem_t   := (others => (others => '0'));
  		variable skip         : integer := 0;
	begin
		file_open (file_handle, filename, READ_MODE);
		for i in mem_t'range loop
			if not ENDFILE(file_handle) and skip = 0 then
				readline(file_handle, current_line);
				hread(current_line, tmp_dword);
				ret(i+7) := tmp_dword(63 downto 56);
				ret(i+6) := tmp_dword(55 downto 48);
				ret(i+5) := tmp_dword(47 downto 40);
				ret(i+4) := tmp_dword(39 downto 32);
				ret(i+3) := tmp_dword(31 downto 24);
				ret(i+2) := tmp_dword(23 downto 16);
				ret(i+1) := tmp_dword(15 downto 8);
				ret(i)   := tmp_dword(7  downto 0);
				skip := 8;
			end if;
			if skip > 0 then
				skip := skip - 1;
			end if;
		end loop;
		
		return ret;
	end function;
	
	signal memory : mem_t := load_dmem("fisc_dmem.bin");
BEGIN
	data_out <= 
			memory(to_integer(unsigned(address+"111"))) & memory(to_integer(unsigned(address+"110"))) & memory(to_integer(unsigned(address+"101"))) & memory(to_integer(unsigned(address+"100"))) &
			memory(to_integer(unsigned(address+"011"))) & memory(to_integer(unsigned(address+"010"))) & memory(to_integer(unsigned(address+"001"))) & memory(to_integer(unsigned(address)))
		WHEN memread = '1' ELSE (data_out'range => 'Z');
	
	process(clk) begin
		if clk'event and clk = '1' then
			memory(to_integer(unsigned(address+"111"))) <= data_in(63 downto 56);
			memory(to_integer(unsigned(address+"110"))) <= data_in(55 downto 48);
			memory(to_integer(unsigned(address+"101"))) <= data_in(47 downto 40);
			memory(to_integer(unsigned(address+"100"))) <= data_in(39 downto 32);
			memory(to_integer(unsigned(address+"011"))) <= data_in(31 downto 24);
			memory(to_integer(unsigned(address+"010"))) <= data_in(23 downto 16);
			memory(to_integer(unsigned(address+"001"))) <= data_in(15 downto 8);
			memory(to_integer(unsigned(address)))       <= data_in(7  downto 0);
		end if;
	end process;
END ARCHITECTURE RTL;

-----------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage4_Memory_Access IS
	PORT(
		clk      : in  std_logic;
		address  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_in  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_out : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		memwrite : in  std_logic;
		memread  : in  std_logic
	);
END Stage4_Memory_Access;

ARCHITECTURE RTL OF Stage4_Memory_Access IS
	COMPONENT Data_Memory
		PORT(
			clk      : in  std_logic;
			address  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			data_in  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			data_out : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			memwrite : in  std_logic;
			memread  : in  std_logic
		);
	END COMPONENT;
BEGIN
	Data_Memory1: Data_Memory PORT MAP(clk, address, data_in, data_out, memwrite, memread);
END ARCHITECTURE RTL;