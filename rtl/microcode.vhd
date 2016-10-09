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
		return "00000000000000000000000000000000" & "00" & control & is_eos; -- FORMAT: MCU_FUNC | SEG_TYPE | IS EOS | CONTROL BITS
	end;
	
	function create_segment (
		segment_ptr : integer
	) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(segment_ptr, MICROCODE_SEGMENT_MAXCOUNT_ENC+1));
	end;
	
	-----------------------------------------------------------------------------------------------------------------------
	-- IMPORTANT: Fill up microcode execute memory (which is segmented) here: (ARGS: control bits | is end of segment) --
	signal code : code_t := (
		0 => microinstr("0000000000000000000000000000000", '1'), -- NULL INSTRUCTION
		1 => microinstr("0000000000000000000000000000010", '1'), -- Instruction ADD
		2 => microinstr("0000000000000000000000000000101", '1'), -- Instruction ADDI
		-- END OF MICROCODE MEMORY --
		others => (others => '0')
	);
	-----------------------------------------------------------------------------------------------------------------------
	---------------------------------------------
	-- IMPORTANT: Fill up segment memory here: -- (NOTE: The index below IS the opcode that will be associated)
	signal seg_start : seg_t := (
		0 => create_segment(1), -- Opcode 0 runs microcode at address 1 (decimal)
		1 => create_segment(2), -- Opcode 1 runs microcode at address 2 (decimal)
		2 => create_segment(3), -- Opcode 2 runs microcode at address 3 (decimal)
		3 => create_segment(2), -- Opcode 3 runs microcode at address 2 (decimal)
		-- END OF SEGMENT MEMORY --
		others => (others => '0')
	);
	---------------------------------------------
	
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
			when "11010010100" => return "00000011001"; -- MOVZ
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
			when others => -- Do nothing here
		end case;
		
		-- Cover the 10 bit opcodes:
		case isa_opcode(10 downto 1) is
			when "1001000100" => return "00000000010"; -- ADDI
			when "1000101100" => return "00000000011"; -- ADDIS
			when "1101000100" => return "00000000110"; -- SUBI
			when "1111000100" => return "00000000111"; -- SUBIS
			when "1001001000" => return "00000001111"; -- ANDI
			when "1111001000" => return "00000010000"; -- ANDIS
			when "1011001000" => return "00000010011"; -- ORRI
			when "1101001000" => return "00000010101"; -- EORI
			when others => -- Do nothing here
		end case;
		
		-- Cover the 8 bit opcodes:
		case isa_opcode(10 downto 3) is
			when "01010100" => return "00000011011"; -- B.cond
			when "10110101" => return "00000011110"; -- CBNZ
			when "10110100" => return "00000011111"; -- CBZ
			when others => -- Do nothing here
		end case;
		
		-- Cover the 6 bit opcodes:
		case isa_opcode(10 downto 5) is
			when "000101" => return "00000011010"; -- B
			when "100101" => return "00000011100"; -- BL
			when others => -- Do nothing here
		end case;
		
		-- Return NULL opcode:	
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
	
	-------- SYSTEM PROCESSES --------
	process(clk)
		variable code_ip_tmp : std_logic_vector(MICROCODE_CTRL_DEPTH_ENC downto 0) := (others => '0');
	begin
		if clk'event and clk = '1' then
			-- Check for invalid/halt opcode:
			check_microcode_running(microunit_running);
			if microunit_running = '1' and code_ip /= (code_ip'range => '1') and sos = '0' and microunit_init = '1' then
				-- Check flags first:
				if flag_jmp = '1' then
					if flag_jmp_addr /= (flag_jmp_addr'range => 'U') then
						code_ip <= flag_jmp_addr;
						flag_jmp <= '0';
					end if;
				else
					-- Check if we reached End of Segment:
					if eos = '1' then
						-- We need to pop the stack:
						pop_stack(flag_jmp_addr, flag_jmp, call_stack, stack_ptr);
					else
						if code_ip /= (code_ip'range => 'U') then
							if code(to_integer(unsigned(code_ip)))(0) /= '1' then
								-- Otherwise continue sequential execution:
								code_ip <= code_ip + "1";
							--else
							--	code_ip <= (others => '1');
							--	ctrl_reg(0) <= '1';
							end if;
						end if;
					end if;
				end if;
				-- Execute microinstruction:
				exec_microinstruction(code_ip, flag_jmp_addr, flag_jmp, call_stack, stack_ptr, ctrl_reg);
			else
				-- Microcode unit is frozen. Needs to be restarted
			end if;
			
			if sos = '1' then
				-- Check for invalid/halt opcode:
				check_microcode_running(microunit_running);
				microunit_init <= '1';
				-- Jump to segment before fetching control:
				if microunit_running = '1' then
					code_ip_tmp := seg_start(to_integer(unsigned(OPCODE_TO_MICROCODE_OPCODE(microcode_opcode))));
					if code_ip_tmp /= (code_ip_tmp'range => 'U') then
						code_ip <= code_ip_tmp;
						-- Execute microinstruction:
						exec_microinstruction(code_ip, flag_jmp_addr, flag_jmp, call_stack, stack_ptr, ctrl_reg);
					end if;
				end if;
			end if;
		end if;
	end process;
	----------------------------------
END ARCHITECTURE RTL;