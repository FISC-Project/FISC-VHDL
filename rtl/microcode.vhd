LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY Microcode IS
	PORT(
		clk              : in  std_logic; -- Clock signal
		sos              : in  std_logic; -- Start of segment flag (triggers on rising edge)
		microcode_opcode : in  std_logic_vector(R_FMT_OPCODE_SZ-1    downto 0); -- Microcode's Opcode input to the FSM
		microcode_ctrl   : out std_logic_vector(MICROCODE_CTRL_WIDTH downto 0)  -- Result of indexing Microcode's memory with the opcode input
		-- NOTE: The 1st bit of 'microcode_ctrl' tells the external system when the Microcode Unit has finished dumping its control signals
	);
END Microcode;

ARCHITECTURE RTL OF Microcode IS
	----- >> Local private variables: << -----
	-- Microcode Memory:
	constant cmw : integer := MICROCODE_FUNC_WIDTH + MICROCODE_CTRL_WIDTH + 1; -- cmw stands for code_memory_width. This name is small on purpose
	constant smw : integer := MICROCODE_SEGMENT_MAXCOUNT_ENC; -- smw stands for segment_memory_width. This name is small on purpose
	type seg_t is array (0 to MICROCODE_SEGMENT_MAXCOUNT) of std_logic_vector(smw downto 0);
	type code_t is array (0 to MICROCODE_CTRL_DEPTH) of std_logic_vector(cmw downto 0);
	
	function microinstr (
		control  : std_logic_vector(MICROCODE_CTRL_WIDTH-2 downto 0);
		is_eos   : std_logic
	) return std_logic_vector is
	begin
		return "00000000000000000000000000000000" & "00" & control & is_eos; -- FORMAT: MCU_FUNC | SEG_TYPE | CONTROL BITS | IS EOS
	end;
	
	function create_segment (
		segment_ptr : integer
	) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(segment_ptr, MICROCODE_SEGMENT_MAXCOUNT_ENC+1));
	end;
	
	--*****************************************************************************************************************--
	-- IMPORTANT: Fill up microcode execute memory (which is segmented) here: (ARGS: control bits | is end of segment) --
	-- Control Signal list (Producer/Consumer):
	-- cpsr_wr (ID/ID) | cpsr_rd (ID/ID) | regwrite_early (ID/ID) | setflags (ID/EX) | signext_src(3) (ID) | reg2loc (IF/ID (OPCODE)) | alusrc (ID/EX) | memtoreg (ID/WB) | regwrite (ID/WB) | memread (ID/MEM) | memwrite (ID/MEM) | ubranch (IF/ID (MCU)) | aluop(2) (ID/EX)
	signal code : code_t := (
		0 =>  microinstr("---------------0000000000000000", '1'), -- NULL INSTRUCTION
		1 =>  microinstr("---------------0000000000100010", '1'), -- Instruction ADD
		2 =>  microinstr("---------------0000000010100010", '1'), -- Instruction ADDI
		3 =>  microinstr("---------------0001000010100010", '1'), -- Instruction ADDIS
		4 =>  microinstr("---------------0001000000100010", '1'), -- Instruction ADDS
		5 =>  microinstr("---------------0000000000100010", '1'), -- Instruction SUB
		6 =>  microinstr("---------------0000000010100010", '1'), -- Instruction SUBI
		7 =>  microinstr("---------------0001000010100010", '1'), -- Instruction SUBIS
		8 =>  microinstr("---------------0001000000100010", '1'), -- Instruction SUBS
		9 =>  microinstr("---------------0000001000100010", '1'), -- Instruction MUL
		10 => microinstr("---------------0000001000100010", '1'), -- Instruction SMULH -- UNIMPLEMENTED (REASON: NEEDS 128 BIT REGISTER FROM FPU)
		11 => microinstr("---------------0000001000100010", '1'), -- Instruction UMULH -- UNIMPLEMENTED (REASON: NEEDS 128 BIT REGISTER FROM FPU)
		12 => microinstr("---------------0000001000100010", '1'), -- Instruction SDIV
		13 => microinstr("---------------0000001000100010", '1'), -- Instruction UDIV
		14 => microinstr("---------------0000000000100010", '1'), -- Instruction AND
		15 => microinstr("---------------0000000010100010", '1'), -- Instruction ANDI
		16 => microinstr("---------------0001000010100010", '1'), -- Instruction ANDIS
		17 => microinstr("---------------0001000000100010", '1'), -- Instruction ANDS
		18 => microinstr("---------------0000000000100010", '1'), -- Instruction ORR
		19 => microinstr("---------------0000000010100010", '1'), -- Instruction ORRI
		20 => microinstr("---------------0000000000100010", '1'), -- Instruction EOR
		21 => microinstr("---------------0000000010100010", '1'), -- Instruction EORI
		22 => microinstr("---------------0000001010100010", '1'), -- Instruction LSL
		23 => microinstr("---------------0000001010100010", '1'), -- Instruction LSR
		24 => microinstr("---------------0000101010100001", '1'), -- Instruction MOVK
		25 => microinstr("---------------0000101010100001", '1'), -- Instruction MOVZ
		26 => microinstr("---------------0000011100000101", '1'), -- Instruction B
		27 => microinstr("---------------0000100100000001", '1'), -- Instruction B.cond
		28 => microinstr("---------------0000110110100101", '1'), -- Instruction BL
		29 => microinstr("---------------0000000100000101", '1'), -- Instruction BR
		30 => microinstr("---------------0000100100000001", '1'), -- Instruction CBNZ
		31 => microinstr("---------------0000100100000001", '1'), -- Instruction CBZ
		32 => microinstr("---------------0000010111110000", '1'), -- Instruction LDUR
		33 => microinstr("---------------0000010111110000", '1'), -- Instruction LDURB
		34 => microinstr("---------------0000010111110000", '1'), -- Instruction LDURH
		35 => microinstr("---------------0000010111110000", '1'), -- Instruction LDURSW
		36 => microinstr("---------------0000010111110000", '1'), -- Instruction LDXR -- TODO ATOMIC
		37 => microinstr("---------------0000010110001000", '1'), -- Instruction STUR
		38 => microinstr("---------------0000010110001000", '1'), -- Instruction STURB
		39 => microinstr("---------------0000010110001000", '1'), -- Instruction STURH
		40 => microinstr("---------------0000010110001000", '1'), -- Instruction STURW
		41 => microinstr("---------------0000010110001000", '1'), -- Instruction STXR -- TODO ATOMIC
		-- Newly added instructions that do not belong to LEGv8:
		42 => microinstr("---------------0000000100100010", '1'), -- Instruction NEG
		43 => microinstr("---------------0000000100100010", '1'), -- Instruction NOT
		44 => microinstr("---------------0000000010100010", '1'), -- Instruction NEGI
		45 => microinstr("---------------0000000010100010", '1'), -- Instruction NOTI
		46 => microinstr("---------------1000000000000010", '1'), -- Instruction MSR
		47 => microinstr("---------------0110000000000000", '1'), -- Instruction MRS
		48 => microinstr("---------------0010000000000000", '1'), -- Instruction LIVP
		49 => microinstr("---------------0010000000000000", '1'), -- Instruction SIVP
		50 => microinstr("---------------0010000000000000", '1'), -- Instruction LEVP
		51 => microinstr("---------------0010000000000000", '1'), -- Instruction SEVP
		52 => microinstr("---------------0010000000000000", '1'), -- Instruction SESR
		53 => microinstr("---------------0000000000000000", '1'), -- Instruction RETI
		54 => microinstr("---------------0000000000000000", '1'), -- Instruction SINT
		55 => microinstr("---------------0010000000000000", '1'), -- Instruction LDPC
		-- END OF MICROCODE MEMORY -
		others => (others => '0')
	);
	--*****************************************************************************************************************--
	--*****************************************--
	-- IMPORTANT: Fill up segment memory here: -- (NOTE: The index below IS the opcode that will be associated)
	signal seg_start : seg_t := (
		0  => create_segment(0),  -- Opcode 0  runs microcode at address 0  (decimal) (NULL)
		1  => create_segment(1),  -- Opcode 1  runs microcode at address 1  (decimal) (ADD)
		2  => create_segment(2),  -- Opcode 2  runs microcode at address 2  (decimal) (ADDI)
		3  => create_segment(3),  -- Opcode 3  runs microcode at address 3  (decimal) (ADDIS)
		4  => create_segment(4),  -- Opcode 4  runs microcode at address 4  (decimal) (ADDS)
		5  => create_segment(5),  -- Opcode 5  runs microcode at address 5  (decimal) (SUB)
		6  => create_segment(6),  -- Opcode 6  runs microcode at address 6  (decimal) (SUBI)
		7  => create_segment(7),  -- Opcode 7  runs microcode at address 7  (decimal) (SUBIS)
		8  => create_segment(8),  -- Opcode 8  runs microcode at address 8  (decimal) (SUBS)
		9  => create_segment(9),  -- Opcode 9  runs microcode at address 9  (decimal) (MUL)
		10 => create_segment(10), -- Opcode 10 runs microcode at address 10 (decimal) (SMULH)
		11 => create_segment(11), -- Opcode 11 runs microcode at address 11 (decimal) (UMULH)
		12 => create_segment(12), -- Opcode 12 runs microcode at address 12 (decimal) (SDIV)
		13 => create_segment(13), -- Opcode 13 runs microcode at address 13 (decimal) (UDIV)
		14 => create_segment(14), -- Opcode 14 runs microcode at address 14 (decimal) (AND)
		15 => create_segment(15), -- Opcode 15 runs microcode at address 15 (decimal) (ANDI)
		16 => create_segment(16), -- Opcode 16 runs microcode at address 16 (decimal) (ANDIS)
		17 => create_segment(17), -- Opcode 17 runs microcode at address 17 (decimal) (ANDS)
		18 => create_segment(18), -- Opcode 18 runs microcode at address 18 (decimal) (ORR)
		19 => create_segment(19), -- Opcode 19 runs microcode at address 19 (decimal) (ORRI)
		20 => create_segment(20), -- Opcode 20 runs microcode at address 20 (decimal) (EOR)
		21 => create_segment(21), -- Opcode 21 runs microcode at address 21 (decimal) (EORI)
		22 => create_segment(22), -- Opcode 22 runs microcode at address 22 (decimal) (LSL)
		23 => create_segment(23), -- Opcode 23 runs microcode at address 23 (decimal) (LSR)
		24 => create_segment(24), -- Opcode 24 runs microcode at address 24 (decimal) (MOVK)
		25 => create_segment(25), -- Opcode 25 runs microcode at address 25 (decimal) (MOVZ)
		26 => create_segment(26), -- Opcode 26 runs microcode at address 26 (decimal) (B)
		27 => create_segment(27), -- Opcode 27 runs microcode at address 27 (decimal) (B.cond)
		28 => create_segment(28), -- Opcode 28 runs microcode at address 28 (decimal) (BL)
		29 => create_segment(29), -- Opcode 29 runs microcode at address 29 (decimal) (BR)
		30 => create_segment(30), -- Opcode 30 runs microcode at address 30 (decimal) (CBNZ)
		31 => create_segment(31), -- Opcode 31 runs microcode at address 31 (decimal) (CBZ)
		32 => create_segment(32), -- Opcode 32 runs microcode at address 32 (decimal) (LDUR)
		33 => create_segment(33), -- Opcode 33 runs microcode at address 33 (decimal) (LDURB)
		34 => create_segment(34), -- Opcode 34 runs microcode at address 34 (decimal) (LDURH)
		35 => create_segment(35), -- Opcode 35 runs microcode at address 35 (decimal) (LDURSW)
		36 => create_segment(36), -- Opcode 36 runs microcode at address 36 (decimal) (LDXR)
		37 => create_segment(37), -- Opcode 37 runs microcode at address 37 (decimal) (STUR)
		38 => create_segment(38), -- Opcode 38 runs microcode at address 38 (decimal) (STURB)
		39 => create_segment(39), -- Opcode 39 runs microcode at address 39 (decimal) (STURH)
		40 => create_segment(40), -- Opcode 40 runs microcode at address 40 (decimal) (STURW)
		41 => create_segment(41), -- Opcode 41 runs microcode at address 41 (decimal) (STXR)
		-- Newly added instructions that do not belong to LEGv8:
		42 => create_segment(42), -- Opcode 42 runs microcode at address 42 (decimal) (NEG)
		43 => create_segment(43), -- Opcode 43 runs microcode at address 43 (decimal) (NOT)
		44 => create_segment(44), -- Opcode 44 runs microcode at address 44 (decimal) (NEGI)
		45 => create_segment(45), -- Opcode 45 runs microcode at address 45 (decimal) (NOTI)
		46 => create_segment(46), -- Opcode 46 runs microcode at address 46 (decimal) (MSR)
		47 => create_segment(47), -- Opcode 47 runs microcode at address 47 (decimal) (MRS)
		48 => create_segment(48), -- Opcode 48 runs microcode at address 48 (decimal) (LIVP)
		49 => create_segment(49), -- Opcode 49 runs microcode at address 49 (decimal) (SIVP)
		50 => create_segment(50), -- Opcode 50 runs microcode at address 50 (decimal) (LEVP)
		51 => create_segment(51), -- Opcode 51 runs microcode at address 51 (decimal) (SEVP)
		52 => create_segment(52), -- Opcode 52 runs microcode at address 52 (decimal) (SESR)
		53 => create_segment(53), -- Opcode 53 runs microcode at address 53 (decimal) (RETI)
		54 => create_segment(54), -- Opcode 54 runs microcode at address 54 (decimal) (SINT)
		55 => create_segment(55), -- Opcode 55 runs microcode at address 55 (decimal) (LDPC)
		-- END OF SEGMENT MEMORY --
		others => (others => '0')
	);
	--*****************************************--
	
	signal int_seg_start : seg_t := (others => (others => '0')); -- Since FISC will be simple, there will be no internal segments
	
	signal microunit_running : std_logic := '1';
	signal microunit_init : std_logic := '0';
	-- Control Register:
	signal ctrl_reg : std_logic_vector(MICROCODE_CTRL_WIDTH downto 0) := (others => '0');
	-- End of Segment Flag, which is used strictly by the Microcode Unit:
	signal eos : std_logic := '0';
	-- Microcode Instruction Pointer:
	signal code_ip : std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0) := (others => '0');
	-- Callstack:
	type call_stack_t is array (0 to MICROCODE_CALLSTACK_SIZE-1) of std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
	signal call_stack : call_stack_t := (others => (others => '0'));
	signal stack_ptr : std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) := (others => '0');
	-- Flags:
	signal flag_jmp : std_logic := '0';
	signal flag_jmp_addr : std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0) := (others => '1');
	signal zero : std_logic := '0';
	------------------------------------------
	
	function OPCODE_TO_MICROCODE_OPCODE 
		(isa_opcode : std_logic_vector(R_FMT_OPCODE_SZ-1 downto 0)) return std_logic_vector is
	begin
		-- Convert from ISA Opcode (which is a 'high' 11 bit number), to a microcode opcode,
		-- which is a very small opcode, such as 0,1,2,3,4...
		
		-- Cover the 11 bit opcodes:
		case isa_opcode is
			when "10001011000" => return "00000000001"; -- ADD
			when "10101011000" => return "00000000100"; -- ADDS
			when "11001011000" => return "00000000101"; -- SUB
			when "11101011000" => return "00000001000"; -- SUBS
			when "10011011000" => return "00000001001"; -- MUL
			when "10011011010" => return "00000001010"; -- SMULH
			when "10011011110" => return "00000001011"; -- UMULH
			when "10011010110" => return "00000001100"; -- SDIV
			when "10011010111" => return "00000001101"; -- UDIV
			when "10001010000" => return "00000001110"; -- AND
			when "11101010000" => return "00000010001"; -- ANDS
			when "10101010000" => return "00000010010"; -- ORR
			when "11001010000" => return "00000010100"; -- EOR
			when "11010011011" => return "00000010110"; -- LSL
			when "11010011010" => return "00000010111"; -- LSR
			when "11110010100" => return "00000011000"; -- MOVK
			when "11110010101" => return "00000011000"; -- MOVK
			when "11110010110" => return "00000011000"; -- MOVK
			when "11110010111" => return "00000011000"; -- MOVK
			when "11010010100" => return "00000011001"; -- MOVZ
			when "11010010101" => return "00000011001"; -- MOVZ
			when "11010010110" => return "00000011001"; -- MOVZ
			when "11010010111" => return "00000011001"; -- MOVZ
			when "11010110000" => return "00000011101"; -- BR
			when "11111000010" => return "00000100000"; -- LDUR
			when "00111000010" => return "00000100001"; -- LDURB
			when "01111000010" => return "00000100010"; -- LDURH
			when "10111000100" => return "00000100011"; -- LDURSW
			when "11001000010" => return "00000100100"; -- LDXR
			when "11111000000" => return "00000100101"; -- STUR
			when "00111000000" => return "00000100110"; -- STURB
			when "01111000000" => return "00000100111"; -- STURH
			when "10111000000" => return "00000101000"; -- STURW
			when "11001000000" => return "00000101001"; -- STXR
			-- Newly added instructions that do not belong to LEGv8:
			when "11101101000" => return "00000101010"; -- NEG
			when "11101101001" => return "00000101011"; -- NOT
			when "11000010100" => return "00000101110"; -- MSR
			when "10111110100" => return "00000101111"; -- MRS
			when "10111010100" => return "00000110000"; -- LIVP
			when "10110110100" => return "00000110001"; -- SIVP
			when "10110010100" => return "00000110010"; -- LEVP
			when "10101110100" => return "00000110011"; -- SEVP
			when "10101010100" => return "00000110100"; -- SESR
			when "10101000100" => return "00000110111"; -- LDPC
			when others => -- Do nothing here
		end case;
		
		-- Cover the 10 bit opcodes:
		case isa_opcode(10 downto 1) is
			when "1001000100" => return "00000000010"; -- ADDI
			when "1011000100" => return "00000000011"; -- ADDIS
			when "1101000100" => return "00000000110"; -- SUBI
			when "1111000100" => return "00000000111"; -- SUBIS
			when "1001001000" => return "00000001111"; -- ANDI
			when "1111001000" => return "00000010000"; -- ANDIS
			when "1011001000" => return "00000010011"; -- ORRI
			when "1101001000" => return "00000010101"; -- EORI
			-- Newly added instructions that do not belong to LEGv8:
			when "0111000100" => return "00000101100"; -- NEGI
			when "0101000100" => return "00000101101"; -- NOTI
			when others => -- Do nothing here
		end case;
		
		-- Cover the 8 bit opcodes:
		case isa_opcode(10 downto 3) is
			when "01010100" => return "00000011011"; -- B.cond
			when "10110101" => return "00000011110"; -- CBNZ
			when "10110100" => return "00000011111"; -- CBZ
			-- Newly added instructions that do not belong to LEGv8:
			when others => -- Do nothing here
		end case;
		
		-- Cover the 6 bit opcodes:
		case isa_opcode(10 downto 5) is
			when "000101" => return "00000011010"; -- B
			when "100101" => return "00000011100"; -- BL
			-- Newly added instructions that do not belong to LEGv8:
			when "101000" => return "00000110101"; -- RETI
			when "101001" => return "00000110110"; -- SINT
			when others => -- Do nothing here
		end case;
		
		-- Return NULL opcode: (TODO: Enter Undefined Instruction here)
		return (R_FMT_OPCODE_SZ-1 downto 0 => '0');
	end;	
	
	-------- PROCEDURES --------
	procedure schedule_jmp (
		new_addr : in std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal flag_jmp_addr : out std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal flag_jmp      : out std_logic
	) is begin
		flag_jmp_addr <= new_addr;
		flag_jmp <= '1';
	end;
	
	procedure push_stack (
		address : in std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal call_stack : out call_stack_t;
		signal stack_ptr  : inout std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0)
	) is begin
		call_stack(to_integer(unsigned(stack_ptr))) <= address;
		stack_ptr <= stack_ptr + "1";
	end;
	
	procedure pop_stack (
		signal flag_jmp_addr : out std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal flag_jmp      : out std_logic;
		signal call_stack    : inout call_stack_t;
		signal stack_ptr     : inout std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0)
	) is begin
		if unsigned(stack_ptr) > 0 then
			stack_ptr <= stack_ptr - "1";
			schedule_jmp(call_stack(to_integer(unsigned(stack_ptr))), flag_jmp_addr, flag_jmp);
		end if;		
	end;
	
	procedure exec_microinstruction  (
		address              : in std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal flag_jmp_addr : out std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0);
		signal flag_jmp      : out std_logic;
		signal call_stack    : inout call_stack_t;
		signal stack_ptr     : inout std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0);
		signal ctrl_reg      : out std_logic_vector(MICROCODE_CTRL_WIDTH downto 0)
	)
	is 
		variable func_fmt : std_logic_vector(MICROCODE_FUNC_WIDTH-1 downto 0) := (others => '0');
	begin
		func_fmt := code(to_integer(unsigned(address)))(MICROCODE_FUNC_WIDTH + MICROCODE_CTRL_WIDTH - 1 downto (MICROCODE_FUNC_WIDTH + MICROCODE_CTRL_WIDTH) - 32);
		case func_fmt(MICROCODE_FUNC_WIDTH-1 downto MICROCODE_FUNC_WIDTH-4) is
			when "0000" => -- No op
			when "0001" => 
				-- Jump to OPCODE segment on the next cycle
				schedule_jmp(seg_start(to_integer(unsigned(func_fmt(MICROCODE_FUNC_WIDTH-6 downto 0)))), flag_jmp_addr, flag_jmp);
				push_stack(address, call_stack, stack_ptr);
			when "0010" =>
				-- Jump to INSTRUCTION/FUNCTION segment on the next cycle
				schedule_jmp(int_seg_start(to_integer(unsigned(func_fmt(MICROCODE_FUNC_WIDTH-6 downto 0)))), flag_jmp_addr, flag_jmp);
				push_stack(address, call_stack, stack_ptr);
			when others =>
		end case;
		-- Fetch control from Microcode Memory:
		ctrl_reg <= code(to_integer(unsigned(address)))(MICROCODE_CTRL_WIDTH downto 0);
	end;
	
	procedure check_microcode_running (
		signal microunit_running : out std_logic
	)
	is begin
		case microcode_opcode is
			when "11111111111" => microunit_running <= '0';
			when others => microunit_running <= '1';
		end case;
	end;
	----------------------------
BEGIN
	-- End of segment flag is triggered by the last bit of the control register:
	eos <= ctrl_reg(0);
	
	-- Assign output:
	microcode_ctrl <= ctrl_reg;
	
	ctrl_reg <= code(to_integer(unsigned(seg_start(to_integer(unsigned(OPCODE_TO_MICROCODE_OPCODE(microcode_opcode)))))))(MICROCODE_CTRL_WIDTH downto 0);
	
	-------- SYSTEM PROCESSES --------
	-- !!!!IMPORTANT TODO!!!!! : FIX THE DAMN MULTICYCLE INSTRUCTIONS, THIS TIME DON'T ASSIGN TO CTRL_REG ON EVERY POSITIVE CLOCK CYCLE
	-- JUST INCREMENT/JUMP CODE_IP
	process(clk)
		variable code_ip_tmp : std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0) := (others => '0');
	begin
		if clk'event and clk = '1' then

		end if;		
	end process;
	----------------------------------
END ARCHITECTURE RTL;