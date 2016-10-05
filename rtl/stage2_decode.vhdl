LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC.all;

ENTITY Stage2_Decode IS
	PORT(
		clk: in std_logic := '0'
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS
	signal sos              : std_logic := '0';
	signal microcode_opcode : std_logic_vector(R_FMT_OPCODE_SZ-1 downto 0) := (others => '0');
	signal microcode_ctrl   : std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) := (others => '0');
BEGIN
	Microcode1: Microcode PORT MAP(clk, sos, microcode_opcode, microcode_ctrl);

END ARCHITECTURE RTL;