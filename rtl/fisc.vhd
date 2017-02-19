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
	signal id_sos           : std_logic := '1';
	signal id_outA          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_outB          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_sign_ext      : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_wr_dat_early  : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal id_wr_addr_early : std_logic_vector(4 downto 0) := (others => '0');
	signal id_pc_src        : std_logic := '0'; -- It's a control but comes from the ID stage. It's produced by the flags: reg1_zero & branch
	signal ivp_out          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- Interrupt Vector Pointer output
	signal evp_out          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- Exception Vector Pointer output
	signal pdp_out          : std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- Page Directory Pointer output
	signal pfla_out         : std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- Page Fault Linear Address output
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
	---------------------------
	------------------------------------------------

	--------------------------------------------------------------------------------------------------------------
	-- Control Wires (from Microcode Unit, can also be considered the inner pipeline layer of the decode stage)
	signal aluop          : std_logic_vector(1 downto 0) := "00";
	signal memwrite       : std_logic := '0';
	signal memread        : std_logic := '0';
	signal regwrite       : std_logic := '0';
	signal memtoreg       : std_logic := '0';
	signal alusrc         : std_logic := '0';
	signal set_flags      : std_logic := '0';
	signal regwrite_early : std_logic := '0';
	--------------------------------------------------------------------------------------------------------------
	
	-- Forwarding Control Signals --------------
	signal forwA : std_logic_vector(1 downto 0);
	signal forwB : std_logic_vector(1 downto 0);
	--------------------------------------------
		
	-- Main Memory Signals ------------
	signal accessing_main_memory : std_logic := '0'; -- Is the CPU currently accessing Main Memory?
	signal mem_en                : std_logic_vector(1 downto 0)  := "00";
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
	signal io_int_en       : std_logic;
	signal io_int_id       : std_logic_vector(7 downto 0);
	signal io_int_id_reg   : std_logic_vector(7 downto 0);
	signal io_int_type     : std_logic_vector(1 downto 0);
	signal io_int_type_reg : std_logic_vector(1 downto 0);
	signal io_int_ack      : std_logic := '0';
	signal io_int_ack_id   : std_logic_vector(7 downto 0) := (others => '0');
	---------------------------
	
	-- MMU Signals --
	signal mmu_pfla    : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal mmu_pfla_wr : std_logic;
	-----------------
	
	-- Software Interrupt Signals --
	signal sint_id   : std_logic_vector(7 downto 0) := (others => '0');
	signal sint_type : std_logic_vector(1 downto 0) := (others => '0');
	--------------------------------
	
	-- CPU Finite State Machine --
	signal cpu_state : std_logic_vector(2 downto 0) := s_fetching;
	------------------------------
