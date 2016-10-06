LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage1_Fetch IS
	PORT(
		clk      : in std_logic;
		--new_pc : in std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		--reset  : in std_logic;
		fsm_next: in std_logic := '0';
		--branch_flag : in std_logic;
		--uncond_branch_flag : in std_logic;
		--zero_flag : in std_logic
		if_instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1  downto 0)
	);
END Stage1_Fetch;

ARCHITECTURE RTL OF Stage1_Fetch IS
	signal instruction_reg : std_logic_vector(FISC_INSTRUCTION_SZ-1  downto 0) := (others => '0');
BEGIN
	process(clk) begin
		if clk'event and clk = '1' then
			if fsm_next = '1' then
				instruction_reg <= instruction_reg + "1";
			end if;
		end if;
	end process;
	
	if_instruction <= instruction_reg;
END ARCHITECTURE RTL;