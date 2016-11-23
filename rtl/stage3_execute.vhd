LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Stage3_Execute IS
	PORT(
		clk                : in  std_logic;
		opA                : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		opB                : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		sign_ext           : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		result             : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		result_early       : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		aluop              : in  std_logic_vector(1  downto 0); -- Consume control on this stage
		opcode             : in  std_logic_vector(10 downto 0);
		alusrc             : in  std_logic;
		alu_neg            : out std_logic;
		alu_zero           : out std_logic;
		alu_overf          : out std_logic;
		alu_carry          : out std_logic;
		-- Pipeline (data) outputs:
		ifid_instruction   : in  std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0);
		ifidex_instruction : out std_logic_vector(FISC_INSTRUCTION_SZ-1 downto 0) := (others => '0');
		ifid_pc_out        : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		ifidex_pc_out      : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
		ex_opB             : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)     := (others => '0');
		-- Pipeline (control) outputs
		id_memwrite        : in  std_logic;
		id_memread         : in  std_logic;
		id_regwrite        : in  std_logic;
		id_memtoreg        : in  std_logic;
		id_set_flags       : in  std_logic; -- Consume control on this stage (by another stage)
		idex_memwrite      : out std_logic := '0';
		idex_memread       : out std_logic := '0';
		idex_regwrite      : out std_logic := '0';
		idex_memtoreg      : out std_logic := '0';
		idex_set_flags     : out std_logic := '0'; -- Consume control on this stage (by another stage)
		-- Pipeline flush/freeze:
		ex_flush           : in  std_logic;
		ex_freeze          : in  std_logic
	);
END Stage3_Execute;

ARCHITECTURE RTL OF Stage3_Execute IS
	signal alu_opB_reg   : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal func_reg      : std_logic_vector(3 downto 0) := (others => '0');
	-- Inner Pipeline Layer:
	signal result_reg    : std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal alu_neg_reg   : std_logic := '0';
	signal alu_zero_reg  : std_logic := '0';
	signal alu_overf_reg : std_logic := '0';
	signal alu_carry_reg : std_logic := '0';
BEGIN
	-- Instantiate ALU:
	ALU1: ENTITY work.ALU PORT MAP(clk, opA, alu_opB_reg, func_reg, result_reg, alu_neg_reg, alu_zero_reg, alu_overf_reg, alu_carry_reg);
	
	alu_opB_reg  <= sign_ext WHEN alusrc = '1' ELSE opB;
	result_early <= result_reg;
	
	func_reg   <= "0010" WHEN aluop = "00" ELSE "0111" WHEN aluop(0) = '1' ELSE 
	              "0010" WHEN (aluop(1) = '1' AND (opcode = "10001011000" or opcode(10 downto 1) = "1001000100" or opcode(10 downto 1) = "1011000100" or opcode = "10101011000" or opcode(10 downto 2) = "111100101" or opcode(10 downto 2) = "110100101")) ELSE -- ADD, MOVK and MOVZ
	              "0110" WHEN (aluop(1) = '1' AND (opcode = "11001011000" or opcode(10 downto 1) = "1101000100" or opcode(10 downto 1) = "1111000100" or opcode = "11101011000")) ELSE -- SUB
	              "0000" WHEN (aluop(1) = '1' AND (opcode = "10001010000" or opcode(10 downto 1) = "1001001000" or opcode(10 downto 1) = "1111001000" or opcode = "11101010000")) ELSE -- AND
	              "0001" WHEN (aluop(1) = '1' AND (opcode = "10101010000" or opcode(10 downto 1) = "1011001000")) ELSE -- ORR
	              "0011" WHEN (aluop(1) = '1' AND (opcode = "11001010000" or opcode(10 downto 1) = "1101001000")) ELSE -- EOR
	              "1000" WHEN (aluop(1) = '1' AND (opcode = "11101101000" or opcode(10 downto 1) = "0111000100")) ELSE -- NEG
	              "1001" WHEN (aluop(1) = '1' AND (opcode = "11101101001" or opcode(10 downto 1) = "0101000100")) ELSE -- NOT
	              "1010" WHEN (aluop(1) = '1' AND (opcode = "10011011000" or opcode = "10011011010")) ELSE -- MUL and SMULH
	              "1011" WHEN (aluop(1) = '1' AND (opcode = "10011011110")) ELSE -- UMULH
	              "1100" WHEN (aluop(1) = '1' AND (opcode = "10011010110")) ELSE -- SDIV
	              "1101" WHEN (aluop(1) = '1' AND (opcode = "10011010111")) ELSE -- UDIV
	              "1110" WHEN (aluop(1) = '1' AND (opcode = "11010011011")) ELSE -- LSL
	              "1111" WHEN (aluop(1) = '1' AND (opcode = "11010011010")) ELSE -- LSR
	              (others => 'X');
	           
	----------------
	-- Behaviour: --
	----------------   
	main_proc: process(clk) begin
		if rising_edge(clk) then
			if ex_freeze = '0' then
				if ex_flush = '0' then
					-- Move the Execute Stage's Inner Pipeline Forward:
					result             <= result_reg;
					ex_opB             <= opB;
					ifidex_instruction <= ifid_instruction;
					ifidex_pc_out      <= ifid_pc_out;
					-- Move the controls:
					idex_memwrite      <= id_memwrite;
					idex_memread       <= id_memread;
					idex_regwrite      <= id_regwrite;
					idex_memtoreg      <= id_memtoreg;
					idex_set_flags     <= id_set_flags;
					alu_neg            <= alu_neg_reg;
					alu_zero           <= alu_zero_reg;
					alu_overf          <= alu_overf_reg;
					alu_carry          <= alu_carry_reg;
				else
					-- Stall the pipeline (preserve the data):
					idex_memwrite      <= '0';
					idex_memread       <= '0';
					idex_regwrite      <= '0';
					idex_memtoreg      <= '0';
					idex_set_flags     <= '0';
					alu_neg            <= '0';
					alu_zero           <= '0';
					alu_overf          <= '0';
					alu_carry          <= '0';
				end if;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;