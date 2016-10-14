LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY Flags IS
	PORT(
		clk            : in std_logic;
		flag_wr        : in std_logic;
		neg_flag_in    : in std_logic;
		zero_flag_in   : in std_logic;
		overf_flag_in  : in std_logic;
		carry_flag_in  : in std_logic;
		neg_flag_out   : out std_logic := '0';
		zero_flag_out  : out std_logic := '0';
		overf_flag_out : out std_logic := '0';
		carry_flag_out : out std_logic := '0'
	);
END;

ARCHITECTURE RTL OF Flags IS
	signal neg_flag_reg   : std_logic := '0';
	signal zero_flag_reg  : std_logic := '0';
	signal overf_flag_reg : std_logic := '0';
	signal carry_flag_reg : std_logic := '0';
BEGIN
	neg_flag_out   <= neg_flag_in   WHEN flag_wr = '1' ELSE neg_flag_reg;
	zero_flag_out  <= zero_flag_in  WHEN flag_wr = '1' ELSE zero_flag_reg;
	overf_flag_out <= overf_flag_in WHEN flag_wr = '1' ELSE overf_flag_reg;
	carry_flag_out <= carry_flag_in WHEN flag_wr = '1' ELSE carry_flag_reg;

	process(clk) begin
		if clk'event and clk = '1' and flag_wr = '1' then
			neg_flag_reg   <= neg_flag_in;
			zero_flag_reg  <= zero_flag_in;
			overf_flag_reg <= overf_flag_in;
			carry_flag_reg <= carry_flag_in;
		end if;
	end process;
END ARCHITECTURE RTL;