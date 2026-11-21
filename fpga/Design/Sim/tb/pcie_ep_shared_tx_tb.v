`timescale 1ns/1ps

module pcie_ep_shared_tx_tb;
    reg clk = 0, rst = 1, tx_wait = 1;
    reg [47:0] rx_bar = 0;
    reg [511:0] rx_data = 0;
    reg rx_sop = 0, rx_eop = 0;
    reg [15:0] rx_valid = 0;
    reg [511:0] held;
    integer completions = 0;

    always #5 clk = ~clk;
    ph2_pcie_ep_top dut();

    initial begin
        force dut.tl_clk_user = clk;
        force dut.tl_rst_user = rst;
        force dut.tl_rx_bardec = rx_bar;
        force dut.tl_rx_data = rx_data;
        force dut.tl_rx_sop = rx_sop;
        force dut.tl_rx_eop = rx_eop;
        force dut.tl_rx_valid = rx_valid;
        force dut.tl_rx_err = 8'd0;
        force dut.tl_rx_mchit = 12'd0;
        force dut.tl_tx_wait = tx_wait;
        force dut.tl_tx_credits = 96'd0;
        force dut.tl_cfg_busdev = 13'h008;
        force dut.tl_cfg_pfregs_cmd = 16'd4;
        force dut.pl_link_up = 1'b1;
        force dut.tl_cfg_current_link_speed = 3'd2;
        force dut.tl_cfg_negotiated_width = 4'd4;
        force dut.tl_cfg_max_payload_size = 3'd0;
    end

    task send_bar0_write;
        begin
            @(negedge clk);
            rx_bar = 48'h1;
            rx_data = 0;
            rx_data[511:509] = 3'b010;
            rx_data[489:480] = 10'd1;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = 32'hfe80_0000;
            rx_data[415:384] = 32'h1234_5678;
            rx_sop = 1; rx_eop = 1; rx_valid = 16'hf000;
            @(negedge clk);
            rx_bar = 0; rx_sop = 0; rx_eop = 0; rx_valid = 0;
        end
    endtask

    task send_read;
        input [47:0] bar;
        input [31:0] address;
        input [7:0] tag;
        begin
            @(negedge clk);
            rx_bar = bar;
            rx_data = 0;
            rx_data[511:509] = 3'b000;
            rx_data[489:480] = 10'd1;
            rx_data[479:464] = 16'h1234;
            rx_data[463:456] = tag;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = address;
            rx_sop = 1; rx_eop = 1; rx_valid = 16'he000;
            do @(posedge clk); while (dut.tl_rx_wait);
            @(negedge clk);
            rx_bar = 0; rx_sop = 0; rx_eop = 0; rx_valid = 0;
        end
    endtask

    task send_bar2_pattern_write;
        begin
            @(negedge clk);
            rx_bar = 48'h4;
            rx_data = 0;
            rx_data[511:509] = 3'b010;
            rx_data[489:480] = 10'd1;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = 32'hfe90_000c;
            rx_data[415:384] = 32'h0500_0000;
            rx_sop = 1; rx_eop = 1; rx_valid = 16'hf000;
            @(negedge clk);
            rx_bar = 0; rx_sop = 0; rx_eop = 0; rx_valid = 0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst && dut.tl_tx_sop && dut.tl_tx_valid[15] && !tx_wait) begin
            case (completions)
                0: if (dut.tl_tx_data[431:424] !== 8'h11 ||
                       dut.tl_tx_data[447:432] !== 16'h1234 ||
                       dut.tl_tx_data[415:384] !== 32'h1234_5678)
                       $fatal(1, "BAR0 completion was corrupted");
                1: if (dut.tl_tx_data[431:424] !== 8'h22 ||
                       dut.tl_tx_data[447:432] !== 16'h1234 ||
                       dut.tl_tx_data[415:384] !== 32'h0100_0100)
                       $fatal(1, "BAR2 completion was corrupted");
                2: if (dut.tl_tx_data[431:424] !== 8'h33 ||
                       dut.tl_tx_data[415:384] !== 32'h1234_5678)
                       $fatal(1, "first consecutive BAR0 read corrupted");
                3: if (dut.tl_tx_data[431:424] !== 8'h44 ||
                       dut.tl_tx_data[415:384] !== 32'h1234_5678)
                       $fatal(1, "second consecutive BAR0 read corrupted");
                4: if (dut.tl_tx_data[431:424] !== 8'h55 ||
                       dut.tl_tx_data[415:384] !== 32'h0500_0000)
                       $fatal(1, "BAR2 write/readback corrupted");
                default: $fatal(1, "unexpected completion");
            endcase
            completions = completions + 1;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        send_bar0_write();
        repeat (8) @(negedge clk);
        send_read(48'h1, 32'hfe80_0000, 8'h11);
        wait (dut.tl_tx_sop);
        held = dut.tl_tx_data;
        send_read(48'h4, 32'hfe90_0000, 8'h22);
        repeat (4) begin
            @(negedge clk);
            if (!dut.tl_tx_sop || dut.tl_tx_data !== held)
                $fatal(1, "shared TX changed while stalled");
        end
        tx_wait = 0;
        wait (completions == 2);
        @(negedge clk);
        tx_wait = 1;
        send_read(48'h1, 32'hfe80_0000, 8'h33);
        wait (dut.tl_tx_sop);
        fork
            begin
                send_read(48'h1, 32'hfe80_0400, 8'h44);
            end
            begin
                repeat (4) @(negedge clk);
                if (!dut.tl_rx_wait)
                    $fatal(1, "second BAR0 request was not backpressured");
                tx_wait = 0;
            end
        join
        wait (completions == 4);
        send_bar2_pattern_write();
        send_read(48'h4, 32'hfe90_000c, 8'h55);
        wait (completions == 5);
        $display("PASS: BAR0 and BAR2 completions share stalled TX safely");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "shared TX test timed out");
    end
endmodule
