LIBRARY IEEE;
USE IEEE.std_logic_1164.all;

ENTITY IO_Controller IS
	PORT(
		clk         : in  std_logic;
		int_en      : out std_logic := '0'; -- Triggered by an external device
		int_id      : out std_logic_vector(7 downto 0) := (others => '0'); -- The ID of the external device which triggered this interrupt
		int_type    : out std_logic_vector(1 downto 0) := (others => '0'); -- Is it an Exception (0) or an IRQ? (1)
		int_ack     : in  std_logic; -- The response of the CPU back into the external device (positive acknowledgement)
		int_ack_id  : in  std_logic_vector(7 downto 0); -- The destination of the acknowledgment given by the CPU to the external device
		ex_enabled  : in  std_logic; -- Are the exceptions enabled?
		int_enabled : in  std_logic  -- Are the interrupts enabled?
	);
END IO_Controller;

ARCHITECTURE RTL OF IO_Controller IS
	-- The IO Controller is implemented on the C side
	attribute foreign : string;
	attribute foreign of rtl : architecture is "io_controller_init_vhd bin/libvm.dll";
BEGIN

END ARCHITECTURE RTL;