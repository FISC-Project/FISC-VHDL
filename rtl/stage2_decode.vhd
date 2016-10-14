LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.math_real.all;
USE IEEE.std_logic_unsigned.all;
USE IEEE.numeric_std.all;
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
		pc_src             : out std_logic;
		uncond_branch_flag : in  std_logic;
		flag_neg           : in  std_logic; -- Condition code
		flag_zero          : in  std_logic; -- Condition code
		flag_overf         : in  std_logic; -- Condition code
		flag_carry         : in  std_logic  -- Condition code
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS
	COMPONENT RegFile
		PORT(
			clk          : in  std_logic;
			readreg1     : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			readreg2     : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writereg     : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
			writedata    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outA         : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			outB         : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			regwr        : in  std_logic;
			current_pc   : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			opcode       : in  std_logic_vector(10 downto 0);
			mov_quadrant : in  std_logic_vector(1 downto 0)
		);
	END COMPONENT;
	
	signal microcode_ctrl_reg : std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
	signal cbnz_branch_flag   : std_logic := '0';
	signal cbz_branch_flag    : std_logic := '0';
	signal cond_branch_flag   : std_logic := '0';
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
		PORT MAP(clk, if_instruction(9 downto 5), tmp_readreg1, if_instruction(4 downto 0), writedata, outA_reg, outB_reg, regwrite, current_pc, if_instruction(31 downto 21), if_instruction(22 downto 21));
	
	-- Instantiate Hazard Unit:
	-- TODO
	
	microcode_ctrl   <= microcode_ctrl_reg;
	cbnz_branch_flag <= '1' WHEN if_instruction(31 downto 24) = "10110101" ELSE '0';
	cbz_branch_flag  <= '1' WHEN if_instruction(31 downto 24) = "10110100" ELSE '0';
	cond_branch_flag <= '1' WHEN if_instruction(31 downto 24) = "01010100" ELSE '0';
	
	-- Branching conditions:
	pc_src <= 
		(cbz_branch_flag  and reg2_zero_flag) or                                                               -- CBZ  condition
		(cbnz_branch_flag and (not reg2_zero_flag))                                                            -- CBNZ condition
		WHEN cond_branch_flag = '0' ELSE
			flag_zero WHEN if_instruction(4 downto 0) = "00000"                                           ELSE -- BEQ  condition
			not flag_zero WHEN if_instruction(4 downto 0) = "00001"                                       ELSE -- BNE  condition
			flag_neg xor flag_overf WHEN if_instruction(4 downto 0) = "00010"                             ELSE -- BLT  condition
			not (not flag_zero and (flag_neg xnor flag_overf)) WHEN if_instruction(4 downto 0) = "00011"  ELSE -- BLE  condition
			not flag_zero and (flag_neg xnor flag_overf) WHEN if_instruction(4 downto 0) = "00100"        ELSE -- BGT  condition
			flag_neg xnor flag_overf WHEN if_instruction(4 downto 0) = "00101"                            ELSE -- BGE  condition
			not flag_carry WHEN if_instruction(4 downto 0) = "00110"                                      ELSE -- BLO  condition
			not ((not flag_zero) and flag_carry) WHEN if_instruction(4 downto 0) = "00111"                ELSE -- BLS  condition
			(not flag_zero) and flag_carry WHEN if_instruction(4 downto 0) = "01000"                      ELSE -- BHI  condition
			flag_carry WHEN if_instruction(4 downto 0) = "01001"                                          ELSE -- BHS  condition
			flag_neg WHEN if_instruction(4 downto 0) = "01010"                                            ELSE -- BMI  condition
			not flag_neg WHEN if_instruction(4 downto 0) = "01011"                                        ELSE -- BPL  condition
			flag_overf WHEN if_instruction(4 downto 0) = "01100"                                          ELSE -- BVS  condition
			not flag_overf WHEN if_instruction(4 downto 0) = "01101";                                          -- BVC  condition

	outA             <= outA_reg;
	outB             <= outB_reg;
	reg1_zero_flag   <= '1' WHEN outA_reg = (outA_reg'range => '0') ELSE '0';
	reg2_zero_flag   <= '1' WHEN outB_reg = (outB_reg'range => '0') ELSE '0';
	
	sign_ext       <= sign_ext_reg;
	sign_ext_reg   <= (51 downto 0 => '0') & if_instruction(21 downto 10) WHEN microcode_ctrl_reg(12 downto 10)    = "000"  -- Sign extend from ALU_immediate
					ELSE (57 downto 0 => '0') & if_instruction(15 downto 10) WHEN microcode_ctrl_reg(12 downto 10) = "001"  -- Sign extend from shamt
					ELSE (54 downto 0 => '0') & if_instruction(20 downto 12) WHEN microcode_ctrl_reg(12 downto 10) = "010"  -- Sign extend from DT_address
					ELSE (37 downto 0 => '0') & if_instruction(25 downto 0) WHEN microcode_ctrl_reg(12 downto 10)  = "011"  -- Sign extend from BR_Address
					ELSE (44 downto 0 => '0') & if_instruction(23 downto 5) WHEN microcode_ctrl_reg(12 downto 10)  = "100"  -- Sign extend from COND BR_Address
					ELSE (47 downto 0 => '0') & if_instruction(20 downto 5) WHEN microcode_ctrl_reg(12 downto 10)  = "101"; -- Sign extend from MOV_immediate
	
	-- Absolute OR PC-relative jump:
	new_pc         <= outB_reg WHEN if_instruction(31 downto 21) = "11010110000" -- BR jump
		ELSE std_logic_vector(signed(sign_ext_reg(22 downto 0) & "00") + signed(current_pc)) WHEN uncond_branch_flag = '1' -- B and BL jump
		ELSE std_logic_vector(signed(if_instruction(23 downto 5) & "00") + signed(current_pc)); -- CBNZ, CBZ and B.cond jump
		
	tmp_readreg1   <= if_instruction(4 downto 0) WHEN reg2loc = '1' ELSE if_instruction(20 downto 16);
END ARCHITECTURE RTL;