-- Instruction BRAM matching Xilinx blk_mem_gen_0 (see blk_mem_gen_0.vho).
-- Inferred single-port RAM for synthesis and xsim.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.numeric_var.all;

entity blk_mem_gen_0 is
    port (
        clka      : in  std_logic;
        rsta      : in  std_logic;
        wea       : in  std_logic_vector(0 downto 0);
        addra     : in  std_logic_vector(COUNTER_LENGTH-1 downto 0);
        dina      : in  std_logic_vector(INSTRUCTION_LENGTH-1 downto 0);
        douta     : out std_logic_vector(INSTRUCTION_LENGTH-1 downto 0);
        rsta_busy : out std_logic
    );
end entity;

architecture blk_mem_gen_0_arch of blk_mem_gen_0 is
    type ram_t is array (0 to INSTRUCTION_HEIGHT-1) of std_logic_vector(INSTRUCTION_LENGTH-1 downto 0);
    signal mem    : ram_t := (others => (others => '0'));
    signal dout_q : std_logic_vector(INSTRUCTION_LENGTH-1 downto 0) := (others => '0');
begin
    process (clka)
    begin
        if rising_edge(clka) then
            if rsta = '1' then
                dout_q <= (others => '0');
            else
                if wea(0) = '1' then
                    mem(to_integer(unsigned(addra))) <= dina;
                end if;
                dout_q <= mem(to_integer(unsigned(addra)));
            end if;
        end if;
    end process;

    douta     <= dout_q;
    rsta_busy <= rsta;
end architecture;
