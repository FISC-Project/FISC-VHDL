LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

entity testc is
	port(
		clk : in boolean
	);
end;

architecture rtl of testc is
	attribute foreign : string;
	attribute foreign of rtl : architecture is "test_init bin/libvm.dll";
begin
end architecture rtl;