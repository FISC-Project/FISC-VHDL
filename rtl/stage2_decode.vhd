LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage2_Decode IS
	PORT(
		clk            : in  std_logic;
		sos            : in  std_logic;
		microcode_ctrl : out std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
		if_instruction : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		writedata      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		reg2loc        : in  std_logic;
		regwrite       : in  std_logic;
		outA           : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		outB           : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS
	COMPONENT RegFile
		PORT(
			clk       : in  std_logic;
			readreg1  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			readreg2  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writereg  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writedata : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outA      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outB      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			regwr     : in std_logic
		);
	END COMPONENT;
	
	signal tmp_readreg1 : std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
BEGIN
	-- Instantiate Microcode Unit:
	Microcode1: Microcode 
		PORT MAP(clk, sos, if_instruction(R_FMT_OPCODE_SZ-1 downto 0), microcode_ctrl);
	
	-- Instantiate Register File:
	RegFile1: RegFile 
		PORT MAP(clk, if_instruction(9 downto 5), tmp_readreg1, if_instruction(4 downto 0), writedata, outA, outB, regwrite);
	
	-- Instantiate Hazard Unit:
	-- TODO
	
	tmp_readreg1 <= if_instruction(4 downto 0) WHEN reg2loc = '1' ELSE if_instruction(20 downto 16);
END ARCHITECTURE RTL;