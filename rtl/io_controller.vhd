LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY IO_Controller IS
	PORT(
		clk      : in  std_logic;
		int_en   : out std_logic := '0';
		int_id   : out std_logic_vector(7 downto 0) := (others => '0');
		int_type : out std_logic_vector(1 downto 0) := (others => '0');
		int_ack  : in  std_logic
	);
END IO_Controller;

ARCHITECTURE RTL OF IO_Controller IS
	-- The IO Controller is implemented on the C side
	attribute foreign : string;
	attribute foreign of rtl : architecture is "io_controller_init_vhd bin/libvm.dll";
BEGIN

END ARCHITECTURE RTL;