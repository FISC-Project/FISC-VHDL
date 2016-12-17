LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY top IS END top;

ARCHITECTURE RTL OF top IS
	-- CPU Control Wires:
	signal clk            : std_logic := '0'; -- Simulated Clock Signal
	signal restart_system : std_logic := '0'; -- Simulated Restart CPU Flags
	signal pause_cpu      : std_logic := '1'; -- Pause/Freeze the CPU completely
	signal system_startup : std_logic := '0'; -- Signals when the system has completely initialized before the CPU is allowed to execute

BEGIN
	-- Declare FISC Core: --
	FISC_CORE: ENTITY work.FISC PORT MAP(clk, restart_system, pause_cpu);
	
	-- Generate Clock: --
	clk <= '1' AFTER 1 ns WHEN clk = '0' ELSE '0' AFTER 1 ns WHEN clk = '1';
		
	-- Main Process:
	main_proc: process begin
		-------------------------
		-- !! Kickstart CPU !! --
		-------------------------
		pause_cpu <= '0'; -- Go!

		-- Now let the CPU run
		wait; -- End simulation --
	end process;
END ARCHITECTURE RTL;