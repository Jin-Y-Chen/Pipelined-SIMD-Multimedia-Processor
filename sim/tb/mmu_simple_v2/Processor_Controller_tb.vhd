library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity Processor_Controller_tb is
end entity;

architecture sim of Processor_Controller_tb is

    constant COUNTER_LENGTH     : integer := 6;
    constant INSTRUCTION_LENGTH : integer := 25;
    constant INSTRUCTION_HEIGHT : integer := 64;
    constant REGISTER_HEIGHT    : integer := 32;

    constant CLK_FREQ    : integer := 100000000;
    constant BAUD_RATE   : integer := 921600;
    constant CLK_PERIOD  : time := 20 ns;
    constant BAUD_PERIOD : time := (CLK_FREQ / BAUD_RATE) * CLK_PERIOD;

    signal clk       : std_logic := '0';
    signal rst_bar   : std_logic := '0';
    signal enable    : std_logic := '0';

    signal rx        : std_logic := '1';
    signal loaded    : std_logic := '0';
    signal uart      : std_logic;
    signal cpu       : std_logic;

    signal reg_pos   : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_tog   : std_logic := '0';
    signal reg_value : std_logic_vector(15 downto 0);

    procedure uart_send_byte(
        signal rx_line : out std_logic;
        data : std_logic_vector(7 downto 0)
    ) is
    begin
        rx_line <= '0';
        wait for BAUD_PERIOD;

        for i in 0 to 7 loop
            rx_line <= data(i);
            wait for BAUD_PERIOD;
        end loop;

        rx_line <= '1';
        wait for BAUD_PERIOD;
    end procedure;

    procedure uart_send_instruction(
        signal rx_line : out std_logic;
        inst : std_logic_vector(24 downto 0)
    ) is
        variable full32 : std_logic_vector(31 downto 0);
    begin
        full32 := "0000000" & inst;
        uart_send_byte(rx_line, full32(31 downto 24));
        uart_send_byte(rx_line, full32(23 downto 16));
        uart_send_byte(rx_line, full32(15 downto 8));
        uart_send_byte(rx_line, full32(7 downto 0));
    end procedure;

    type inst_array is array (0 to 4) of std_logic_vector(24 downto 0);
    constant program : inst_array := (
        "1100000000000000000000000",
        "1100000000000000000000000",
        "0001011111111111111100001",
        "0011011111111111111100001",
        "0000000000000000000000000"
    );

begin

    DUT : entity work.Processor_Controller(structural)
        port map (
            clk       => clk,
            rst_bar   => rst_bar,
            enable    => enable,
            rx        => rx,
            loaded    => loaded,
            uart      => uart,
            cpu       => cpu,
            reg_pos   => reg_pos,
            reg_tog   => reg_tog,
            reg_value => reg_value
        );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    stim_proc : process
    begin
        rst_bar <= '0';
        enable  <= '0';
        rx      <= '1';
        wait for 10 * CLK_PERIOD;

        rst_bar <= '1';
        wait for 10 * CLK_PERIOD;

        enable <= '1';
        wait for 10 * CLK_PERIOD;

        for i in 0 to 4 loop
            uart_send_instruction(rx, program(i));
        end loop;

        wait;
    end process;

    dump_mem : process
        file     mem_out : text;
        variable L       : line;
        variable reg_idx : integer;
        variable seg_idx : integer;
    begin
        wait until loaded = '1';
        wait for CLK_PERIOD * INSTRUCTION_HEIGHT;

        file_open(mem_out, "../internal/register_file.txt", write_mode);

        for reg_idx in 0 to REGISTER_HEIGHT - 1 loop
            L := null;
            for seg_idx in 7 downto 0 loop
                reg_pos <= std_logic_vector(to_unsigned(reg_idx, 5)) &
                           std_logic_vector(to_unsigned(seg_idx, 3));
                reg_tog <= '1';
                wait for CLK_PERIOD;
                reg_tog <= '0';
                wait for CLK_PERIOD;
                write(L, reg_value);
                write(L, string'(" "));
            end loop;
            writeline(mem_out, L);
        end loop;

        file_close(mem_out);
        report "Processor_Controller_tb: register dump complete" severity note;
        wait;
    end process;

end architecture;
