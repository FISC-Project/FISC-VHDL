LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

ENTITY FLASHMEM_Controller_tb IS
	PORT(
		CLK       : in  std_logic;
		FLASH_CS  : out std_logic; -- /SS (Drive)
		FLASH_DO  : in  std_logic; -- MISO (Read)
		FLASH_WP  : out std_logic;
		FLASH_CLK : out std_logic; -- SCK (Drive)
		FLASH_DI  : out std_logic; -- MOSI (Drive)
		DS_DP     : out std_logic;
		DS_G      : out std_logic;
		DS_C      : out std_logic;
		DS_D      : out std_logic
	);
END FLASHMEM_Controller_tb;

ARCHITECTURE RTL OF FLASHMEM_Controller_tb IS
	signal z    : boolean := false;
	signal leds : std_logic_vector(3 downto 0) := (others => '0');
	
	signal flash_mem_ctrl_reset : std_logic := '0';
	signal flash_mem_ctrl_reset_done : std_logic;
	
	type fsm_t is (
		s_reset,
		s_reset_done,
		s_idle
	);
	signal state : fsm_t := s_reset;
	
--	signal CLK       : std_logic := '0';
--	signal FLASH_CS  : std_logic; -- /SS (Drive)
--	signal FLASH_DO  : std_logic := '0'; -- MISO (Read)
--	signal FLASH_WP  : std_logic := '1';
--	signal FLASH_CLK : std_logic; -- SCK (Drive)
--	signal FLASH_DI  : std_logic; -- MOSI (Drive)
BEGIN
	--CLK <= '1' AFTER 1 ps WHEN CLK = '0' ELSE '0' AFTER 1 ps WHEN CLK = '1';

	(DS_D, DS_C, DS_G, DS_DP) <= not leds;
	
	FLASH_WP <= '1'; -- We don't want to mess with Write Protection

	FLASHMEM_Controller1: ENTITY work.FLASHMEM_Controller PORT MAP(
		CLK, flash_mem_ctrl_reset, flash_mem_ctrl_reset_done, 
		FLASH_CS, FLASH_DO, FLASH_DI, FLASH_CLK, 
		leds
	);
	
	main_proc: process(CLK) begin
		if rising_edge(CLK) then
			case state is
				when s_reset =>
					flash_mem_ctrl_reset <= '1';
					state <= s_reset_done;
					
				when s_reset_done =>
					flash_mem_ctrl_reset <= '0';
					if flash_mem_ctrl_reset_done = '1' then
						state <= s_idle;
					end if;
					
				when s_idle => -- Do nothing
				when others => state <= s_idle;
			end case;
		end if;
	end process;
	
END ARCHITECTURE RTL;