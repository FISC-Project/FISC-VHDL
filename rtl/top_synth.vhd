LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY top_synth IS 
	PORT(
		CLK  : IN std_logic;
		KEY3 : IN std_logic
	);
END top_synth;

ARCHITECTURE RTL OF top_synth IS

BEGIN
	-- Declare FISC Core: --
	FISC1: FISC PORT MAP(clk, NOT KEY3);
	
	process(CLK)
	begin
		
	end process;
END ARCHITECTURE RTL;