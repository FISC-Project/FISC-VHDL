LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage2_Decode IS
	PORT(
		clk                : in  std_logic;
		sos                : in  std_logic;
		microcode_ctrl     : out std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0);
		if_instruction     : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		writedata          : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
		reg2loc            : in  std_logic;
		regwrite           : in  std_logic;
		outA               : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		outB               : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		current_pc         : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		new_pc             : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		sign_ext           : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		pc_src             : out std_logic
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS
	COMPONENT RegFile
		PORT(
			readreg1  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			readreg2  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writereg  : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writedata : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outA      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outB      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			regwr     : in  std_logic
		);
	END COMPONENT;
	
	signal microcode_ctrl_reg : std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
	signal branch_flag        : std_logic := '0'; -- Control (comes straight from Microcode Unit)
	signal reg1_zero_flag     : std_logic := '0';
	signal reg2_zero_flag     : std_logic := '0';
	signal sign_ext_reg       : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal tmp_readreg1       : std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
	signal outA_reg           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal outB_reg           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
BEGIN
	-- Instantiate Microcode Unit:
	Microcode1: Microcode 
		PORT MAP(clk, sos, if_instruction(31 downto 21), microcode_ctrl_reg);
	
	-- Instantiate Register File:
	RegFile1: RegFile 
		PORT MAP(if_instruction(9 downto 5), tmp_readreg1, if_instruction(4 downto 0), writedata, outA_reg, outB_reg, regwrite);
	
	-- Instantiate Hazard Unit:
	-- TODO
	
	microcode_ctrl <= microcode_ctrl_reg;
	pc_src         <= (branch_flag and reg1_zero_flag);
	outA           <= outA_reg;
	outB           <= outB_reg;
	reg1_zero_flag <= '1' WHEN outA_reg = (outA_reg'range => '0') ELSE '0';
	reg2_zero_flag <= '1' WHEN outB_reg = (outB_reg'range => '0') ELSE '0';
	sign_ext_reg   <= (51 downto 0 => '0') & if_instruction(21 downto 10) WHEN microcode_ctrl_reg(12 downto 10)    = "000"  -- Sign extend from ALU_immediate
					ELSE (54 downto 0 => '0') & if_instruction(20 downto 12) WHEN microcode_ctrl_reg(12 downto 10) = "001"  -- Sign extend from DT_address
					ELSE (37 downto 0 => '0') & if_instruction(25 downto 0) WHEN microcode_ctrl_reg(12 downto 10)  = "010"  -- Sign extend from BR_Address
					ELSE (44 downto 0 => '0') & if_instruction(23 downto 5) WHEN microcode_ctrl_reg(12 downto 10)  = "011"  -- Sign extend from COND BR_Address
					ELSE (47 downto 0 => '0') & if_instruction(20 downto 5) WHEN microcode_ctrl_reg(12 downto 10)  = "100"; -- Sign extend from COND BR_Address
	sign_ext       <= sign_ext_reg;
	new_pc         <= (sign_ext_reg(FISC_INTEGER_SZ-2 downto 0) & '0') + current_pc;
	tmp_readreg1   <= if_instruction(4 downto 0) WHEN reg2loc = '1' ELSE if_instruction(20 downto 16);
END ARCHITECTURE RTL;