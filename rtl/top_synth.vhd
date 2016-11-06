LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY top_synth IS 
	PORT(
		CLK   : IN  std_logic;
		KEY3  : IN  std_logic;
		DS_DP : OUT std_logic;
		DS_G  : OUT std_logic;
		DS_C  : OUT std_logic;
		DS_D  : OUT std_logic
	);
END top_synth;

ARCHITECTURE RTL OF top_synth IS
	signal dbus  : std_logic_vector(3 downto 0);
	signal reset : std_logic := '0';
	signal init  : std_logic := '0';
	signal init2 : std_logic := '0';
BEGIN
	DS_DP <= not dbus(0);
	DS_G  <= not dbus(1);
	DS_C  <= not dbus(2);
	DS_D  <= not dbus(3);

	-- Declare FISC Core: --
	--FISC_CORE: FISC PORT MAP(clk, NOT KEY3, dbus);
	
	process(CLK)
	begin
		if CLK'event AND CLK = '1' then
			if reset = '0' then
				reset <= '1';
				init  <= '1';
			end if;
			
			if init2 = '1' then
				reset <= '0';
				init2 <= '1';
			else
				init2 <= init;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;