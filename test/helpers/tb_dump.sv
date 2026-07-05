module tb_dump;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule
