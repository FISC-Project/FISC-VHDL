LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.math_real.all;
USE IEEE.std_logic_unsigned.all;
USE IEEE.numeric_std.all;
USE work.FISC_DEFINES.all;

ENTITY Stage2_Decode IS
	PORT(
		clk                   : in  std_logic;
		sos                   : in  std_logic;
		microcode_ctrl        : out std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
		microcode_ctrl_early  : out std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
		id_wr_dat_early       : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		id_wr_addr_early      : in  std_logic_vector(4 downto 0);
		regwrite_early        : in  std_logic;
		if_instruction        : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		writedata             : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
		regwrite              : in  std_logic;
		outA                  : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		outB                  : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		outB_unpiped          : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		writereg_addr         : in  std_logic_vector(4 downto 0);
		current_pc            : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		ifidexmem_pc_out      : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		new_pc                : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		sign_ext              : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		pc_src                : out std_logic;
		uncond_branch_flag    : in  std_logic;
		flag_neg              : in  std_logic; -- Condition code
		flag_zero             : in  std_logic; -- Condition code
		flag_overf            : in  std_logic; -- Condition code
		flag_carry            : in  std_logic; -- Condition code
		ifidexmem_instruction : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0); -- This signal is used only for MOVZ and MOVK
		ex_result_forw        : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0); -- Forward value from Execute stage
		mem_wb_forw           : in  std_logic_vector(FISC_INTEGER_SZ-1     downto 0); -- Forward value from Writeback stage
		idexmem_regwrite      : in  std_logic;
		ivp_out               : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		evp_out               : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		-- Pipeline (data) outputs:
		ifid_pc_out           : out std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
		ifid_instruction      : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		-- Pipeline flush/freeze:
		id_flush              : in  std_logic;
		id_freeze             : in  std_logic
	);
END Stage2_Decode;

ARCHITECTURE RTL OF Stage2_Decode IS
	signal regwrite_reg         : std_logic := '0';
	signal writedata_reg        : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal writereg_addr_mux    : std_logic_vector(4 downto 0) := (others => '0');
	
	signal ifid_instruction_reg : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	signal microcode_ctrl_reg   : std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
	signal microcode_ctrl_copy  : std_logic_vector(MICROCODE_CTRL_WIDTH  downto 0) := (others => '0');
	
	signal reg2loc              : std_logic := '0';
	signal cbnz_branch_flag     : std_logic := '0';
	signal cbz_branch_flag      : std_logic := '0';
	signal cond_branch_flag     : std_logic := '0';
	signal reg1_zero_flag       : std_logic := '0';
	signal reg2_zero_flag       : std_logic := '0';
	signal tmp_readreg1         : std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
	signal decode_forw          : std_logic_vector(1 downto 0) := "00";
	signal ifid_pc_out_reg      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	-- Inner Pipeline Layer:
	-- Data:
	signal outA_reg             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal outB_reg             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal sign_ext_reg         : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal sign_ext_copy        : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Not pipelined!
