LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC.all;

ENTITY top_synth IS 
	PORT(
		CLK : IN std_logic
	);
END top_synth;

ARCHITECTURE RTL OF top_synth IS
	-----------------------------------------------
	---- Stage interconnect wires declaration: ----
	-- Stage 1 - Fetch Interconnect wires --
	
	-- Stage 2 - Decode Interconnect wires --
	signal microcode_opcode : std_logic_vector(R_FMT_OPCODE_SZ-1 downto 0) := (others => '0');
	signal microcode_ctrl   : std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) := (others => '0');
	-----------------------------------------------
BEGIN
---- Microarchitecture Stages Declaration: ----
	-- Stage 1: Fetch
	-- Stage 2: Decode
	Stage2_Decode1 : Stage2_Decode PORT MAP(CLK);
	Stage1_Fetch1  : Stage1_Fetch  PORT MAP(microcode_ctrl(0));
	
	process(CLK)
	begin
		
	end process;
END ARCHITECTURE RTL;