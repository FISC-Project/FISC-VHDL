LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY FISC IS
	PORT(
		clk         : in std_logic;
		restart_cpu : in std_logic
	);
END FISC;

ARCHITECTURE RTL OF FISC IS
	-----------------------------------------------
	-- Microcode Control Bus (very important):
	signal id_microcode_ctrl : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	signal id_microcode_ctrl_early : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	
	---- Stage interconnect wires declaration: ----
	-- Stage 1 - Fetch Interconnect wires --
	signal if_new_pc             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal if_reset_pc           : std_logic; -- Control (*UNUSED* (for now...))
	signal if_uncond_branch_flag : std_logic; -- Control (ID (MCU))
	signal if_instruction        : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	signal if_new_pc_unpiped     : std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
	signal if_pc_out             : std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
	signal if_flush              : std_logic := '0';
	signal if_freeze             : std_logic := '0';
	----------------------------------------
	
	-- Stage 2 - Decode Interconnect wires --
	signal id_sos           : std_logic := '0';
	signal id_outA          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_outB          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_sign_ext      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_pc_src        : std_logic := '0'; -- It's a control but comes from the ID stage. It's produced by the flags: reg1_zero & branch
	-- Pipeline output:
	signal ifid_pc_out      : std_logic_vector(FISC_INTEGER_SZ-1     downto 0);
	signal ifid_instruction : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
	-- Pipeline flush/freeze:
	signal id_flush         : std_logic := '0';
	signal id_freeze        : std_logic := '0';
	-----------------------------------------
	
	-- Stage 3 - Execute Interconnect wires --
	signal ex_srcA         : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_srcB         : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_result       : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_result_early : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_alu_neg      : std_logic; -- Condition code
	signal ex_alu_zero     : std_logic; -- Condition code
	signal ex_alu_overf    : std_logic; -- Condition code
	signal ex_alu_carry    : std_logic; -- Condition code
	-- Pipeline output:
	signal ifidex_instruction : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
	signal ex_opB             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ifidex_pc_out      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	-- Pipeline controls:
	signal idex_memwrite  : std_logic;
	signal idex_memread   : std_logic;
	signal idex_regwrite  : std_logic;
	signal idex_memtoreg  : std_logic;
	signal idex_set_flags : std_logic;
	-- Pipeline flush/freeze:
	signal ex_flush       : std_logic := '0';
	signal ex_freeze      : std_logic := '0';
	-----------------------------------------------
	
	-- Stage 4 - Memory Access Interconnect wires --
	-- Pipeline output:
	signal mem_data_out : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal mem_address           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ifidexmem_instruction : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
	signal ifidexmem_pc_out      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	-- Pipeline controls:
	signal idexmem_regwrite      : std_logic;
	signal idexmem_memtoreg      : std_logic;
	-- Pipeline flush/freeze:
	signal mem_flush             : std_logic := '0';
	signal mem_freeze            : std_logic := '0';
	------------------------------------------------
	
	-- Stage 5 - Writeback Interconnect wires --
	signal wb_writeback_data : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	--------------------------------------------
	
	-- Flag Outputs / Condition Codes --
	signal flag_neg     : std_logic; -- Condition code
	signal flag_zero    : std_logic; -- Condition code
	signal flag_overf   : std_logic; -- Condition code
	signal flag_carry   : std_logic; -- Condition code
	------------------------------------
	
	--------------------------------------------------------------------------------------------------------------
	-- Control Wires (from Microcode Unit, can also be considered the inner pipeline layer of the decode stage) --
	signal aluop     : std_logic_vector(1 downto 0) := "00";
	signal memwrite  : std_logic := '0';
	signal memread   : std_logic := '0';
	signal regwrite  : std_logic := '0';
	signal memtoreg  : std_logic := '0';
	signal alusrc    : std_logic := '0';
	signal set_flags : std_logic := '0';
	--------------------------------------------------------------------------------------------------------------
	
	-- Forwarding Control Signals --------------
	signal forwA : std_logic_vector(1 downto 0);
	signal forwB : std_logic_vector(1 downto 0);
	--------------------------------------------
	
	-- L1 Instruction Cache Internal Signals --
	signal l1_ic_request_data : std_logic := '1';
	signal l1_ic_hit          : std_logic;
	signal l1_ic_miss         : std_logic;
	signal l1_ic_data         : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
	signal l1_ic_data_src     : std_logic;
	-------------------------------------------
