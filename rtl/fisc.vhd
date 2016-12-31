LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY FISC IS
	PORT(
		clk         : in std_logic;
		restart_cpu : in std_logic;
		pause       : in std_logic
	);
END FISC;

ARCHITECTURE RTL OF FISC IS
	signal master_clk   : std_logic := '0';
	signal clk_old_edge : std_logic := '0';

	-----------------------------------------------
	-- Microcode Control Bus (very important):
	signal id_microcode_ctrl       : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	signal id_microcode_ctrl_early : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	-----------------------------------------------
	
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
	-----------------------------------------------
	
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
	signal mem_data_out          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
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
	
	-- CPSR Wires ----------------------------------
	-- Flag Outputs / Condition Codes --
	signal flag_neg     : std_logic; -- Condition code
	signal flag_zero    : std_logic; -- Condition code
	signal flag_overf   : std_logic; -- Condition code
	signal flag_carry   : std_logic; -- Condition code
	------------------------------------
	-- Alignment Wires --
	signal ae_flag      : std_logic;
	---------------------
	-- Paging Wires --
	signal pg_flag      : std_logic;
	------------------
	-- Interrupt Enable Mask Wires --
	signal ien_flags    : std_logic_vector(1 downto 0);
	---------------------------------
	-- CPU Mode Wires --
	signal cpu_mode_flags : std_logic_vector(2 downto 0);
	--------------------
	-- CPSR Read/Write Wires --
	signal cpsr_wr      : std_logic := '0';
	signal cpsr_rd      : std_logic := '0';
	signal cpsr_wr_in   : std_logic_vector(10 downto 0) := (others => '0');
	signal cpsr_rd_out  : std_logic_vector(10 downto 0);
	signal cpsr_field   : std_logic_vector(4 downto 0) := (others => '0');
	signal cpsr_or_spsr : std_logic := '0';
	---------------------------
	------------------------------------------------

	--------------------------------------------------------------------------------------------------------------
	-- Control Wires (from Microcode Unit, can also be considered the inner pipeline layer of the decode stage)
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
		
	-- Main Memory Signals ------------
	signal accessing_main_memory : std_logic := '0'; -- Is the CPU currently accessing Main Memory?
	signal mem_en                : std_logic_vector(1 downto 0)  := "01";
	signal mem_wr                : std_logic := '0';
	signal mem_rd                : std_logic_vector(1  downto 0) := "01";
	signal mem_ready             : std_logic_vector(1  downto 0);
	signal mem_address1          : std_logic_vector(22 downto 0) := (others => '0');
	signal mem_address2          : std_logic_vector(22 downto 0) := (others => '0');
	signal mem_data_in           : std_logic_vector(63 downto 0) := (others => '0');
	signal mem_data_out1         : std_logic_vector(63 downto 0);
	signal mem_data_out2         : std_logic_vector(63 downto 0);
	signal mem_access_width      : std_logic_vector(1  downto 0) := (others => '0');
	-----------------------------------
	
	-- IO Controller Signals --
	signal io_int_en   : std_logic;
	signal io_int_id   : std_logic_vector(7 downto 0);
	signal io_int_type : std_logic_vector(1 downto 0);
	signal io_int_ack  : std_logic := '0';
	---------------------------
