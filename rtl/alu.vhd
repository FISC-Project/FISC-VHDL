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
		result : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		neg    : out std_logic := '0'; 
		zero   : out std_logic := '0';
		overf  : out std_logic := '0';
		carry  : out std_logic := '0'
	);
END;

ARCHITECTURE RTL OF ALU IS
	signal result_reg     : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0');
	signal result_reg_ext : std_logic_vector(FISC_INTEGER_SZ downto 0)   := (others => '0');
	signal opA_ext : std_logic_vector(FISC_INTEGER_SZ downto 0)          := (others => '0');
	signal opB_ext : std_logic_vector(FISC_INTEGER_SZ downto 0)          := (others => '0');
BEGIN
	-- TODO: Add MUL, LSL (achieved by multiplying operand by 2^n) and LSR (achieved by dividing operand by 2^n)
	-- TODO: Add DIV
	-- TODO: Add signed and unsigned functionality to every single operation
	
	result_reg <= result_reg_ext(FISC_INTEGER_SZ-1 downto 0);
	
	opA_ext <= opA(FISC_INTEGER_SZ-1) & opA;
	opB_ext <= opB(FISC_INTEGER_SZ-1) & opB;
	
	result_reg_ext <= 
		opA_ext and opB_ext WHEN func = "0000" ELSE -- AND
		opA_ext or opB_ext  WHEN func = "0001" ELSE -- ORR
		opA_ext xor opB_ext WHEN func = "0011" ELSE -- EOR
		opA_ext + opB_ext   WHEN func = "0010" ELSE -- ADD
		opA_ext - opB_ext   WHEN func = "0110" ELSE -- SUB
		opB_ext WHEN func = "0111" ELSE -- pass operand B
		--shift_calculate(opA, opB, '0') WHEN func = "0100" ELSE -- LSL
		--shift_calculate(opA, opB, '1') WHEN func = "0101" ELSE -- LSR
		not (opA_ext or opB_ext) WHEN func =  "1100"; -- NOR

	neg    <= '1' WHEN signed(result_reg) < 0 ELSE '0';
	zero   <= '1' WHEN result_reg_ext(FISC_INTEGER_SZ-1 downto 0) = (FISC_INTEGER_SZ-1 downto 0 => '0') ELSE '0';
	overf  <= '1' WHEN unsigned(result_reg) < 0 ELSE '0';
	carry  <= result_reg_ext(FISC_INTEGER_SZ);
	
	process(result_reg_ext)
	begin
	   if result_reg_ext(FISC_INTEGER_SZ) /= result_reg_ext(FISC_INTEGER_SZ-1) then
	      if result_reg_ext(FISC_INTEGER_SZ) = '1' then
	         result <= ('1', others => '0');
	      else
	         result <= ('0', others => '1');
	      end if;
	   else
	      result <= result_reg_ext(FISC_INTEGER_SZ-1 downto 0);
	   end if;
	end process;
END ARCHITECTURE RTL;