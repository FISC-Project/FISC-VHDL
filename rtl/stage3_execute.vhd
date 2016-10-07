LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage3_Execute IS
	PORT(
		clk        : in  std_logic;
		opA        : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		opB        : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		result     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		add_uncond : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		pc         : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		sign_ext   : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		aluop      : in  std_logic_vector(1  downto 0);
		opcode     : in  std_logic_vector(10 downto 0);
		alusrc     : in  std_logic;
		zero       : out std_logic
	);
END Stage3_Execute;

ARCHITECTURE RTL OF Stage3_Execute IS
	COMPONENT ALU
		PORT(
			clk    : in  std_logic;
			opA    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			opB    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			func   : in  std_logic_vector(3 downto 0);
			zero   : out std_logic;
			result : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
		);
	END COMPONENT;
	
	signal opB_reg : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
BEGIN
	ALU1: ALU PORT MAP(clk, opA, opB_reg, "0000", zero, result);

	opB_reg    <= sign_ext WHEN alusrc = '1' ELSE opB;
	add_uncond <= (sign_ext(FISC_INTEGER_SZ-2 downto 0) & '0') + pc;
END ARCHITECTURE RTL;