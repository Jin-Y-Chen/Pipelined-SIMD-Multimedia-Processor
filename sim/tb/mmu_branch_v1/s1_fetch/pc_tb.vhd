library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.numeric_var.all;

entity pc_tb is
end entity;

architecture tb of pc_tb is
    signal clk        : std_logic := '0';
    signal enable     : std_logic := '0';
    signal reset_bar  : std_logic := '0';
    signal pc_next    : std_logic_vector(COUNTER_LENGTH-1 downto 0) := (others => '0');
    signal pc_current : std_logic_vector(COUNTER_LENGTH-1 downto 0);
begin

    UUT : entity work.pc
        port map (
            clk        => clk,
            enable     => enable,
            reset_bar  => reset_bar,
            pc_next    => pc_next,
            pc_current => pc_current
        );

    clk_process : process
    begin
        clk <= '0';
        wait for PERIOD / 2;
        clk <= '1';
        wait for PERIOD / 2;
    end process;

    stim : process
        procedure wait_posedge is
        begin
            wait until rising_edge(clk);
            wait for PERIOD / 4; -- sample after registered update
        end procedure;
    begin
        -- async reset clears pc_current without a clock
        reset_bar <= '0';
        enable    <= '0';
        pc_next   <= std_logic_vector(to_unsigned(12, COUNTER_LENGTH));
        wait for PERIOD / 2;
        assert unsigned(pc_current) = 0
            report "Reset failed: pc_current not 0"
            severity error;

        -- hold: enable low, pc_next ignored
        reset_bar <= '1';
        enable    <= '0';
        pc_next   <= std_logic_vector(to_unsigned(5, COUNTER_LENGTH));
        wait_posedge;
        assert unsigned(pc_current) = 0
            report "Hold failed: pc loaded while enable=0"
            severity error;

        -- load on rising edge when enable=1
        enable  <= '1';
        pc_next <= std_logic_vector(to_unsigned(7, COUNTER_LENGTH));
        wait_posedge;
        assert unsigned(pc_current) = 7
            report "Load failed: expected 7"
            severity error;

        -- hold previous value when enable drops
        enable  <= '0';
        pc_next <= std_logic_vector(to_unsigned(20, COUNTER_LENGTH));
        wait_posedge;
        assert unsigned(pc_current) = 7
            report "Hold failed: pc changed while enable=0"
            severity error;

        -- load a new value
        enable  <= '1';
        pc_next <= std_logic_vector(to_unsigned(20, COUNTER_LENGTH));
        wait_posedge;
        assert unsigned(pc_current) = 20
            report "Load failed: expected 20"
            severity error;

        -- sequence of loads
        for i in 0 to 63 loop
            pc_next <= std_logic_vector(to_unsigned(i, COUNTER_LENGTH));
            wait_posedge;
            assert unsigned(pc_current) = to_unsigned(i, COUNTER_LENGTH)
                report "Mismatch at load " & integer'image(i) &
                       ": got " & integer'image(to_integer(unsigned(pc_current)))
                severity error;
        end loop;

        -- async reset while enabled
        pc_next   <= std_logic_vector(to_unsigned(40, COUNTER_LENGTH));
        reset_bar <= '0';
        wait for PERIOD / 4;
        assert unsigned(pc_current) = 0
            report "Async reset failed while enable=1"
            severity error;

        report "PC test completed successfully!" severity note;
        wait;
    end process;

end architecture;
