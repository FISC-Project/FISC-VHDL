LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

PACKAGE FISC IS
	---------- FISC ISA DEFINES -----------
	constant FISC_INSTRUCTION_WIDTH : integer := 32; -- Each instruction is 32 bits wide
	constant FISC_INTEGER_SZ : integer := 64; -- Each integer value is 64 bits wide
	
	constant R_FMT_OPCODE_SZ : integer := 11; -- The opcode is composed of 11 bits (maximum)
	---------------------------------------
	
	---------- MICROCODE DEFINES ----------
	constant MICROCODE_CTRL_WIDTH : integer := 32; -- The width of the control bus that will be connected to the pipeline
	COMPONENT Microcode
		PORT(
			clk : in std_logic; -- Clock signal
			sos : in std_logic; -- Start of segment flag (triggers on rising edge)
			microcode_opcode : in std_logic_vector(R_FMT_OPCODE_SZ-1 downto 0); -- Microcode's Opcode input to the FSM
			microcode_ctrl   : out std_logic_vector(MICROCODE_CTRL_WIDTH-1 downto 0) -- Result of indexing Microcode's memory with the opcode input
		);
	END COMPONENT;
	---------------------------------------
	
	---------- MICROARCHITECTURE: STAGE 1 - FETCH DEFINES -----------
	COMPONENT Stage1_Fetch IS
		PORT(
			--new_pc : in std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
			--reset  : in std_logic;
			fsm_next: in std_logic := '0'
			--branch_flag : in std_logic;
			--uncond_branch_flag : in std_logic;
			--zero_flag : in std_logic
		);
	END COMPONENT;
	-----------------------------------------------------------------
	
	---------- MICROARCHITECTURE: STAGE 2 - DECODE DEFINES ----------
	COMPONENT Stage2_Decode IS
		PORT(
			clk: in std_logic := '0'
		);
	END COMPONENT;
	-----------------------------------------------------------------
END FISC;