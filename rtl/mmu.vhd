LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE work.FISC_DEFINES.all;

ENTITY MMU IS
	PORT(
		clk     : in  std_logic;
		en      : in  std_logic; -- Is the MMU enabled?
		pdp     : in  std_logic_vector(FISC_INTEGER_SZ-1 downto 0); -- Address of the Paging Directory
		pfla    : out std_logic_vector(FISC_INTEGER_SZ-1 downto 0) := (others => '0'); -- Page Fault Linear Address. Indicates what address caused the page fault
		pfla_wr : out std_logic := '0' -- Write into the PFLA register. If this is 1, then a page fault ocurred, and we must enter exception mode
	);
END MMU;

ARCHITECTURE RTL OF MMU IS
	-- The MMU is implemented on the C side
	attribute foreign : string;
	attribute foreign of rtl : architecture is "mmu_init bin/libvm.dll";
BEGIN
	
END ARCHITECTURE RTL;