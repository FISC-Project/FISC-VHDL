LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Program_Counter IS
	PORT(
		clk      : in  std_logic;
		addr_in  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		wr       : in  std_logic;
		reset    : in  std_logic;
		addr_out : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	);
END Program_Counter;

ARCHITECTURE RTL OF Program_Counter IS
	signal latched_addr : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
BEGIN
	addr_out <= latched_addr;

	process(clk) begin
		if clk'event and clk = '1' then
			if wr = '1' then
				latched_addr <= addr_in;
			elsif reset = '1' then
				latched_addr <= (others => '0');
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;

------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage1_Fetch IS
	PORT(
		clk                : in std_logic;
		new_pc             : in std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		reset              : in std_logic;
		fsm_next           : in std_logic := '0';
		branch_flag        : in std_logic;
		uncond_branch_flag : in std_logic;
		zero_flag          : in std_logic;
		if_instruction     : out std_logic_vector(FISC_INSTRUCTION_SZ-1  downto 0);
		pc_out             : out std_logic_vector(FISC_INTEGER_SZ-1      downto 0)
	);
END Stage1_Fetch;

ARCHITECTURE RTL OF Stage1_Fetch IS
	COMPONENT Program_Counter
		PORT(
			clk      : in  std_logic;
			addr_in  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			wr       : in  std_logic;
			reset    : in  std_logic;
			addr_out : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
		);
	END COMPONENT;
	
	COMPONENT Instruction_Memory
		PORT(
			address     : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0)
		);
	END COMPONENT;

	signal instruction_reg : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	signal pc_out_reg          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0)     := (others => '0');
	signal new_pc_reg      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0)     := (others => '0');
BEGIN
	Program_Counter1: Program_Counter PORT MAP(clk, new_pc_reg, fsm_next, reset, pc_out_reg);
	Instruction_Memory1: Instruction_Memory PORT MAP(pc_out_reg, instruction_reg);	

	new_pc_reg <= new_pc WHEN ((branch_flag and zero_flag) or uncond_branch_flag) = '1' ELSE pc_out_reg + "100";
	pc_out     <= pc_out_reg; 
	
	process(clk) begin
		if clk'event and clk = '1' then
			if fsm_next = '1' then
				
			end if;
		end if;
	end process;
	
	if_instruction <= instruction_reg;
END ARCHITECTURE RTL;