BEGIN
	-- Instantiate Microcode Unit:
	Microcode1: ENTITY work.Microcode PORT MAP(clk, sos, if_instruction(31 downto 21), microcode_ctrl_reg);
	
	-- Instantiate Register File:
	RegFile1: ENTITY work.RegFile PORT MAP(
		clk,
		if_instruction(9 downto 5),
		tmp_readreg1,
		writereg_addr_mux,
		writedata_reg,
		outA_reg,
		outB_reg,
		regwrite_reg,
		ifidexmem_pc_out,
		ifid_instruction_reg(31 downto 21),
		ifidexmem_instruction(31 downto 21),
		ifidexmem_instruction(22 downto 21),
		ivp_out,
		evp_out
	);
	
	-- Register write logic:
	regwrite_reg      <= regwrite OR regwrite_early;
	writedata_reg     <= id_wr_dat_early  WHEN regwrite_early = '1' ELSE writedata     WHEN regwrite = '1' ELSE (others => '0');
	writereg_addr_mux <= id_wr_addr_early WHEN regwrite_early = '1' ELSE writereg_addr WHEN regwrite = '1' ELSE (others => '0');
	
	microcode_ctrl_early <= microcode_ctrl_reg;
	
	ifid_instruction <= ifid_instruction_reg;
	
	reg2loc          <= microcode_ctrl_reg(9);
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

	reg1_zero_flag   <= '1' WHEN outA_reg = (outA_reg'range => '0') ELSE '0';
	reg2_zero_flag   <= '1' WHEN outB_reg = (outB_reg'range => '0') ELSE '0';
	
	ifid_pc_out      <= ifid_pc_out_reg;
	
	sign_ext_reg     <=  (51 downto 0 => '0') & if_instruction(21 downto 10) WHEN microcode_ctrl_reg(12 downto 10) = "000"  -- Sign extend from ALU_immediate
					ELSE (57 downto 0 => '0') & if_instruction(15 downto 10) WHEN microcode_ctrl_reg(12 downto 10) = "001"  -- Sign extend from shamt
					ELSE (54 downto 0 => '0') & if_instruction(20 downto 12) WHEN microcode_ctrl_reg(12 downto 10) = "010"  -- Sign extend from DT_address
					ELSE (37 downto 0 => '0') & if_instruction(25 downto 0)  WHEN microcode_ctrl_reg(12 downto 10) = "011"  -- Sign extend from BR_Address
					ELSE (44 downto 0 => '0') & if_instruction(23 downto 5)  WHEN microcode_ctrl_reg(12 downto 10) = "100"  -- Sign extend from COND BR_Address
					ELSE (47 downto 0 => '0') & if_instruction(20 downto 5)  WHEN microcode_ctrl_reg(12 downto 10) = "101"  -- Sign extend from MOV_immediate
					ELSE ("00" & current_pc(63 downto 2))+"1"                WHEN microcode_ctrl_reg(12 downto 10) = "110"; -- Sign extend from the Program Counter
	
	-- Forwarding Logic from Execute stage to Decode Stage:
	decode_forw <=
		     "01" WHEN microcode_ctrl_copy(6) = '1' AND ifid_instruction_reg(4 downto 0) /= "11111" AND ifid_instruction_reg(4 downto 0) = if_instruction(4 downto 0)
		ELSE "10" WHEN idexmem_regwrite = '1' AND ifidexmem_instruction(4 downto 0) /= "11111" AND ifidexmem_instruction(4 downto 0) = if_instruction(4 downto 0)
		ELSE "11" WHEN ifid_instruction_reg(31 downto 26) = "100101" 
		ELSE "00";
	
	-- Absolute 'OR' PC-relative jump:
	new_pc <= 
		outB_reg(61 downto 0) & "00" WHEN if_instruction(31 downto 21) = "11010110000" AND decode_forw = "00" -- BR jump WITHOUT forwarding
		ELSE ex_result_forw(61 downto 0) & "00" WHEN if_instruction(31 downto 21) = "11010110000" AND decode_forw = "01" -- BR jump WITH forwarding from Execute Stage
		ELSE mem_wb_forw(61 downto 0) & "00" WHEN if_instruction(31 downto 21) = "11010110000" AND decode_forw = "10" -- BR jump WITH forwarding from Writeback Stage
		ELSE sign_ext_copy(61 downto 0) & "00" WHEN if_instruction(31 downto 21) = "11010110000" AND decode_forw = "11" -- BR jump WITH forwarding from Writeback Stage
		ELSE std_logic_vector(signed(if_instruction(25 downto 0) & "00") + signed(current_pc)) WHEN uncond_branch_flag = '1' -- B and BL jump
		ELSE std_logic_vector(signed(if_instruction(23 downto 5) & "00") + signed(current_pc)); -- CBNZ, CBZ and B.cond jump
		
	tmp_readreg1 <= if_instruction(4 downto 0) WHEN reg2loc = '1' ELSE if_instruction(20 downto 16); -- Select either RD or RM fields for input readreg1 (only effective with Instr. Format R)

	outB_unpiped <= outB_reg;

	----------------
	-- Behaviour: --
	----------------
	main_proc: process(clk) begin
		if falling_edge(clk) then
			if id_freeze = '0' then
				if id_flush = '0' then
					-- Move the Decode Stage's Inner Pipeline Forward:
					ifid_pc_out_reg      <= current_pc;
					outA                 <= outA_reg;
					outB                 <= outB_reg;
					sign_ext             <= sign_ext_reg;
					sign_ext_copy        <= sign_ext_reg;
					ifid_instruction_reg <= if_instruction;
					-- Move all the control wires as well:
					microcode_ctrl       <= microcode_ctrl_reg;
					microcode_ctrl_copy  <= microcode_ctrl_reg;
				else
					-- Stall the pipeline (preserve the data, except the instruction):
					ifid_instruction_reg <= (others => '0');
					microcode_ctrl       <= (others => '0');
					microcode_ctrl_copy  <= (others => '0');
				end if;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;