BEGIN
	-- Main Memory Wire Assignments:
	accessing_main_memory <= '0' WHEN mem_ready > "00" ELSE '1'; 
	mem_address1          <= if_new_pc_unpiped(mem_address1'high downto 0);
	mem_address2          <= ex_result(mem_address2'high downto 0);
	mem_data_in           <= ex_opB;
	mem_en(1)             <= idex_memread or idex_memwrite;
	mem_wr                <= idex_memwrite;
	mem_rd(1)             <= idex_memread;
	mem_access_width      <= ifidex_instruction(11 downto 10);
	
	-- Do not update any component if the pause signal is asserted or if the Main memory is being accessed
	master_clk <= clk_old_edge WHEN pause = '1' OR accessing_main_memory = '1' ELSE clk;
	
	---- Microarchitecture Stages Declaration: ----
	-- Stage 1: Fetch
	Stage1_Fetch1   : ENTITY work.Stage1_Fetch   PORT MAP(master_clk, if_new_pc, if_reset_pc, id_microcode_ctrl(0), id_pc_src, if_uncond_branch_flag, mem_data_out1(31 downto 0), if_instruction, if_new_pc_unpiped, if_pc_out, if_flush, if_freeze);
	-- Stage 2: Decode
	Stage2_Decode1  : ENTITY work.Stage2_Decode  PORT MAP(master_clk, id_sos, id_microcode_ctrl, id_microcode_ctrl_early, if_instruction, wb_writeback_data, idexmem_regwrite, id_outA, id_outB, ifidexmem_instruction(4 downto 0), if_pc_out, ifidexmem_pc_out, if_new_pc, id_sign_ext, id_pc_src, if_uncond_branch_flag, flag_neg, flag_zero, flag_overf, flag_carry, ifidexmem_instruction, ex_result_early, wb_writeback_data, idexmem_regwrite, ifid_pc_out, ifid_instruction, id_flush, id_freeze);
	-- Stage 3: Execute
	Stage3_Execute1 : ENTITY work.Stage3_Execute PORT MAP(master_clk, ex_srcA, ex_srcB, id_sign_ext, ex_result, ex_result_early, aluop, ifid_instruction(31 downto 21), alusrc, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, ifid_instruction, ifidex_instruction, ifid_pc_out, ifidex_pc_out, ex_opB, memwrite, memread, regwrite, memtoreg, set_flags, idex_memwrite, idex_memread, idex_regwrite, idex_memtoreg, idex_set_flags, ex_flush, ex_freeze);
	-- Stage 4: Memory Access
	Stage4_Memory_Access1 : ENTITY work.Stage4_Memory_Access PORT MAP(master_clk, ex_result, mem_data_out2, mem_data_out, mem_address, ifidex_instruction, ifidexmem_instruction, ifidex_pc_out, ifidexmem_pc_out, idex_regwrite, idex_memtoreg, idexmem_regwrite, idexmem_memtoreg, mem_flush, mem_freeze);
	-- Stage 5: Writeback
	Stage5_Writeback1 : ENTITY work.Stage5_Writeback PORT MAP(master_clk, mem_address, mem_data_out, idexmem_memtoreg, wb_writeback_data);
	
	-- Declare Main Memory: --
	Main_Memory : ENTITY work.Memory PORT MAP(
		clk, mem_en, mem_wr, mem_rd, mem_ready, 
		mem_address1, mem_address2, mem_data_in, mem_data_out1, mem_data_out2, mem_access_width
	);
	
	-- Declare IO Controller:
	IO_Controller1: ENTITY work.IO_Controller PORT MAP(
		clk, io_int_en, io_int_id, io_int_type, io_int_ack
	);
	
	-- ALU Flags, Exception and Interrupts Flags (CPSR) declaration:
	CPSR1: ENTITY work.CPSR PORT MAP(
		master_clk, idex_set_flags, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, flag_neg, flag_zero, flag_overf, flag_carry,
		ae_flag, pg_flag, ien_flags, cpu_mode_flags,
		cpsr_wr, cpsr_rd, cpsr_wr_in, cpsr_rd_out, cpsr_field, cpsr_or_spsr
	);
	
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
		'1' WHEN (restart_cpu = '1' OR (memread = '1' AND ((ifid_instruction(4 downto 0) = if_instruction(9 downto 5)) OR ifid_instruction(4 downto 0) = if_instruction(20 downto 16))))
		ELSE '0';
	if_flush <= id_flush;
	
	if_uncond_branch_flag <= id_microcode_ctrl_early(3); -- Control (ID (MCU *UNPIPELINED*))	
	if_reset_pc <= restart_cpu;
	
	-- Control Signals Assignment: --
	aluop     <= id_microcode_ctrl(2 downto 1); -- Control (EX)
	memwrite  <= id_microcode_ctrl(4);          -- Control (MEM)
	memread   <= id_microcode_ctrl(5);          -- Control (MEM)
	regwrite  <= id_microcode_ctrl(6);          -- Control (WB)
	memtoreg  <= id_microcode_ctrl(7);          -- Control (WB)
	alusrc    <= id_microcode_ctrl(8);          -- Control (EX)
	set_flags <= id_microcode_ctrl(13);         -- Control (originates from ID and is used on stage EX)
		
	---------------------------
	------- Behaviour: --------
	---------------------------
	main_proc: process(clk, restart_cpu, id_microcode_ctrl, pause, accessing_main_memory) begin
		if restart_cpu = '1' then
			id_sos <= '1';
		else
			if clk = '0' then
				if pause = '0' AND accessing_main_memory = '0' then
					clk_old_edge <= clk;
				end if;
				if id_microcode_ctrl(0) = '1' then
					id_sos <= '1';
				else
					id_sos <= '0';
				end if;
			else
				if pause = '0' AND accessing_main_memory = '0'then
					clk_old_edge <= clk;
				end if;
				id_sos <= '0';
			end if;
		end if;
	end process;
	--------------------------
END ARCHITECTURE RTL;