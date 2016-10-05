LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC.all;

ENTITY Microcode IS
	PORT(
		clk : in std_logic; -- Clock signal
		sos : in std_logic; -- Start of segment flag (triggers on rising edge)
		microcode_opcode : in std_logic_vector(R_FMT_OPCODE_SZ-1 downto 0); -- Microcode's Opcode input to the FSM
		microcode_ctrl   : out std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) -- Result of indexing Microcode's memory with the opcode input
	);
END Microcode;

ARCHITECTURE RTL OF Microcode IS
BEGIN

END ARCHITECTURE RTL;