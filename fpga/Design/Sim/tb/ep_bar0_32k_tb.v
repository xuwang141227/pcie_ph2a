`timescale 1ns/1ps

module ep_bar0_32k_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [47:0] rx_bardec = 48'd0;
    reg [511:0] rx_data = 512'd0;
    reg rx_eop = 1'b0;
    reg rx_sop = 1'b0;
    reg [15:0] rx_valid = 16'd0;
    wire [511:0] tx_data;
    wire tx_eop;
    wire tx_sop;
    wire [15:0] tx_valid;

    always #5 clk = ~clk;

    pcie_ep_engine dut (
        .tl_clk_user(clk),
        .tl_rst_user(rst),
        .tl_int_msix_trigger(4'd0),
        .tl_rx_wait(),
        .tl_rx_masknp(),
        .tl_rx_bardec(rx_bardec),
        .tl_rx_data(rx_data),
        .tl_rx_eop(rx_eop),
        .tl_rx_err(8'd0),
        .tl_rx_mchit(12'd0),
        .tl_rx_sop(rx_sop),
        .tl_rx_valid(rx_valid),
        .tl_tx_data(tx_data),
        .tl_tx_eop(tx_eop),
        .tl_tx_err(),
        .tl_tx_sop(tx_sop),
        .tl_tx_stream(),
        .tl_tx_valid(tx_valid),
        .tl_tx_wait(1'b0),
        .tl_tx_credits(96'd0),
        .tl_cfg_busdev(13'h008)
    );

    task send_write_2dw;
        input [31:0] address;
        input [31:0] data0;
        input [31:0] data1;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b010;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd2;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h21;
            rx_data[455:452] = 4'hf;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = address;
            rx_data[415:384] = data0;
            rx_data[383:352] = data1;
            rx_sop = 1'b1;
            rx_eop = 1'b1;
            rx_valid = 16'hf800;
            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_sop = 1'b0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    task send_read_2dw;
        input [31:0] address;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b000;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd2;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h22;
            rx_data[455:452] = 4'hf;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = address;
            rx_sop = 1'b1;
            rx_eop = 1'b1;
            rx_valid = 16'he000;
            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_sop = 1'b0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    task send_write_20dw;
        input [31:0] address;
        integer lane;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b010;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd20;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h31;
            rx_data[455:452] = 4'hf;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = address;
            for(lane = 0; lane < 13; lane = lane + 1)
                rx_data[(12-lane)*32 +: 32] = 32'ha000_0000 + lane;
            rx_sop = 1'b1;
            rx_eop = 1'b0;
            rx_valid = 16'hffff;

            @(negedge clk);
            rx_data = 512'd0;
            for(lane = 13; lane < 20; lane = lane + 1)
                rx_data[(28-lane)*32 +: 32] = 32'ha000_0000 + lane;
            rx_sop = 1'b0;
            rx_eop = 1'b1;
            rx_valid = 16'hfe00;

            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    task send_read_20dw;
        input [31:0] address;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b000;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd20;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h32;
            rx_data[455:452] = 4'hf;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = address;
            rx_sop = 1'b1;
            rx_eop = 1'b1;
            rx_valid = 16'he000;
            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_sop = 1'b0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    task send_read_1byte;
        input [31:0] address;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b000;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd1;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h42;
            rx_data[455:452] = 4'h0;
            rx_data[451:448] = 4'h4;
            rx_data[447:416] = address;
            rx_sop = 1'b1;
            rx_eop = 1'b1;
            rx_valid = 16'he000;
            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_sop = 1'b0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    task send_write_1byte;
        input [31:0] address;
        input [31:0] data;
        begin
            @(negedge clk);
            rx_bardec = 48'h1;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b010;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd1;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h41;
            rx_data[455:452] = 4'h0;
            rx_data[451:448] = 4'h4;
            rx_data[447:416] = address;
            rx_data[415:384] = data;
            rx_sop = 1'b1;
            rx_eop = 1'b1;
            rx_valid = 16'hf000;
            @(negedge clk);
            rx_bardec = 48'd0;
            rx_data = 512'd0;
            rx_sop = 1'b0;
            rx_eop = 1'b0;
            rx_valid = 16'd0;
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        rst = 1'b0;
        send_write_2dw(32'h0000_7ff8, 32'h1234_5678, 32'h89ab_cdef);
        repeat(8) @(negedge clk);

        send_read_2dw(32'h0000_7ff8);
        wait(tx_sop);
        #1;
        if(tx_data[511:509] !== 3'b010 ||
           tx_data[415:384] !== 32'h1234_5678 ||
           tx_data[383:352] !== 32'h89ab_cdef) begin
            $display("FAIL: BAR0 completion data mismatch: %h", tx_data[415:352]);
            $fatal(1);
        end

        wait(!tx_sop);
        send_write_2dw(32'h0000_003c, 32'h0bad_f00d, 32'hc001_d00d);
        repeat(8) @(negedge clk);
        send_read_2dw(32'h0000_003c);
        wait(tx_sop);
        #1;
        if(tx_data[415:384] !== 32'h0bad_f00d ||
           tx_data[383:352] !== 32'hc001_d00d) begin
            $display("FAIL: BAR0 bank-wrap completion data mismatch: %h", tx_data[415:352]);
            $fatal(1);
        end

        wait(!tx_sop);
        send_write_20dw(32'h0000_0100);
        repeat(8) @(negedge clk);
        send_read_20dw(32'h0000_0100);
        wait(tx_sop);
        #1;
        if(tx_eop) begin
            $display("FAIL: 20-DW read completed in one beat");
            $fatal(1);
        end
        for(integer data_index = 0; data_index < 13; data_index = data_index + 1) begin
            if(tx_data[415-data_index*32 -: 32] !== 32'ha000_0000 + data_index) begin
                $display("FAIL: first completion beat data[%0d]=%h",
                         data_index, tx_data[415-data_index*32 -: 32]);
                $fatal(1);
            end
        end
        wait(tx_eop);
        #1;
        for(integer data_index = 13; data_index < 20; data_index = data_index + 1) begin
            if(tx_data[511-(data_index-13)*32 -: 32] !== 32'ha000_0000 + data_index) begin
                $display("FAIL: second completion beat data[%0d]=%h",
                         data_index, tx_data[511-(data_index-13)*32 -: 32]);
                $fatal(1);
            end
        end

        wait(!tx_eop);
        send_write_1byte(32'h0000_0100, 32'hdead_beef);
        repeat(8) @(negedge clk);
        send_read_1byte(32'h0000_0100);
        wait(tx_sop);
        #1;
        if(tx_data[415:384] !== 32'ha0ad_0000 ||
           tx_data[459:448] !== 12'd1 ||
           tx_data[422:416] !== 7'd2) begin
            $display("FAIL: byte-enable completion header/data mismatch");
            $fatal(1);
        end

        $display("PASS: BAR0 bounds, multi-beat access, and byte enables verified");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: test timed out");
        $fatal(1);
    end
endmodule
