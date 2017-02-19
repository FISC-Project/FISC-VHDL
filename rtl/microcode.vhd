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
	-- pc_rel (ID/ID) | cpsr_wr (ID/ID) | cpsr_rd (ID/ID) | regwrite_early (ID/ID) | setflags (ID/EX) | signext_src(3) (ID) | reg2loc (IF/ID (OPCODE)) | alusrc (ID/EX) | memtoreg (ID/WB) | regwrite (ID/WB) | memread (ID/MEM) | memwrite (ID/MEM) | ubranch (IF/ID (MCU)) | aluop(2) (ID/EX)
	signal code : code_t := (
		0 =>  microinstr("--------------00000000000000000", '1'), -- NULL INSTRUCTION
		1 =>  microinstr("--------------00000000000100010", '1'), -- Instruction ADD
		2 =>  microinstr("--------------00000000010100010", '1'), -- Instruction ADDI
		3 =>  microinstr("--------------00001000010100010", '1'), -- Instruction ADDIS
		4 =>  microinstr("--------------00001000000100010", '1'), -- Instruction ADDS
		5 =>  microinstr("--------------00000000000100010", '1'), -- Instruction SUB
		6 =>  microinstr("--------------00000000010100010", '1'), -- Instruction SUBI
		7 =>  microinstr("--------------00001000010100010", '1'), -- Instruction SUBIS
		8 =>  microinstr("--------------00001000000100010", '1'), -- Instruction SUBS
		9 =>  microinstr("--------------00000001000100010", '1'), -- Instruction MUL
		10 => microinstr("--------------00000001000100010", '1'), -- Instruction SMULH -- UNIMPLEMENTED (REASON: NEEDS 128 BIT REGISTER FROM FPU)
		11 => microinstr("--------------00000001000100010", '1'), -- Instruction UMULH -- UNIMPLEMENTED (REASON: NEEDS 128 BIT REGISTER FROM FPU)
		12 => microinstr("--------------00000001000100010", '1'), -- Instruction SDIV
		13 => microinstr("--------------00000001000100010", '1'), -- Instruction UDIV
		14 => microinstr("--------------00000000000100010", '1'), -- Instruction AND
		15 => microinstr("--------------00000000010100010", '1'), -- Instruction ANDI
		16 => microinstr("--------------00001000010100010", '1'), -- Instruction ANDIS
		17 => microinstr("--------------00001000000100010", '1'), -- Instruction ANDS
		18 => microinstr("--------------00000000000100010", '1'), -- Instruction ORR
		19 => microinstr("--------------00000000010100010", '1'), -- Instruction ORRI
		20 => microinstr("--------------00000000000100010", '1'), -- Instruction EOR
		21 => microinstr("--------------00000000010100010", '1'), -- Instruction EORI
		22 => microinstr("--------------00000001010100010", '1'), -- Instruction LSL
		23 => microinstr("--------------00000001010100010", '1'), -- Instruction LSR
		24 => microinstr("--------------00000101010100001", '1'), -- Instruction MOVK
		25 => microinstr("--------------00000101010100001", '1'), -- Instruction MOVZ
		26 => microinstr("--------------00000011100000101", '1'), -- Instruction B
		27 => microinstr("--------------00000100100000001", '1'), -- Instruction B.cond
		28 => microinstr("--------------00000110110100101", '1'), -- Instruction BL
		29 => microinstr("--------------00000000100000101", '1'), -- Instruction BR
		30 => microinstr("--------------00000100100000001", '1'), -- Instruction CBNZ
		31 => microinstr("--------------00000100100000001", '1'), -- Instruction CBZ
		32 => microinstr("--------------00000010111110000", '1'), -- Instruction LDR
		33 => microinstr("--------------00000010111110000", '1'), -- Instruction LDRB
		34 => microinstr("--------------00000010111110000", '1'), -- Instruction LDRH
		35 => microinstr("--------------00000010111110000", '1'), -- Instruction LDRSW
		36 => microinstr("--------------00000010111110000", '1'), -- Instruction LDXR -- TODO ATOMIC
		37 => microinstr("--------------00000010110001000", '1'), -- Instruction STR
		38 => microinstr("--------------00000010110001000", '1'), -- Instruction STRB
		39 => microinstr("--------------00000010110001000", '1'), -- Instruction STRH
		40 => microinstr("--------------00000010110001000", '1'), -- Instruction STRW
		41 => microinstr("--------------00000010110001000", '1'), -- Instruction STXR -- TODO ATOMIC
		-- Newly added instructions that do not belong to LEGv8:
		42 => microinstr("--------------00000000100100010", '1'), -- Instruction NEG
		43 => microinstr("--------------00000000100100010", '1'), -- Instruction NOT
		44 => microinstr("--------------00000000010100010", '1'), -- Instruction NEGI
		45 => microinstr("--------------00000000010100010", '1'), -- Instruction NOTI
		46 => microinstr("--------------01000000000000010", '1'), -- Instruction MSR
		47 => microinstr("--------------00110000000000000", '1'), -- Instruction MRS
		48 => microinstr("--------------00010000000000000", '1'), -- Instruction LIVP
		49 => microinstr("--------------00010000000000000", '1'), -- Instruction SIVP
		50 => microinstr("--------------00010000000000000", '1'), -- Instruction LEVP
		51 => microinstr("--------------00010000000000000", '1'), -- Instruction SEVP
		52 => microinstr("--------------00010000000000000", '1'), -- Instruction SESR
		53 => microinstr("--------------00000000000000000", '1'), -- Instruction RETI
		54 => microinstr("--------------00000000000000000", '1'), -- Instruction SINT
		55 => microinstr("--------------00010000000000000", '1'), -- Instruction LDPC
		56 => microinstr("--------------10000010111110000", '1'), -- Instruction LDRR
		57 => microinstr("--------------10000010111110000", '1'), -- Instruction LDRBR
		58 => microinstr("--------------10000010111110000", '1'), -- Instruction LDRHR
		59 => microinstr("--------------10000010111110000", '1'), -- Instruction LDRSWR
		60 => microinstr("--------------10000010111110000", '1'), -- Instruction LDXRR -- TODO ATOMIC
		61 => microinstr("--------------10000010110001000", '1'), -- Instruction STRR
		62 => microinstr("--------------10000010110001000", '1'), -- Instruction STRBR
		63 => microinstr("--------------10000010110001000", '1'), -- Instruction STRHR
		64 => microinstr("--------------10000010110001000", '1'), -- Instruction STRWR
		65 => microinstr("--------------10000010110001000", '1'), -- Instruction STXRR -- TODO ATOMIC
		66 => microinstr("--------------00010000000000000", '1'), -- Instruction LPDP
		67 => microinstr("--------------00010000000000000", '1'), -- Instruction SPDP
		68 => microinstr("--------------00010000000000000", '1'), -- Instruction LPFLA
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
		32 => create_segment(32), -- Opcode 32 runs microcode at address 32 (decimal) (LDR)
		33 => create_segment(33), -- Opcode 33 runs microcode at address 33 (decimal) (LDRB)
		34 => create_segment(34), -- Opcode 34 runs microcode at address 34 (decimal) (LDRH)
		35 => create_segment(35), -- Opcode 35 runs microcode at address 35 (decimal) (LDRSW)
		36 => create_segment(36), -- Opcode 36 runs microcode at address 36 (decimal) (LDXR)
		37 => create_segment(37), -- Opcode 37 runs microcode at address 37 (decimal) (STR)
		38 => create_segment(38), -- Opcode 38 runs microcode at address 38 (decimal) (STRB)
		39 => create_segment(39), -- Opcode 39 runs microcode at address 39 (decimal) (STRH)
		40 => create_segment(40), -- Opcode 40 runs microcode at address 40 (decimal) (STRW)
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
		56 => create_segment(56), -- Opcode 56 runs microcode at address 56 (decimal) (LDRR)
		57 => create_segment(57), -- Opcode 57 runs microcode at address 57 (decimal) (LDRBR)
		58 => create_segment(58), -- Opcode 58 runs microcode at address 58 (decimal) (LDRHR)
		59 => create_segment(59), -- Opcode 59 runs microcode at address 59 (decimal) (LDRSWR)
		60 => create_segment(60), -- Opcode 60 runs microcode at address 60 (decimal) (LDXRR)
		61 => create_segment(61), -- Opcode 61 runs microcode at address 61 (decimal) (STRR)
		62 => create_segment(62), -- Opcode 62 runs microcode at address 62 (decimal) (STRBR)
		63 => create_segment(63), -- Opcode 63 runs microcode at address 63 (decimal) (STRHR)
		64 => create_segment(64), -- Opcode 64 runs microcode at address 64 (decimal) (STRWR)
		65 => create_segment(65), -- Opcode 65 runs microcode at address 65 (decimal) (STXRR)
		66 => create_segment(66), -- Opcode 66 runs microcode at address 66 (decimal) (LPDP)
		67 => create_segment(67), -- Opcode 67 runs microcode at address 67 (decimal) (LPDP)
		68 => create_segment(68), -- Opcode 68 runs microcode at address 68 (decimal) (LPFLA)
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
			when "11111000010" => return "00000100000"; -- LDR
			when "00111000010" => return "00000100001"; -- LDRB
			when "01111000010" => return "00000100010"; -- LDRH
			when "10111000100" => return "00000100011"; -- LDRSW
			when "11001000010" => return "00000100100"; -- LDXR
			when "11111000000" => return "00000100101"; -- STR
			when "00111000000" => return "00000100110"; -- STRB
			when "01111000000" => return "00000100111"; -- STRH
			when "10111000000" => return "00000101000"; -- STRW
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
			when "11111010010" => return "00000110111"; -- LDRR
			when "00111010010" => return "00000111001"; -- LDRBR
			when "01111010010" => return "00000111010"; -- LDRHR
			when "10011000100" => return "00000111011"; -- LDRSWR
			when "11001010010" => return "00000111100"; -- LDXRR
			when "11111010000" => return "00000111101"; -- STRR
			when "00111010000" => return "00000111110"; -- STRBR
			when "01111010000" => return "00000111111"; -- STRHR
			when "10111010000" => return "00001000000"; -- STRWR
			when "10111010001" => return "00001000001"; -- STXRR
			when "10011110100" => return "00001000010"; -- LPDP
			when "10011010100" => return "00001000011"; -- SPDP
			when "10010110100" => return "00001000100"; -- LPFLA
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