BEGIN
	---- Microarchitecture Stages Declaration: ----
	-- Stage 1: Fetch
	Stage1_Fetch1   : Stage1_Fetch   PORT MAP(clk, if_new_pc, if_reset_pc, id_microcode_ctrl(0), id_pc_src, if_uncond_branch_flag, l1_ic_data, if_instruction, if_new_pc_unpiped, if_pc_out, if_flush, if_freeze);
	-- Stage 2: Decode
	Stage2_Decode1  : Stage2_Decode  PORT MAP(clk, id_sos, id_microcode_ctrl, id_microcode_ctrl_early, if_instruction, wb_writeback_data, idexmem_regwrite, id_outA, id_outB, ifidexmem_instruction(4 downto 0), if_pc_out, ifidexmem_pc_out, if_new_pc, id_sign_ext, id_pc_src, if_uncond_branch_flag, flag_neg, flag_zero, flag_overf, flag_carry, ifidexmem_instruction, ex_result_early, wb_writeback_data, idexmem_regwrite, ifid_pc_out, ifid_instruction, id_flush, id_freeze);
	-- Stage 3: Execute
	Stage3_Execute1 : Stage3_Execute PORT MAP(clk, ex_srcA, ex_srcB, id_sign_ext, ex_result, ex_result_early, aluop, ifid_instruction(31 downto 21), alusrc, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, ifid_instruction, ifidex_instruction, ifid_pc_out, ifidex_pc_out, ex_opB, memwrite, memread, regwrite, memtoreg, set_flags, idex_memwrite, idex_memread, idex_regwrite, idex_memtoreg, idex_set_flags, ex_flush, ex_freeze);
	-- Stage 4: Memory Access
	Stage4_Memory_Access1: Stage4_Memory_Access PORT MAP(clk, ex_result, ex_opB, mem_data_out, idex_memwrite, idex_memread, ifidex_instruction(11 downto 10), mem_address, ifidex_instruction, ifidexmem_instruction, ifidex_pc_out, ifidexmem_pc_out, idex_regwrite, idex_memtoreg, idexmem_regwrite, idexmem_memtoreg, mem_flush, mem_freeze);
	-- Stage 3: Writeback
	Stage5_Writeback1: Stage5_Writeback PORT MAP(clk, mem_address, mem_data_out, idexmem_memtoreg, wb_writeback_data);
	
	-- Flags declaration:
	Flags1: Flags PORT MAP(clk, idex_set_flags, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, flag_neg, flag_zero, flag_overf, flag_carry);
	
	-- Exception Flags declaration:
	-- TODO
		
	-- Forwarding logic declaration:
	forwA <= 
		"10" WHEN (idex_regwrite = '1' AND ifidex_instruction(4 downto 0) /= "11111" AND ifidex_instruction(4 downto 0) = ifid_instruction(9 downto 5)) ELSE -- Forward EX/MEM ALU Result
		"01" WHEN -- Forward MEM/WB Writeback result
			(
				idexmem_regwrite = '1' AND ifidexmem_instruction(4 downto 0) /= "11111" 
				AND NOT(
					idex_regwrite = '1' 
					AND (ifidex_instruction(4 downto 0) /= "11111") 
					AND (ifidex_instruction(4 downto 0) /= ifid_instruction(9 downto 5))
				)
				AND (ifidexmem_instruction(4 downto 0) = ifid_instruction(9 downto 5))
			)
		ELSE "00"; -- Don't forward anything, just select the normal operand from the register through the pipe ID/EX
		
	forwB <= 
		"10" WHEN (idex_regwrite = '1' AND ifidex_instruction(4 downto 0) /= "11111" AND ifidex_instruction(4 downto 0) = ifid_instruction(20 downto 16)) ELSE -- Forward EX/MEM ALU Result
		"01" WHEN -- Forward MEM/WB Writeback result
			(
				idexmem_regwrite = '1' AND ifidexmem_instruction(4 downto 0) /= "11111" 
				AND 
					(NOT(
						idex_regwrite = '1' 
						AND (ifidex_instruction(4 downto 0) /= "11111") 
						AND (ifidex_instruction(4 downto 0) /= ifid_instruction(20 downto 16))
					)
				OR
					(NOT(
						idex_regwrite = '1' 
						AND (ifidex_instruction(4 downto 0) /= "11111") 
						AND (ifidex_instruction(4 downto 0) /= ifid_instruction(4 downto 0))
					)))
				AND ((ifidexmem_instruction(4 downto 0) = ifid_instruction(20 downto 16)) OR (ifidexmem_instruction(4 downto 0) = ifid_instruction(4 downto 0)))
			)
		ELSE "00"; -- Don't forward anything, just select the normal operand from the register through the pipe ID/EX
	
	ex_srcA <= ex_result WHEN forwA = "10" ELSE wb_writeback_data WHEN forwA = "01" ELSE id_outA WHEN forwA = "00";
	ex_srcB <= ex_result WHEN forwB = "10" ELSE wb_writeback_data WHEN forwB = "01" ELSE id_outB WHEN forwB = "00";
	
	-- Hazard Detection logic declaration:
	-- Stall Decode Stage due to Loads followed by an R-Type instruction:
	id_flush <= 
		'1' WHEN (memread = '1' AND ((ifid_instruction(4 downto 0) = if_instruction(9 downto 5)) OR ifid_instruction(4 downto 0) = if_instruction(20 downto 16)))
		ELSE '0';
	if_flush <= id_flush;
	
	if_uncond_branch_flag <= id_microcode_ctrl_early(3); -- Control (ID (MCU *UNPIPELINED*))	
	if_reset_pc <= '0'; -- TODO: Use this signal
	
	-- Control Signals Assignment: --
	aluop     <= id_microcode_ctrl(2 downto 1); -- Control (EX)
	memwrite  <= id_microcode_ctrl(4);  -- Control (MEM)
	memread   <= id_microcode_ctrl(5);  -- Control (MEM)
	regwrite  <= id_microcode_ctrl(6);  -- Control (WB)
	memtoreg  <= id_microcode_ctrl(7);  -- Control (WB)
	alusrc    <= id_microcode_ctrl(8);  -- Control (EX)
	set_flags <= id_microcode_ctrl(13); -- Control (originates from ID and is used on stage EX)
	
	-- L1 Instruction Cache Declaration:
	L1_ICache1: ENTITY work.L1_ICache PORT MAP(clk, l1_ic_request_data, if_new_pc_unpiped, l1_ic_hit, l1_ic_miss, l1_ic_data, l1_ic_data_src);
	
	--------------------------
	------- Behaviour: -------
	--------------------------
	process(clk, restart_cpu, id_microcode_ctrl) begin
		if restart_cpu = '1' then
			id_sos <= '1';
		else
			if clk = '0' then 		
				if id_microcode_ctrl(0) = '1' then
					id_sos <= '1';
				else
					id_sos <= '0';
				end if;
			else
				id_sos <= '0';
			end if;
		end if;
	end process;
	--------------------------
END ARCHITECTURE RTL;