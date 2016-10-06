LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY RegFile IS
	PORT(
		clk       : in  std_logic;
		readreg1  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		readreg2  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		writereg  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		writedata : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		outA      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		outB      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		regwr     : in  std_logic
	);
END RegFile;

ARCHITECTURE RTL OF RegFile IS
	type regfile_t is array (0 to FISC_REGISTER_COUNT-1) of std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal regfile : regfile_t := (others => (others => '0'));
BEGIN
	process(clk) begin
		if clk'event and clk = '1' then
			outA <= regfile(to_integer(unsigned(readreg1)));
			outB <= regfile(to_integer(unsigned(readreg2)));
			if regwr = '1' then
				regfile(to_integer(unsigned(writereg))) <= writedata;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;