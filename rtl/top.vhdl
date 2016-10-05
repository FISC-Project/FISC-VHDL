LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC.all;

ENTITY top IS END top;

ARCHITECTURE RTL OF top IS
	signal clk : std_logic := '0'; -- Simulated Clock Signal
	
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
	Stage2_Decode1 : Stage2_Decode PORT MAP(clk);
	Stage1_Fetch1  : Stage1_Fetch  PORT MAP(microcode_ctrl(0));
	
	-- Generate Clock: --
	clk <= '1' AFTER 1 fs WHEN clk = '0' ELSE '0' AFTER 1 fs WHEN clk = '1';
	
	-- Testbench Process:
	process begin
		wait for 10 fs;
		
		-- End simulation --
		wait;
	end process;
END ARCHITECTURE RTL;