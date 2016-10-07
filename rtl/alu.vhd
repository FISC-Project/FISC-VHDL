LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY ALU IS
	PORT(
		clk    : in  std_logic;
		opA    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		opB    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		func   : in  std_logic_vector(3 downto 0);
		zero   : out std_logic;
		result : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	);
END;

ARCHITECTURE RTL OF ALU IS
	signal result_reg : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
BEGIN
	process(clk) begin
		if clk'event and clk = '1' then
			case func is
			when "0000" => result_reg <= opA and opB;
			when "0001" => result_reg <= opA or opB;
			when "0010" => result_reg <= opA - opB;
			when "0111" => 
				if opA < opB then
					result_reg <= (FISC_INTEGER_SZ-2 downto 0 => '0') & "1";
				else
					result_reg <= (others => '0');
				end if;	
			when "1100" => result_reg <= not (opA or opB);
			when others => result_reg <= result_reg;
			end case;
		end if;
	end process;
	
	result <= result_reg;
	zero   <= '1' WHEN result_reg = (result_reg'range => '0') ELSE '0';
END ARCHITECTURE RTL;