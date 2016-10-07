LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY Stage5_Writeback IS
	PORT(
		clk                : in  std_logic;
		val_stage3_execute : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		val_stage4_memacc  : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0);
		memtoreg           : in  std_logic;
		writeback_data     : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0)
	);
END Stage5_Writeback;

ARCHITECTURE RTL OF Stage5_Writeback IS
BEGIN
	process(clk) begin
		if clk'event and clk = '1' then
			-- TODO: Move Writeback pipeline forward
		end if;
	end process;
	
	writeback_data <= val_stage4_memacc WHEN memtoreg = '1' ELSE val_stage3_execute;
END ARCHITECTURE RTL;