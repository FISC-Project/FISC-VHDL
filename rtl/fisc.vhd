LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY FISC IS
	PORT(
		clk         : in std_logic;
		restart_cpu : in std_logic
	);
END;

ARCHITECTURE RTL OF FISC IS
	-----------------------------------------------
	-- Microcode Control Bus (very important):
	signal id_microcode_ctrl : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	
	---- Stage interconnect wires declaration: ----
	-- Stage 1 - Fetch Interconnect wires --
	signal if_new_pc             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal if_reset_pc           : std_logic; -- Control (*UNUSED*)
	signal if_uncond_branch_flag : std_logic; -- Control (ID (MCU))
	signal if_instruction        : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	signal if_pc_out             : std_logic_vector(FISC_INTEGER_SZ-1     downto 0) := (others => '0');
	
	-- Stage 2 - Decode Interconnect wires --
	signal id_sos            : std_logic := '0';
	signal id_reg2loc        : std_logic; -- Control (ID (From Opcode))
	signal id_regwrite       : std_logic; -- Control (WB)
	signal id_outA           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_outB           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_sign_ext       : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_pc_src         : std_logic := '0'; -- It's a control but comes from the ID stage. It's produced by the flags: reg1_zero & branch
	
	-- Stage 3 - Execute Interconnect wires --
	signal ex_aluop      : std_logic_vector(1  downto 0); -- Control (EX)
	signal ex_result     : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_alusrc     : std_logic; -- Control (EX)
	signal ex_alu_neg    : std_logic; -- Condition code
	signal ex_alu_zero   : std_logic; -- Condition code
	signal ex_alu_overf  : std_logic; -- Condition code
	signal ex_alu_carry  : std_logic; -- Condition code
	-----------------------------------------------
	
	-- Stage 4 - Memory Access Interconnect wires --
	signal mem_data_out : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal mem_memwrite : std_logic; -- Control (MEM)
	signal mem_memread  : std_logic; -- Control (MEM)
	------------------------------------------------
	
	-- Stage 5 - Writeback Interconnect wires --
	signal wb_memtoreg       : std_logic; -- Control (WB)
	signal wb_writeback_data : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	--------------------------------------------
	
	-- Flag Outputs / Condition Codes --
	signal ex_set_flags : std_logic; -- Control (originates from ID and is used on stage EX)
	signal flag_neg     : std_logic; -- Condition code
	signal flag_zero    : std_logic; -- Condition code
	signal flag_overf   : std_logic; -- Condition code
	signal flag_carry   : std_logic; -- Condition code
	------------------------------------
BEGIN
	---- Microarchitecture Stages Declaration: ----
	-- Stage 1: Fetch
	Stage1_Fetch1   : Stage1_Fetch   PORT MAP(clk, if_new_pc, if_reset_pc, id_microcode_ctrl(0), id_pc_src, if_uncond_branch_flag, if_instruction, if_pc_out);
	-- Stage 2: Decode
	Stage2_Decode1  : Stage2_Decode  PORT MAP(clk, id_sos, id_microcode_ctrl, if_instruction, wb_writeback_data, id_reg2loc, id_regwrite, id_outA, id_outB, if_pc_out, if_new_pc, id_sign_ext, id_pc_src, if_uncond_branch_flag, flag_neg, flag_zero, flag_overf, flag_carry);
	-- Stage 3: Execute
	Stage3_Execute1 : Stage3_Execute PORT MAP(clk, id_outA, id_outB, ex_result, id_sign_ext, ex_aluop, if_instruction(31 downto 21), ex_alusrc, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry);
	-- Stage 4: Memory Access
	Stage4_Memory_Access1: Stage4_Memory_Access PORT MAP(clk, ex_result, id_outB, mem_data_out, mem_memwrite, mem_memread, if_instruction(11 downto 10));
	-- Stage 3: Writeback
	Stage5_Writeback1: Stage5_Writeback PORT MAP(clk, ex_result, mem_data_out, wb_memtoreg, wb_writeback_data);
	
	-- Flags declaration:
	Flags1: Flags PORT MAP(clk, ex_set_flags, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, flag_neg, flag_zero, flag_overf, flag_carry);
	
	-- Control Assignments: --
	if_uncond_branch_flag <= id_microcode_ctrl(3);  -- Control (ID (MCU))
	id_reg2loc            <= id_microcode_ctrl(9);  -- Control (ID)
	id_regwrite           <= id_microcode_ctrl(6);  -- Control (WB)
	ex_aluop              <= id_microcode_ctrl(2 downto 1); -- Control (EX)
	ex_alusrc             <= id_microcode_ctrl(8);  -- Control (EX)
	mem_memwrite          <= id_microcode_ctrl(4);  -- Control (MEM)
	mem_memread           <= id_microcode_ctrl(5);  -- Control (MEM)
	wb_memtoreg           <= id_microcode_ctrl(7);  -- Control (WB)
	ex_set_flags          <= id_microcode_ctrl(13); -- Control (originates from ID and is used on stage EX)
	
	if_reset_pc <= '0';
	
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