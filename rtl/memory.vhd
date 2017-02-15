LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY Memory IS
	PORT(
		clk            : in  std_logic;
		en             : in  std_logic_vector(1 downto 0);
		wr             : in  std_logic;
		rd             : in  std_logic_vector(1 downto 0);
		ready          : out std_logic_vector(1 downto 0) := (others => '0');
		address1       : in  std_logic_vector(22 downto 0);
		address2       : in  std_logic_vector(22 downto 0);
		data_in        : in  std_logic_vector(63 downto 0);
		data_out1      : out std_logic_vector(63 downto 0);
		data_out2      : out std_logic_vector(63 downto 0);
		access_width   : in  std_logic_vector(1 downto 0); -- 64/8/16/32 bits
		alignment_flag : in  std_logic
	);
END Memory;

ARCHITECTURE RTL OF Memory IS
	-- The Memory is implemented on the C side
	attribute foreign : string;
	attribute foreign of rtl : architecture is "memory_init bin/libvm.dll";
BEGIN
	
END ARCHITECTURE RTL;