LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC.all;

ENTITY Stage1_Fetch IS
	PORT(
		--new_pc : in std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		--reset  : in std_logic;
		fsm_next: in std_logic := '0'
		--branch_flag : in std_logic;
		--uncond_branch_flag : in std_logic;
		--zero_flag : in std_logic
	);
END Stage1_Fetch;

ARCHITECTURE RTL OF Stage1_Fetch IS
BEGIN


END ARCHITECTURE RTL;