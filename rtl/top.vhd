LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY top IS END top;

ARCHITECTURE RTL OF top IS
	signal clk : std_logic := '0'; -- Simulated Clock Signal
	signal restart_cpu: std_logic := '0'; -- Simulated Restart CPU Flags
BEGIN
	-- Declare FISC Core: --
	FISC_CORE: FISC PORT MAP(clk, restart_cpu);
	
	-- Declare DRAM: --
	-- TODO --

	-- Generate Clock: --
	clk <= '1' AFTER 1 fs WHEN clk = '0' ELSE '0' AFTER 1 fs WHEN clk = '1';
	
	-- Testbench Process:
	process begin
		wait for 2 fs;
		restart_cpu <= '1';
		wait for 1 fs;
		restart_cpu <= '0';
		wait for 7 fs;
		-- End simulation --
		wait;
	end process;
END ARCHITECTURE RTL;