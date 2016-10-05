LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY Stage2_Decode IS
	PORT(
		clk : in std_logic := '0';
		sos : in std_logic := '0';
		microcode_ctrl : out std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) := (others => '0');
		if_instruction : in std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0')
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS BEGIN
	Microcode1: Microcode 
		PORT MAP(clk, sos, if_instruction(FISC_INSTRUCTION_SZ-1 downto (FISC_INSTRUCTION_SZ - R_FMT_OPCODE_SZ)), microcode_ctrl);

END ARCHITECTURE RTL;