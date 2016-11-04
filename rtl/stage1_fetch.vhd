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
		clk                : in  std_logic;
		new_pc             : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		reset              : in  std_logic;
		fsm_next           : in  std_logic;
		pc_src             : in  std_logic;
		uncond_branch_flag : in  std_logic;
		l1ic_instruction   : in std_logic_vector(FISC_INSTRUCTION_SZ-1  downto 0);
		if_instruction     : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		new_pc_unpiped     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		pc_out             : out std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
		-- Pipeline flush/freeze:
		if_flush           : in  std_logic;
		if_freeze          : in  std_logic
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
	
	signal new_pc_reg      : std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
	signal pc_wr_reg       : std_logic := '0';
	-- Inner Pipeline Layer:
	signal pc_out_reg      : std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
	signal pc_out_reg_cpy  : std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0'); -- Just a copy, not pipelined
BEGIN
	Program_Counter1: Program_Counter PORT MAP(clk, new_pc_reg, fsm_next, reset, pc_out_reg);
	
	-- If this stage is stalling/freezing, we may not write the new PC value
	pc_wr_reg <= '1' WHEN fsm_next = '1' AND (if_freeze = '0' OR if_flush = '0');

	-- NOTE: There are two ways to branch unconditionally. Either use the microcode unit for ANY instruction, or use the B/BR instructions with no other side effects
	new_pc_reg <=
		new_pc WHEN (pc_src or uncond_branch_flag) = '1'
		ELSE pc_out_reg + "100";
	
	new_pc_unpiped <= pc_out_reg;
	
	pc_out_reg_cpy <= pc_out_reg WHEN pc_src = '0' ELSE new_pc_reg;
	
	process(clk) begin
		if clk'event and clk = '0' then
			if if_flush = '0' and if_freeze = '0' and reset = '0' then -- In the fetch stage, freezing is the same as flushing/stalling
				-- Move the Fetch Stage's Inner Pipeline Forward:
				if_instruction <= l1ic_instruction;
				pc_out <= pc_out_reg_cpy;
			elsif reset = '1' then
				if_instruction <= (others => '0');
				pc_out <= (others => '0');
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;