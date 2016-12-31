LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY CPSR IS
	PORT(
		clk : in std_logic;
		
		-- Flag wires:
		flags_wr       : in  std_logic; -- Flag WR Controlled by the ALU
		neg_flag_in    : in  std_logic;
		zero_flag_in   : in  std_logic;
		overf_flag_in  : in  std_logic;
		carry_flag_in  : in  std_logic;
		neg_flag_out   : out std_logic := '0';
		zero_flag_out  : out std_logic := '0';
		overf_flag_out : out std_logic := '0';
		carry_flag_out : out std_logic := '0';
		
		-- Alignment Wires:
		ae_out         : out std_logic := '0';
		
		-- Paging Wires:
		pg_out         : out std_logic := '0';		
		
		-- Interrupt Masking Wires:
		ien_out        : out std_logic_vector(1 downto 0) := (others => '0');
		
		-- CPU Mode Wires:
		mode_out       : out std_logic_vector(2 downto 0) := (others => '0');
		
		-- WR/RD Busses:
		cpsr_wr        : in  std_logic;
		cpsr_rd        : in  std_logic;
		cpsr_wr_in     : in  std_logic_vector(10 downto 0);
		cpsr_rd_out    : out std_logic_vector(10 downto 0) := (others => '0');
		cpsr_field     : in  std_logic_vector(4 downto 0);
		cpsr_or_spsr   : in  std_logic -- Are we writing / reading to / from the CPSR or the SPSR of the current CPU Mode? (0: CPSR 1: SPSR)
	);
END CPSR;

ARCHITECTURE RTL OF CPSR IS
	signal cpsr_reg  : std_logic_vector(10 downto 0) := (others => '0');
	
	signal spsr1_reg : std_logic_vector(10 downto 0) := (others => '0');
	signal spsr2_reg : std_logic_vector(10 downto 0) := (others => '0');
	signal spsr3_reg : std_logic_vector(10 downto 0) := (others => '0');
	signal spsr4_reg : std_logic_vector(10 downto 0) := (others => '0');
	signal spsr5_reg : std_logic_vector(10 downto 0) := (others => '0');
	signal spsr6_reg : std_logic_vector(10 downto 0) := (others => '0');

BEGIN
	neg_flag_out   <= neg_flag_in   WHEN flags_wr = '1' ELSE cpsr_reg(10);
	zero_flag_out  <= zero_flag_in  WHEN flags_wr = '1' ELSE cpsr_reg(9);
	overf_flag_out <= overf_flag_in WHEN flags_wr = '1' ELSE cpsr_reg(8);
	carry_flag_out <= carry_flag_in WHEN flags_wr = '1' ELSE cpsr_reg(7);
	ae_out         <= cpsr_reg(6);
	pg_out         <= cpsr_reg(5);
	ien_out        <= cpsr_reg(4 downto 3);
	mode_out       <= cpsr_reg(2 downto 0);
	
	-- CPSR Register Behaviour:
	main_proc: 
	process(clk, flags_wr) begin
		if falling_edge(clk) then
			-- Handle Flag Writes by the ALU:
			if flags_wr = '1' then
				cpsr_reg <= neg_flag_in & zero_flag_in & overf_flag_in & carry_flag_in & cpsr_reg(6 downto 0);
			end if;
			
			-- Handle CSPR Reads / Writes from / to specific fields:
			if cpsr_wr = '1' then
				
				case cpsr_field is
					when "00000" => cpsr_reg              <= cpsr_wr_in;
					when "00001" => cpsr_reg(10 downto 7) <= cpsr_wr_in(3 downto 0);
					when "00010" => cpsr_reg(10)          <= cpsr_wr_in(0);
					when "00011" => cpsr_reg(9)           <= cpsr_wr_in(0);
					when "00100" => cpsr_reg(8)           <= cpsr_wr_in(0);
					when "00101" => cpsr_reg(7)           <= cpsr_wr_in(0);
					when "00110" => cpsr_reg(6)           <= cpsr_wr_in(0);
					when "00111" => cpsr_reg(5)           <= cpsr_wr_in(0);
					when "01000" => cpsr_reg(4 downto 3)  <= cpsr_wr_in(1 downto 0);
					when "01001" => cpsr_reg(4)           <= cpsr_wr_in(0);
					when "01010" => cpsr_reg(3)           <= cpsr_wr_in(0);
					when "01011" => cpsr_reg(2 downto 0)  <= cpsr_wr_in(2 downto 0);
					when others => -- TODO: Enter Exception Mode
				end case;
				
			elsif cpsr_rd = '1' then
				
				case cpsr_field is
					when "00000" => cpsr_rd_out             <= cpsr_reg;
					when "00001" => cpsr_rd_out(3 downto 0) <= cpsr_reg(10 downto 7);
					when "00010" => cpsr_rd_out(0)          <= cpsr_reg(10);
					when "00011" => cpsr_rd_out(0)          <= cpsr_reg(9);
					when "00100" => cpsr_rd_out(0)          <= cpsr_reg(8);
					when "00101" => cpsr_rd_out(0)          <= cpsr_reg(7);
					when "00110" => cpsr_rd_out(0)          <= cpsr_reg(6);
					when "00111" => cpsr_rd_out(0)          <= cpsr_reg(5);
					when "01000" => cpsr_rd_out(1 downto 0) <= cpsr_reg(4 downto 3);
					when "01001" => cpsr_rd_out(0)          <= cpsr_reg(4);
					when "01010" => cpsr_rd_out(0)          <= cpsr_reg(3);
					when "01011" => cpsr_rd_out(2 downto 0) <= cpsr_reg(2 downto 0);
					when others => -- TODO: Enter Exception Mode
				end case;
				
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;