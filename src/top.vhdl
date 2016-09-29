library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
	port(CLK : in std_logic; DS_G : out std_logic);
end top;

architecture rtl of top is
	constant CLK_FREQ : integer := 50000000;
	constant BLINK_FREQ : integer := 1;
	constant CNT_MAX : integer := CLK_FREQ / BLINK_FREQ / 2 - 1;

	signal cnt : unsigned(24 downto 0);
	signal blink : std_logic;
begin
	process(CLK)
	begin
		if rising_edge(CLK) then
			if cnt = CNT_MAX then
				cnt <= (others => '0');
				blink <= not blink;
			else
				cnt <= cnt + 1;
			end if;
		end if;
	end process;
	DS_G <= blink;
end rtl;