BEGIN
	-- Main Memory Wire Assignments:
	accessing_main_memory <= '0' WHEN mem_ready > "00" ELSE '1'; 
	mem_address1          <= if_new_pc_unpiped(mem_address1'high downto 0);
	mem_address2          <= ex_result(mem_address2'high downto 0);
	mem_data_in           <= ex_opB;
	mem_en(0)             <= '1' WHEN cpu_state = s_fetching or cpu_state = s_jmpint or cpu_state = s_runint or cpu_state = s_jmpex or cpu_state = s_runex ELSE '0';
	mem_en(1)             <= idex_memread or idex_memwrite;
	mem_wr                <= idex_memwrite;
	mem_rd(1)             <= idex_memread;
	mem_access_width      <= ifidex_instruction(11 downto 10);
	
	-- Do not update any component if the pause signal is asserted or if the Main memory is being accessed
	master_clk <= clk_old_edge WHEN pause = '1' OR accessing_main_memory = '1' ELSE clk;
	
	-----------------------------------------------------------------------
	-- Microarchitecture Stages Declaration: ------------------------------
	-----------------------------------------------------------------------
	
	-------------------------------------------------------------
	-- Stage 1: Fetch -------------------------------------------
	-------------------------------------------------------------
	Stage1_Fetch1 : ENTITY work.Stage1_Fetch PORT MAP(
		master_clk,
		cpu_state,
		if_new_pc,
		if_reset_pc,
		id_microcode_ctrl(0),
		id_pc_src,
		if_uncond_branch_flag,
		mem_data_out1(31 downto 0),
		if_instruction,
		if_new_pc_unpiped,
		if_pc_out,
		ivp_out,
		evp_out,
		io_int_id_reg,
		if_flush,
		if_freeze
	);
	
	-------------------------------------------------------------
	-- Stage 2: Decode ------------------------------------------
	-------------------------------------------------------------
	Stage2_Decode1 : ENTITY work.Stage2_Decode PORT MAP(
		master_clk,
		id_sos,
		id_microcode_ctrl,
		id_microcode_ctrl_early,
		id_wr_dat_early,
		id_wr_addr_early,
		regwrite_early,
		if_instruction,
		wb_writeback_data,
		idexmem_regwrite,
		id_outA,
		id_outB,
		ifidexmem_instruction(4 downto 0),
		if_pc_out,
		ifidexmem_pc_out,
		if_new_pc,
		id_sign_ext,
		id_pc_src,
		if_uncond_branch_flag,
		flag_neg,
		flag_zero,
		flag_overf,
		flag_carry,
		ifidexmem_instruction,
		ex_result_early,
		wb_writeback_data,
		idexmem_regwrite,
		ivp_out,
		evp_out,
		pdp_out,
		pfla_out,
		mmu_pfla,
		mmu_pfla_wr,
		ae_flag,
		ifid_pc_out,
		ifid_instruction,
		id_flush,
		id_freeze
	);
	
	-------------------------------------------------------------
	-- Stage 3: Execute -----------------------------------------
	-------------------------------------------------------------
	Stage3_Execute1 : ENTITY work.Stage3_Execute PORT MAP(
		master_clk,
		ex_srcA,
		ex_srcB,
		id_sign_ext,
		ex_result,
		ex_result_early,
		aluop,
		ifid_instruction(31 downto 21),
		alusrc,
		ex_alu_neg,
		ex_alu_zero,
		ex_alu_overf,
		ex_alu_carry,
		ifid_instruction,
		ifidex_instruction,
		ifid_pc_out,
		ifidex_pc_out,
		ex_opB,
		memwrite,
		memread,
		regwrite,
		memtoreg,
		set_flags,
		idex_memwrite,
		idex_memread,
		idex_regwrite,
		idex_memtoreg,
		idex_set_flags,
		ex_flush,
		ex_freeze
	);
	
	-------------------------------------------------------------
	-- Stage 4: Memory Access -----------------------------------
	-------------------------------------------------------------
	Stage4_Memory_Access1 : ENTITY work.Stage4_Memory_Access PORT MAP(
		master_clk,
		ex_result,
		mem_data_out2,
		mem_data_out,
		mem_address,
		ifidex_instruction,
		ifidexmem_instruction,
		ifidex_pc_out,
		ifidexmem_pc_out,
		idex_regwrite,
		idex_memtoreg,
		idexmem_regwrite,
		idexmem_memtoreg,
		mem_flush,
		mem_freeze
	);
	
	---------------------------------------------------------------
	-- Stage 5: Writeback -----------------------------------------
	---------------------------------------------------------------
	Stage5_Writeback1 : ENTITY work.Stage5_Writeback PORT MAP(
		master_clk,
		mem_address,
		mem_data_out,
		idexmem_memtoreg,
		wb_writeback_data
	);
	
	-- Declare Main Memory: --
	Main_Memory : ENTITY work.Memory PORT MAP(
		clk, mem_en, mem_wr, mem_rd, mem_ready,
		mem_address1, mem_address2, mem_data_in, mem_data_out1, mem_data_out2, mem_access_width, ae_flag
	);
	
	-- Declare IO Controller:
	IO_Controller1: ENTITY work.IO_Controller PORT MAP(
		clk, io_int_en, io_int_id, io_int_type, io_int_ack, io_int_ack_id, ien_flags(0), ien_flags(1)
	);
	
	-- Declare MMU:
	MMU1: ENTITY work.MMU PORT MAP(
		clk, pg_flag, pdp_out, mmu_pfla, mmu_pfla_wr
	);
	
	-- Two ways of entering interrupts: via the IO Controller, and via the instruction SINT - Software Interrupt
	io_int_id_reg   <= io_int_id   WHEN sint_type /= "10" ELSE sint_id;
	io_int_type_reg <= io_int_type WHEN sint_type /= "10" ELSE sint_type;
	
	-- ALU Flags, Exception and Interrupts Flags (CPSR) declaration:
	CPSR1: ENTITY work.CPSR PORT MAP(
		master_clk, cpu_state, io_int_type_reg,
		idex_set_flags, ex_alu_neg, ex_alu_zero, ex_alu_overf, ex_alu_carry, flag_neg, flag_zero, flag_overf, flag_carry,
		ae_flag, pg_flag, ien_flags, cpu_mode_flags,
		cpsr_wr, cpsr_rd, cpsr_wr_in, cpsr_rd_out, cpsr_field
	);
	
	cpsr_field                                 <= ifid_instruction(4 downto 0) WHEN ifid_instruction(31 downto 21) = "11000010100" ELSE ifid_instruction(9 downto 5);
	id_wr_addr_early                           <= ifid_instruction(9 downto 5) WHEN ifid_instruction(31 downto 21) = "11000010100" ELSE ifid_instruction(4 downto 0);
	cpsr_wr_in                                 <= id_outA(cpsr_wr_in'high downto 0);
	id_wr_dat_early(cpsr_rd_out'high downto 0) <= cpsr_rd_out;
	
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
	
	-- Assignments of Control Signals: --
	aluop          <= id_microcode_ctrl(2 downto 1); -- Control (EX)
	memwrite       <= id_microcode_ctrl(4);          -- Control (MEM)
	memread        <= id_microcode_ctrl(5);          -- Control (MEM)
	regwrite       <= id_microcode_ctrl(6);          -- Control (WB)
	memtoreg       <= id_microcode_ctrl(7);          -- Control (WB)
	alusrc         <= id_microcode_ctrl(8);          -- Control (EX)
	set_flags      <= id_microcode_ctrl(13);         -- Control (originates from ID and is used on stage EX)
	regwrite_early <= id_microcode_ctrl(14);         -- Control (ID)
	cpsr_rd        <= id_microcode_ctrl(15);         -- Control (ID)
	cpsr_wr        <= id_microcode_ctrl(16);         -- Control (ID)
	
	---------------------------
	------- Behaviour: --------
	---------------------------
	main_proc: process(clk, restart_cpu) begin
		-- On restart:
		if restart_cpu = '1' then
			-- Do nothing for now (TODO)
		else
			
			-- On clock:
			if clk = '0' then -- On negative edge
				-- Update old clock:
				if pause = '0' AND accessing_main_memory = '0' then
					clk_old_edge <= clk;
				end if;
				
				--------------------------------------
				-- CPU Finite State Machine algorithm:
				--------------------------------------
				case cpu_state is
					when s_fetching =>
					when s_savectx  => cpu_state  <= s_changemode;
					when s_changemode => 
						if io_int_type_reg = "00" then
							cpu_state <= s_jmpex;  -- Change CPU state to Exception execution
						elsif io_int_type_reg = "01" or io_int_type_reg = "10" then
							cpu_state <= s_jmpint; -- Change CPU state to Interrupt/Software Interrupt execution
						end if;
					when s_jmpint =>     cpu_state <= s_runint;
					when s_jmpex  =>     cpu_state <= s_runex;
					when s_runint =>     -- On the instruction RETI or while enabling interrupts, do: cpu_state <= s_restorectx
					when s_runex  =>     -- On the instruction RETI or while enabling interrupts, do: cpu_state <= s_restorectx
					when s_restorectx =>
						-- Clear all the software interrupt wires:
						sint_id   <= (others => '0');
						sint_type <= (others => '0');
						cpu_state <= s_fetching;
					when others =>
				end case;
				
				-- On RETI instruction:
				if if_instruction(31 downto 26) = "101000" then
					cpu_state <= s_restorectx;
				end if;
				
				--  On SINT instruction (Note: the SINT interrupt instruction has a higher priority compared to the IO interrupt):
				if if_instruction(31 downto 26) = "101001" and ien_flags(1) = '1' then
					if cpu_state = s_fetching then
						cpu_state <= s_savectx;
						sint_id   <= if_instruction(7 downto 0);
						sint_type <= "10";
					else
						-- TODO: The programmer tried to execute a software interrupt while inside an interrupt. 
						-- This is a double interrupt / fault and we should jump into exception mode because of this
					end if;
				end if;
				
				-- Handle Interrupt Requests (normal IRQs):
				if io_int_en = '1' and ien_flags(1) = '1' and cpu_state = s_fetching and if_instruction(31 downto 26) /= "101001" then
					cpu_state  <= s_savectx;
					io_int_ack <= '0'; -- Disable acknowledgment flag, indicating to the IO Controller that we're currently servicing an interrupt
				end if;

			else -- On positive edge
				
				if cpu_state = s_restorectx then
					-- Acknowledge the IO Controller's interrupt request:
					io_int_ack    <= '1'; -- The acknowledgement has been sent, and now we're waiting for more interrupts
					io_int_ack_id <= io_int_id;
				end if;
				
				-- Update old clock:
				if pause = '0' AND accessing_main_memory = '0'then
					clk_old_edge <= clk;
				end if;
				
			end if;
		end if;
	end process;
	--------------------------
END ARCHITECTURE RTL;