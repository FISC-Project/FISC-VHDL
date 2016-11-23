LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY top IS END top;

ARCHITECTURE RTL OF top IS
	-- CPU Control Wires:
	signal clk               : std_logic := '0'; -- Simulated Clock Signal
	signal restart_system    : std_logic := '0'; -- Simulated Restart CPU Flags
	signal pause_cpu         : std_logic := '1'; -- Pause/Freeze the CPU completely
	signal dbus              : std_logic_vector(3 downto 0); -- TODO: TEMPORARY. REMOVE LATER
	signal system_startup    : std_logic := '0'; -- Signals when the system has completely initialized before the CPU is allowed to execute
	
	-- SDRAM Controller Wires:
	signal sdram_cmd_ready   : std_logic := '0';
	signal sdram_cmd_en      : std_logic := '0';
	signal sdram_cmd_wr      : std_logic := '0';
	signal sdram_cmd_address : std_logic_vector(22 downto 0) := (others => '0');
	signal sdram_cmd_byte_en : std_logic_vector(3  downto 0) := (others => '0');
	signal sdram_cmd_data_in : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_data_out    : std_logic_vector(31 downto 0) := (others => '0');
	signal sdram_data_ready  : std_logic := '0';
	
	-- SDRAM Wires:
	signal sdram_cke         : std_logic;
	signal sdram_clk         : std_logic;
	signal sdram_cs_n        : std_logic;
	signal sdram_we_n        : std_logic;
	signal sdram_cas_n       : std_logic;
	signal sdram_ras_n       : std_logic;
	signal sdram_an          : std_logic_vector(12 downto 0);
	signal sdram_ban         : std_logic_vector(1  downto 0);
	signal sdram_dqmhl       : std_logic_vector(1  downto 0);
	signal sdram_dqn         : std_logic_vector(15 downto 0);
BEGIN
	-- Declare FISC Core: --
	FISC_CORE: ENTITY work.FISC PORT MAP(
		clk, restart_system, pause_cpu, dbus,
		sdram_cmd_ready, sdram_cmd_en, sdram_cmd_wr,
		sdram_cmd_address, sdram_cmd_byte_en,
		sdram_cmd_data_in, sdram_data_out,
		sdram_data_ready 
	);
	
	-- Declare DRAM Controller (simulated): --
	DRAM_Controller_Sim1 : ENTITY work.DRAM_Controller_Sim 
		PORT MAP(
			clk, restart_system, sdram_cmd_en, 
			sdram_cmd_wr, sdram_cmd_ready, sdram_cmd_address,
			sdram_cmd_data_in, sdram_data_ready, sdram_data_out
		);
	
	-- Generate Clock: --
	clk <= '1' AFTER 1 fs WHEN clk = '0' ELSE '0' AFTER 1 fs WHEN clk = '1';
	
	-- Initialization Process:
	init_proc: process(clk) begin
		if clk'event and clk = '1' then
			if sdram_cmd_ready = '1' then
				system_startup <= '1'; -- The System's devices are now initialized! (TODO: In the future, when there's multiple devices, we must change this logic)
			end if;
		end if;
	end process;
	
	-- Main Process:
	main_proc: process begin
		----------------------------------------
		-- Initialize All Systems here first: --
		----------------------------------------
		pause_cpu      <= '1'; -- Do not let the CPU execute while the external systems are being initialized
		restart_system <= '1'; wait for 2 fs; restart_system <= '0'; -- Restart every device on the FPGA Board with a signal pulse
			
		-- Wait for the device with the longest startup time to finish its initialization:
		wait until system_startup = '1';
		
		-------------------------
		-- !! Kickstart CPU !! --
		-------------------------
		pause_cpu <= '0'; -- Go!

		-- Now let the CPU run
		wait; -- End simulation --
	end process;
END ARCHITECTURE RTL;