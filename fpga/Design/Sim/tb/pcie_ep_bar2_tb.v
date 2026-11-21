`timescale 1ns/1ps

module pcie_ep_bar2_tb;
    reg clk = 0, rst = 1, tx_wait = 1;
    reg [47:0] bardec = 0;
    reg [511:0] rx_data = 0;
    reg sop = 0, eop = 0;
    reg [15:0] valid = 0;
    wire rx_wait;
    wire [511:0] tx_data;
    wire tx_sop, tx_eop;
    wire [15:0] tx_valid;
    reg [511:0] held;
    integer completed = 0;

    always #5 clk = ~clk;

    pcie_ep_image_dma #(.FRAME_BYTES(80), .FRAME_PERIOD_CYCLES(500)) dut (
        .tl_clk_user(clk), .tl_rst_user(rst), .tl_rx_bardec(bardec),
        .tl_rx_data(rx_data), .tl_rx_sop(sop), .tl_rx_eop(eop),
        .tl_rx_valid(valid), .tl_rx_err(8'd0), .tl_rx_wait(rx_wait),
        .tl_cfg_busdev(13'h008), .tl_cfg_pfregs_cmd(16'h0004),
        .tl_cfg_current_link_speed(3'd2), .tl_cfg_negotiated_width(4'd4),
        .tl_cfg_max_payload_size(3'd0), .pl_link_up(1'b1),
        .tl_tx_credits(96'd0), .tl_tx_wait(tx_wait), .tl_tx_data(tx_data),
        .tl_tx_eop(tx_eop), .tl_tx_err(), .tl_tx_sop(tx_sop),
        .tl_tx_stream(), .tl_tx_valid(tx_valid), .irq_pending()
    );

    task drive_read;
        input [7:0] tag;
        input [3:0] be;
        input [9:0] length;
        begin
            bardec = 48'h4;
            rx_data = 0;
            rx_data[511:509] = 3'b000;
            rx_data[502:500] = 3'd3;
            rx_data[498] = 1'b1;
            rx_data[493:492] = 2'b10;
            rx_data[489:480] = length;
            rx_data[479:464] = 16'h1234;
            rx_data[463:456] = tag;
            rx_data[451:448] = be;
            rx_data[447:416] = 32'hfe90_0000;
            sop = 1;
            eop = 1;
            valid = 16'he000;
        end
    endtask

    always @(posedge clk) begin
        if (!rst && tx_valid != 0 && !tx_wait) begin
            if (!tx_sop || !tx_eop || tx_data[447:432] !== 16'h1234 ||
                tx_data[502:500] !== 3'd3 || tx_data[498] !== 1'b1 ||
                tx_data[493:492] !== 2'b10) begin
                $display("FAIL: completion header %h", tx_data[511:416]);
                $fatal(1);
            end
            case (completed)
                0: if (tx_valid !== 16'hf000 || tx_data[431:424] !== 8'h41 ||
                       tx_data[459:448] !== 12'd4 ||
                       tx_data[415:384] !== 32'h0100_0100) $fatal(1, "first read");
                1: if (tx_valid !== 16'hf000 || tx_data[431:424] !== 8'h42 ||
                       tx_data[459:448] !== 12'd2 ||
                       tx_data[422:416] !== 7'd2 ||
                       tx_data[415:384] !== 32'h0100_0100) $fatal(1, "second read");
                2: if (tx_valid !== 16'he000 || tx_data[511:509] !== 3'b000 ||
                       tx_data[463:461] !== 3'b001 ||
                       tx_data[489:480] !== 10'd0 ||
                       tx_data[431:424] !== 8'h43) $fatal(1, "unsupported read");
                3: if (tx_data[431:424] !== 8'h44 ||
                       tx_data[459:448] !== 12'd3 ||
                       tx_data[422:416] !== 7'd0) $fatal(1, "sparse byte enables");
                4: if (tx_data[431:424] !== 8'h45 ||
                       tx_data[459:448] !== 12'd1 ||
                       tx_data[422:416] !== 7'd0) $fatal(1, "zero byte enable");
                default: $fatal(1, "duplicate completion");
            endcase
            completed = completed + 1;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        drive_read(8'h41, 4'hf, 10'd1);
        @(negedge clk);
        drive_read(8'h42, 4'hc, 10'd1);
        if (!rx_wait) $fatal(1, "second read not backpressured");
        wait (tx_valid != 0);
        held = tx_data;
        repeat (3) begin
            @(negedge clk);
            if (!rx_wait || !tx_sop || tx_data !== held)
                $fatal(1, "request or completion changed under backpressure");
        end
        tx_wait = 0;
        wait (!rx_wait);
        @(posedge clk);
        @(negedge clk);
        bardec = 0;
        sop = 0;
        eop = 0;
        valid = 0;
        wait (completed == 2);
        @(negedge clk);
        drive_read(8'h43, 4'hf, 10'd2);
        @(negedge clk);
        bardec = 0;
        sop = 0;
        eop = 0;
        valid = 0;
        wait (completed == 3);
        @(negedge clk);
        drive_read(8'h44, 4'h5, 10'd1);
        @(negedge clk);
        bardec = 0;
        sop = 0;
        eop = 0;
        valid = 0;
        wait (completed == 4);
        @(negedge clk);
        drive_read(8'h45, 4'h0, 10'd1);
        @(negedge clk);
        bardec = 0;
        sop = 0;
        eop = 0;
        valid = 0;
        wait (completed == 5);
        $display("PASS: BAR2 backpressure, byte enables, endian and unsupported read");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
