-- Flat mixed-language wrapper around T65.  T65's DEBUG port is a VHDL record,
-- which cannot be connected portably from SystemVerilog in Quartus 17.

library ieee;
use ieee.std_logic_1164.all;

entity t65_wrapper is
	port (
		clk     : in  std_logic;
		reset_n : in  std_logic;
		enable  : in  std_logic;
		ready   : in  std_logic;
		irq_n   : in  std_logic;
		nmi_n   : in  std_logic;
		data_in : in  std_logic_vector(7 downto 0);
		data_out: out std_logic_vector(7 downto 0);
		address : out std_logic_vector(15 downto 0);
		read_nwrite : out std_logic;
		sync    : out std_logic;
		regs    : out std_logic_vector(63 downto 0)
	);
end entity;

architecture rtl of t65_wrapper is
	signal address_full : std_logic_vector(23 downto 0);
begin
	cpu: entity work.T65
		port map (
			Mode => "00", BCD_en => '1', Res_n => reset_n,
			Enable => enable, Clk => clk, Rdy => ready, Abort_n => '1',
			IRQ_n => irq_n, NMI_n => nmi_n, SO_n => '1',
			R_W_n => read_nwrite, Sync => sync,
			EF => open, MF => open, XF => open, ML_n => open,
			VP_n => open, VDA => open, VPA => open,
			A => address_full, DI => data_in, DO => data_out,
			Regs => regs, DEBUG => open, NMI_ack => open
		);
	address <= address_full(15 downto 0);
end architecture;
