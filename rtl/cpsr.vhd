LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;

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
		cpsr_field     : in  std_logic_vector(4 downto 0)
	);
END CPSR;

ARCHITECTURE RTL OF CPSR IS
	signal cpsr_reg  : std_logic_vector(10 downto 0) := (others => '0');
	
	type spsr_t is array (7 downto 0) of std_logic_vector(10 downto 0); -- Only 6 of these are being used
	signal spsrs : spsr_t := (others => (others => '0'));
	
	signal sreg_mux  : std_logic_vector(10 downto 0);
	
	signal cpsr_or_spsr : std_logic; -- Are we writing / reading to / from the CPSR or the SPSR of the current CPU Mode? (0: CPSR 1: SPSR)
BEGIN
	cpsr_or_spsr   <= cpsr_field(4);
	
	neg_flag_out   <= neg_flag_in   WHEN flags_wr = '1' ELSE cpsr_reg(10);
	zero_flag_out  <= zero_flag_in  WHEN flags_wr = '1' ELSE cpsr_reg(9);
	overf_flag_out <= overf_flag_in WHEN flags_wr = '1' ELSE cpsr_reg(8);
	carry_flag_out <= carry_flag_in WHEN flags_wr = '1' ELSE cpsr_reg(7);
	ae_out         <= cpsr_reg(6);
	pg_out         <= cpsr_reg(5);
	ien_out        <= cpsr_reg(4 downto 3);
	mode_out       <= cpsr_reg(2 downto 0);
	
	sreg_mux       <= cpsr_reg WHEN cpsr_or_spsr = '0' ELSE spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))));
	
	-- CPSR Register reading logic:
	cpsr_rd_out <= 
		sreg_mux                             WHEN cpsr_field(3 downto 0) = "0000" and cpsr_rd = '1' ELSE
		"0000000"    & sreg_mux(10 downto 7) WHEN cpsr_field(3 downto 0) = "0001" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(10)          WHEN cpsr_field(3 downto 0) = "0010" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(9)           WHEN cpsr_field(3 downto 0) = "0011" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(8)           WHEN cpsr_field(3 downto 0) = "0100" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(7)           WHEN cpsr_field(3 downto 0) = "0101" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(6)           WHEN cpsr_field(3 downto 0) = "0110" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(5)           WHEN cpsr_field(3 downto 0) = "0111" and cpsr_rd = '1' ELSE
		"000000000"  & sreg_mux(4 downto 3)  WHEN cpsr_field(3 downto 0) = "1000" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(4)           WHEN cpsr_field(3 downto 0) = "1001" and cpsr_rd = '1' ELSE
		"0000000000" & sreg_mux(4)           WHEN cpsr_field(3 downto 0) = "1010" and cpsr_rd = '1' ELSE
		"00000000"   & sreg_mux(2 downto 0)  WHEN cpsr_field(3 downto 0) = "1011" and cpsr_rd = '1' ELSE
		(others => '0');
	
	-- CPSR Register Behaviour:
	main_proc: 
	process(clk, flags_wr) begin
		if falling_edge(clk) then
			-- Handle Flag Writes by the ALU:
			if flags_wr = '1' then
				cpsr_reg <= neg_flag_in & zero_flag_in & overf_flag_in & carry_flag_in & cpsr_reg(6 downto 0);
			end if;
			
			-- Handle CSPR Writes to specific fields:
			if cpsr_wr = '1' then
				case cpsr_field(3 downto 0) is
					when "0000" => if cpsr_or_spsr = '0' then cpsr_reg              <= cpsr_wr_in;             else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0)))) <= cpsr_wr_in; end if;
					when "0001" => if cpsr_or_spsr = '0' then cpsr_reg(10 downto 7) <= cpsr_wr_in(3 downto 0); else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(10 downto 7) <= cpsr_wr_in(3 downto 0); end if;
					when "0010" => if cpsr_or_spsr = '0' then cpsr_reg(10)          <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(10) <= cpsr_wr_in(0); end if;
					when "0011" => if cpsr_or_spsr = '0' then cpsr_reg(9)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(9)  <= cpsr_wr_in(0); end if;
					when "0100" => if cpsr_or_spsr = '0' then cpsr_reg(8)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(8)  <= cpsr_wr_in(0); end if;
					when "0101" => if cpsr_or_spsr = '0' then cpsr_reg(7)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(7)  <= cpsr_wr_in(0); end if;
					when "0110" => if cpsr_or_spsr = '0' then cpsr_reg(6)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(6)  <= cpsr_wr_in(0); end if;
					when "0111" => if cpsr_or_spsr = '0' then cpsr_reg(5)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(5)  <= cpsr_wr_in(0); end if;
					when "1000" => if cpsr_or_spsr = '0' then cpsr_reg(4 downto 3)  <= cpsr_wr_in(1 downto 0); else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(4 downto 3) <= cpsr_wr_in(1 downto 0); end if;
					when "1001" => if cpsr_or_spsr = '0' then cpsr_reg(4)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(4)  <= cpsr_wr_in(0); end if;
					when "1010" => if cpsr_or_spsr = '0' then cpsr_reg(3)           <= cpsr_wr_in(0);          else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(3)  <= cpsr_wr_in(0); end if;
					when "1011" => if cpsr_or_spsr = '0' then cpsr_reg(2 downto 0)  <= cpsr_wr_in(2 downto 0); else spsrs(to_integer(unsigned(cpsr_reg(2 downto 0))))(2 downto 0) <= cpsr_wr_in(2 downto 0); end if;
					when others => -- TODO: Enter Exception Mode
				end case;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;