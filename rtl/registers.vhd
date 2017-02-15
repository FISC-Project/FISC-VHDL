LIBRARY IEEE;
USE IEEE.math_real.all;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_unsigned.all;
USE work.FISC_DEFINES.all;

ENTITY RegFile IS
	PORT(
		clk           : in  std_logic;
		readreg1      : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		readreg2      : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		writereg      : in  std_logic_vector(integer(ceil(log2(real(FISC_REGISTER_COUNT)))) - 1 downto 0);
		writedata     : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		outA          : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		outB          : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		regwr         : in  std_logic;
		current_pc    : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		ifid_opcode   : in  std_logic_vector(10 downto 0);
		opcode        : in  std_logic_vector(10 downto 0);
		mov_quadrant  : in  std_logic_vector(1 downto 0);
		ivp_out       : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		evp_out       : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	);
END RegFile;

ARCHITECTURE RTL OF RegFile IS
	-- Regular 64-bit registers:
	type regfile_t is array (0 to FISC_REGISTER_COUNT-1) of std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
	signal regfile : regfile_t := (others => (others => '0'));
	
	-- Special Registers:
	signal esr  : std_logic_vector(7 downto 0)                 := (others => '0'); -- Exception Syndrome Register
	-- The ELR register is declared on the file stage1_fetch.vhd
	signal ivp  : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Interrupt Vector Pointer
	signal evp  : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Exception Vector Pointer
	signal pdp  : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Page Directory Pointer
	signal pfla : std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Page Fault Linear Address
BEGIN
	outA <= (outA'range => '0') WHEN (readreg1 = "11111" or opcode(10 downto 2) = "111100101" or opcode(10 downto 2) = "110100101") ELSE regfile(to_integer(unsigned(readreg1)));
	outB <= (outB'range => '0') WHEN  readreg2 = "11111" ELSE regfile(to_integer(unsigned(readreg2)));
	
	ivp_out <= ivp;
	evp_out <= evp;
	
	----------------
	-- Behaviour: --
	----------------
	main_proc: process(clk, regwr) begin
		if rising_edge(clk) and regwr = '1' then		
			if opcode(10 downto 2) = "111100101" then
				-- Execute MOVK:
				case mov_quadrant is
					when "00" => regfile(to_integer(unsigned(writereg))) <= regfile(to_integer(unsigned(writereg)))(63 downto 16) & writedata(15 downto 0);
					when "01" => regfile(to_integer(unsigned(writereg))) <= regfile(to_integer(unsigned(writereg)))(63 downto 32) & writedata(15 downto 0) & regfile(to_integer(unsigned(writereg)))(15 downto 0);
					when "10" => regfile(to_integer(unsigned(writereg))) <= regfile(to_integer(unsigned(writereg)))(63 downto 48) & writedata(15 downto 0) & regfile(to_integer(unsigned(writereg)))(31 downto 0);
					when "11" => regfile(to_integer(unsigned(writereg))) <= writedata(15 downto 0) & regfile(to_integer(unsigned(writereg)))(47 downto 0);
					when others =>
				end case;
			elsif opcode(10 downto 2) = "110100101" then
				-- Execute MOVZ:
				case mov_quadrant is
					when "00" => 
						regfile(to_integer(unsigned(writereg)))(15 downto 0)  <= writedata(15 downto 0);
						regfile(to_integer(unsigned(writereg)))(63 downto 16) <= (others => '0');
					when "01" =>
						regfile(to_integer(unsigned(writereg)))(15 downto 0)  <= (others => '0');
						regfile(to_integer(unsigned(writereg)))(31 downto 16) <= writedata(15 downto 0);
						regfile(to_integer(unsigned(writereg)))(63 downto 32) <= (others => '0');
					when "10" => 
						regfile(to_integer(unsigned(writereg)))(31 downto 0)  <= (others => '0');
						regfile(to_integer(unsigned(writereg)))(47 downto 32) <= writedata(15 downto 0);
						regfile(to_integer(unsigned(writereg)))(63 downto 48) <= (others => '0');
					when "11" =>
						regfile(to_integer(unsigned(writereg)))(47 downto 0)  <= (others => '0');
						regfile(to_integer(unsigned(writereg)))(63 downto 48) <= writedata(15 downto 0);
					when others =>
				end case;
			elsif opcode(10 downto 5) = "100101" then
				-- Link PC to register 30 (store return address):
				regfile(30) <= writedata;
			elsif ifid_opcode = "10101000100" then
				-- Execute LDPC:
				regfile(30) <= std_logic_vector(uns(current_pc) + uns("100"));
			elsif ifid_opcode = "10111010100" then
				-- Execute LIVP:
				ivp <= regfile(to_integer(unsigned(writereg)));
			elsif ifid_opcode = "10110110100" then
				-- Execute SIVP:
				regfile(to_integer(unsigned(writereg))) <= ivp;
			elsif ifid_opcode = "10110010100" then
				-- Execute LEVP:
				evp <= regfile(to_integer(unsigned(writereg)));
			elsif ifid_opcode = "10101110100" then
				-- Execute SEVP:
				regfile(to_integer(unsigned(writereg))) <= evp;
			elsif ifid_opcode = "10101010100" then
				-- Execute SESR:
				regfile(to_integer(unsigned(writereg)))(7 downto 0) <= esr;
			else				
				-- Write normally to the register:
				regfile(to_integer(unsigned(writereg))) <= writedata;
			end if;
		end if;
	end process;
END ARCHITECTURE RTL;