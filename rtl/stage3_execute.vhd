LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage3_Execute IS
	PORT(
		clk       : in  std_logic;
		opA       : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		opB       : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		result    : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		sign_ext  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		aluop     : in  std_logic_vector(1  downto 0);
		opcode    : in  std_logic_vector(10 downto 0);
		alusrc    : in  std_logic;
		alu_neg   : out std_logic;
		alu_zero  : out std_logic;
		alu_overf : out std_logic;
		alu_carry : out std_logic
	);
END Stage3_Execute;

ARCHITECTURE RTL OF Stage3_Execute IS
	COMPONENT ALU
		PORT(
			clk         : in  std_logic;
			opA         : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			opB         : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			func        : in  std_logic_vector(3 downto 0);
			result      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			signed_flag : in  std_logic;
			neg         : out std_logic := '0'; 
			zero        : out std_logic := '0';
			overf       : out std_logic := '0';
			carry       : out std_logic := '0'
		);
	END COMPONENT;
	
	signal opB_reg  : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal func_reg : std_logic_vector(3 downto 0) := (others => '0');
BEGIN
	-- Instantiate ALU:
	ALU1: ALU PORT MAP(clk, opA, opB_reg, func_reg, result, alusrc, alu_neg, alu_zero, alu_overf, alu_carry);

	-- Instantiate Forward Unit:
	-- TODO

	opB_reg    <= sign_ext WHEN alusrc = '1' ELSE opB;
	
	func_reg   <= "0010" WHEN aluop = "00" ELSE "0111" WHEN aluop(0) = '1' ELSE 
	              "0010" WHEN (aluop(1) = '1' AND (opcode = "10001011000" or opcode(10 downto 1) = "1001000100" or opcode(10 downto 1) = "1011000100" or opcode = "10101011000" or opcode(10 downto 2) = "111100101" or opcode(10 downto 2) = "110100101")) ELSE -- ADD, MOVK and MOVZ
	              "0110" WHEN (aluop(1) = '1' AND (opcode = "11001011000" or opcode(10 downto 1) = "1101000100" or opcode(10 downto 1) = "1111000100" or opcode = "11101011000")) ELSE -- SUB
	              "0000" WHEN (aluop(1) = '1' AND (opcode = "10001010000" or opcode(10 downto 1) = "1001001000" or opcode(10 downto 1) = "1111001000" or opcode = "11101010000")) ELSE -- AND
	              "0001" WHEN (aluop(1) = '1' AND (opcode = "10101010000" or opcode(10 downto 1) = "1011001000")) ELSE -- ORR
	              "0011" WHEN (aluop(1) = '1' AND (opcode = "11001010000" or opcode(10 downto 1) = "1101001000")) ELSE -- EOR
	              "1000" WHEN (aluop(1) = '1' AND (opcode = "11101101000" or opcode(10 downto 1) = "0111000100")) ELSE -- NEG
	              "1001" WHEN (aluop(1) = '1' AND (opcode = "11101101001" or opcode(10 downto 1) = "0101000100")) ELSE -- NOT
	              "1010" WHEN (aluop(1) = '1' AND (opcode = "10011011000" or opcode = "10011011010")) ELSE -- MUL and SMULH
	              "1011" WHEN (aluop(1) = '1' AND (opcode = "10011011110")) ELSE -- UMULH
	              "1100" WHEN (aluop(1) = '1' AND (opcode = "10011010110")) ELSE -- SDIV
	              "1101" WHEN (aluop(1) = '1' AND (opcode = "10011010111")) ELSE -- UDIV
	              "1110" WHEN (aluop(1) = '1' AND (opcode = "11010011011")) ELSE -- LSL
	              "1111" WHEN (aluop(1) = '1' AND (opcode = "11010011010")) ELSE -- LSR
	              (others => 'X');
END ARCHITECTURE RTL;