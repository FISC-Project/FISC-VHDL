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
		clk          : in  std_logic;
		address      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_in      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_out     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		memwrite     : in  std_logic;
		memread      : in  std_logic;
		access_width : in  std_logic_vector(1 downto 0)
	);
END Data_Memory;

ARCHITECTURE RTL OF Data_Memory IS
	type mem_t is array (0 to 255) of std_logic_vector(7 downto 0);
	
	impure function load_dmem(filename : STRING) return mem_t is
		file file_handle      : text;
		variable current_line : line;
		variable tmp_byte     : std_logic_vector(7 downto 0);
  		variable ret          : mem_t   := (others => (others => '0'));
  		variable skip         : integer := 0;
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
	
	signal memory : mem_t := load_dmem("fisc_dmem.bin");
BEGIN
	data_out <= 
			-- Read 64 bits:
			memory(to_integer(unsigned(address))) & memory(to_integer(unsigned(address+"001"))) & memory(to_integer(unsigned(address+"010"))) & memory(to_integer(unsigned(address+"011"))) &
			memory(to_integer(unsigned(address+"100"))) & memory(to_integer(unsigned(address+"101"))) & memory(to_integer(unsigned(address+"110"))) & memory(to_integer(unsigned(address+"111")))
		WHEN memread = '1' and access_width = "11" ELSE
			-- Read 8 bits:
			(63 downto 8 => '0') & memory(to_integer(unsigned(address)))
		WHEN memread = '1' and access_width = "00" ELSE
			-- Read 16 bits:
			(63 downto 16 => '0') & memory(to_integer(unsigned(address))) & memory(to_integer(unsigned(address+"001")))
		WHEN memread = '1' and access_width = "01" ELSE 
			-- Read 32 bits:
			(63 downto 32 => '0') & memory(to_integer(unsigned(address))) & memory(to_integer(unsigned(address+"001"))) &
									memory(to_integer(unsigned(address+"010"))) & memory(to_integer(unsigned(address+"011")))
		WHEN memread = '1' and access_width = "10" ELSE 
			(data_out'range => 'Z');
	
	process(clk, memwrite) begin
		if clk'event and clk = '1' and memwrite = '1' then
			case access_width is
				when "11" => 
					memory(to_integer(unsigned(address)))       <= data_in(63 downto 56);
					memory(to_integer(unsigned(address+"001"))) <= data_in(55 downto 48);
					memory(to_integer(unsigned(address+"010"))) <= data_in(47 downto 40);
					memory(to_integer(unsigned(address+"011"))) <= data_in(39 downto 32);
					memory(to_integer(unsigned(address+"100"))) <= data_in(31 downto 24);
					memory(to_integer(unsigned(address+"101"))) <= data_in(23 downto 16);
					memory(to_integer(unsigned(address+"110"))) <= data_in(15 downto 8);
					memory(to_integer(unsigned(address+"111"))) <= data_in(7  downto 0);
				when "00" =>
					memory(to_integer(unsigned(address)))       <= data_in(7  downto 0);
				when "01" =>
					memory(to_integer(unsigned(address)))       <= data_in(15 downto 8);
					memory(to_integer(unsigned(address+"001"))) <= data_in(7  downto 0);
				when "10" =>
					memory(to_integer(unsigned(address)))       <= data_in(31 downto 24);
					memory(to_integer(unsigned(address+"001"))) <= data_in(23 downto 16);
					memory(to_integer(unsigned(address+"010"))) <= data_in(15 downto 8);
					memory(to_integer(unsigned(address+"011"))) <= data_in(7  downto 0);
				when others =>
			end case;
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
		clk          : in  std_logic;
		address      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_in      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		data_out     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Pipeline data output
		memwrite     : in  std_logic; -- Consume control on this stage
		memread      : in  std_logic; -- Consume control on this stage
		access_width : in  std_logic_vector(1 downto 0);
		-- Pipeline (data) outputs:
		mem_address           : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)     := (others => '0');
		ifidex_instruction    : in std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		ifidexmem_instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		idex_regwrite         : in std_logic;
		idex_memtoreg         : in std_logic;
		idexmem_regwrite      : out std_logic := '0';
		idexmem_memtoreg      : out std_logic := '0'
	);
END Stage4_Memory_Access;

ARCHITECTURE RTL OF Stage4_Memory_Access IS
	COMPONENT Data_Memory
		PORT(
			clk          : in  std_logic;
			address      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			data_in      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			data_out     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			memwrite     : in  std_logic;
			memread      : in  std_logic;
			access_width : in  std_logic_vector(1 downto 0)
		);
	END COMPONENT;
	
	-- Inner Pipeline Layer:
	signal data_out_reg : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
BEGIN
	Data_Memory1: Data_Memory PORT MAP(clk, address, data_in, data_out_reg, memwrite, memread, access_width);
	
	process(clk) begin
		if clk'event and clk = '0' then
			-- Move the Memory Access Stage's Inner Pipeline Forward:
			data_out <= data_out_reg;
			mem_address <= address;
			ifidexmem_instruction <= ifidex_instruction;
			-- Move the controls:
			idexmem_regwrite <= idex_regwrite;
			idexmem_memtoreg <= idex_memtoreg;
		end if;
	end process;
END ARCHITECTURE RTL;