LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY FISC IS
	PORT(
		clk : IN std_logic;
		restart_cpu : in std_logic
	);
END;

ARCHITECTURE RTL OF FISC IS
	-----------------------------------------------
	---- Stage interconnect wires declaration: ----
	-- Stage 1 - Fetch Interconnect wires --
	signal if_new_pc             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal if_reset_pc           : std_logic := '0';
	signal if_branch_flag        : std_logic := '0';
	signal if_uncond_branch_flag : std_logic := '0';
	signal if_zero_flag          : std_logic := '0';
	signal if_instruction        : std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
	signal if_pc_out             : std_logic_vector(FISC_INTEGER_SZ-1 downto 0)     := (others => '0');
	
	-- Stage 2 - Decode Interconnect wires --
	signal id_sos            : std_logic := '0';
	signal id_microcode_ctrl : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	signal id_writedata      : std_logic_vector(FISC_INTEGER_SZ-1    downto 0) := (others => '0');
	signal id_reg2loc        : std_logic := '0';
	signal id_regwrite       : std_logic := '0';
	signal id_outA           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_outB           : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal id_sign_ext       : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	
	-- Stage 3 - Execute Interconnect wires --
	signal ex_aluop      : std_logic_vector(1  downto 0) := (others => '0');
	signal ex_result     : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_add_uncond : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal ex_alusrc     : std_logic := '0';
	signal ex_zero       : std_logic := '0';
	-----------------------------------------------
	
	-- Stage 4 - Memory Access Interconnect wires --
	signal mem_data_out : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal mem_memwrite : std_logic := '0';
	signal mem_memread  : std_logic := '0';
	------------------------------------------------
	
	-- Stage 5 - Writeback Interconnect wires --
	signal wb_memtoreg       : std_logic := '0';
	signal wb_writeback_data : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	--------------------------------------------
BEGIN
	---- Microarchitecture Stages Declaration: ----
	-- Stage 1: Fetch
	Stage1_Fetch1   : Stage1_Fetch   PORT MAP(clk, if_new_pc, if_reset_pc,  id_microcode_ctrl(0), if_branch_flag, if_uncond_branch_flag, if_zero_flag, if_instruction, if_pc_out);
	-- Stage 2: Decode
	Stage2_Decode1  : Stage2_Decode  PORT MAP(clk, id_sos, id_microcode_ctrl, if_instruction, id_writedata, id_reg2loc, id_regwrite, id_outA, id_outB, id_sign_ext);
	-- Stage 3: Execute
	Stage3_Execute1 : Stage3_Execute PORT MAP(clk, id_outA, id_outB, ex_result, ex_add_uncond, if_pc_out, id_sign_ext, ex_aluop, if_instruction(31 downto 21), ex_alusrc, ex_zero);
	-- Stage 4: Memory Access
	Stage4_Memory_Access1: Stage4_Memory_Access PORT MAP(clk, ex_result, id_outB, mem_data_out, mem_memwrite, mem_memread);
	-- Stage 3: Writeback
	Stage5_Writeback1: Stage5_Writeback PORT MAP(clk, ex_result, mem_data_out, wb_memtoreg, wb_writeback_data);
	
	--------------------------
	------- Behaviour: -------
	--------------------------
	process(clk, restart_cpu) begin
		if restart_cpu = '1' then
			id_sos <= '1';
		else
			if clk = '0' then
				if id_microcode_ctrl(0) = '1' then
					id_sos <= '1';
				end if;
			else
				id_sos <= '0';
			end if;
		end if;
	end process;
	--------------------------
END ARCHITECTURE RTL;