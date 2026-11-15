`timescale 1ns/1ps

module pcie_ep_image_dma_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [47:0] rx_bardec = 48'd0;
    reg [511:0] rx_data = 512'd0;
    reg rx_sop = 1'b0;
    reg rx_eop = 1'b0;
    reg [15:0] rx_valid = 16'd0;
    reg tx_wait = 1'b0;
    wire [511:0] tx_data;
    wire tx_eop;
    wire tx_sop;
    wire [15:0] tx_valid;
    wire irq_pending;
    integer dma_packets = 0;
    integer slot1_dma_packets = 0;
    integer completion_packets = 0;
    reg [31:0] completion_payload = 32'd0;
    reg [511:0] stalled_data = 512'd0;

    always #5 clk = ~clk;

    pcie_ep_image_dma #(
        .FRAME_BYTES(80),
        .FRAME_PERIOD_CYCLES(500)
    ) dut (
        .tl_clk_user(clk),
        .tl_rst_user(rst),
        .tl_rx_bardec(rx_bardec),
        .tl_rx_data(rx_data),
        .tl_rx_sop(rx_sop),
        .tl_rx_eop(rx_eop),
        .tl_rx_valid(rx_valid),
        .tl_cfg_busdev(13'h008),
        .tl_cfg_pfregs_cmd(16'h0004),
        .tl_cfg_current_link_speed(3'd2),
        .tl_cfg_negotiated_width(4'd4),
        .tl_cfg_max_payload_size(3'd1),
        .pl_link_up(1'b1),
        .tl_tx_credits(96'hffffffffffffffffffffffff),
        .tl_tx_wait(tx_wait),
        .tl_tx_data(tx_data),
        .tl_tx_eop(tx_eop),
        .tl_tx_err(),
        .tl_tx_sop(tx_sop),
        .tl_tx_stream(),
        .tl_tx_valid(tx_valid),
        .irq_pending(irq_pending)
    );

    task write_bar2;
        input [31:0] offset;
        input [31:0] value;
        begin
            @(negedge clk);
            rx_bardec = 48'h4;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b011;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd1;
            rx_data[479:464] = 16'h0100;
            rx_data[455:448] = 8'hff;
            rx_data[447:416] = 32'd0;
            rx_data[415:386] = offset[31:2];
            rx_data[383:352] = value;
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

    task read_bar2;
        input [31:0] offset;
        begin
            @(negedge clk);
            rx_bardec = 48'h4;
            rx_data = 512'd0;
            rx_data[511:509] = 3'b001;
            rx_data[508:504] = 5'b00000;
            rx_data[489:480] = 10'd1;
            rx_data[479:464] = 16'h0100;
            rx_data[463:456] = 8'h55;
            rx_data[451:448] = 4'hf;
            rx_data[447:416] = 32'd0;
            rx_data[415:386] = offset[31:2];
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

    always @(posedge clk) begin
        if (!rst && tx_sop && tx_eop && tx_valid == 16'hff00 &&
            tx_data[489:480] == 10'd4 && !tx_wait) begin
            if (dut.frame_sequence == 32'd0) begin
                if (tx_data[511:509] !== 3'b011 ||
                    tx_data[489:480] !== 10'd4 ||
                    tx_data[447:416] !== 32'h0000_0001 ||
                    tx_data[415:386] !== (32'h1234_5ff0 >> 2) ||
                    tx_data[383:352] !== 32'hffff_ffff ||
                    tx_data[351:320] !== 32'hffff_ffff ||
                    tx_data[319:288] !== 32'hffff_ffff ||
                    tx_data[287:256] !== 32'hffff_ffff) begin
                    $display("FAIL: malformed TLP ending at 4 KiB: %h",
                             tx_data[511:256]);
                    $fatal(1);
                end
            end
            dma_packets = dma_packets + 1;
        end
        if (!rst && tx_valid == 16'hffff && tx_sop && !tx_eop) begin
            if (dut.frame_sequence == 32'd1 &&
                tx_data[511:509] == 3'b011) begin
                if (tx_data[415:386] !== (32'h1234_6000 >> 2) ||
                    tx_data[447:416] !== 32'h0000_0001) begin
                    $display("FAIL: second frame did not use slot 1 DMA address");
                    $fatal(1);
                end
                slot1_dma_packets = slot1_dma_packets + 1;
            end
            if (tx_data[511:509] !== 3'b011 ||
                tx_data[489:480] !== 10'd16 ||
                tx_data[447:416] !== 32'h0000_0001 ||
                tx_data[415:386] !== (32'h1234_6000 >> 2) ||
                tx_data[383:352] !== 32'hffff_ffff ||
                tx_data[31:0] !== 32'hffff_ffff) begin
                $display("FAIL: malformed TLP beginning after 4 KiB: %h",
                         tx_data[511:352]);
                $fatal(1);
            end
        end
        if (!rst && tx_valid == 16'hf000 && !tx_sop && tx_eop && !tx_wait) begin
            if (tx_data[511:384] !== {4{32'hffff_ffff}}) begin
                $display("FAIL: malformed final MWr beat: %h", tx_data[511:384]);
                $fatal(1);
            end
            dma_packets = dma_packets + 1;
        end
        if (!rst && tx_valid == 16'hf000 && tx_sop && tx_eop &&
            tx_data[511:509] == 3'b010) begin
            completion_payload = tx_data[415:384];
            completion_packets = completion_packets + 1;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        if (dut.pixel_component(3'd0, 0, 0, 0) != 8'd255 ||
            dut.pixel_component(3'd0, 240, 0, 2) != 8'd0 ||
            dut.pixel_component(3'd1, 0, 0, 0) != 8'd0 ||
            dut.pixel_component(3'd1, 1919, 0, 0) != 8'd255 ||
            dut.pixel_component(3'd2, 0, 0, 0) != 8'd255 ||
            dut.pixel_component(3'd2, 120, 0, 0) != 8'd0 ||
            dut.pixel_component(3'd3, 1919, 1079, 2) != 8'd128 ||
            dut.pixel_component(3'd3, 1919, 1079, 1) != 8'd255 ||
            dut.pixel_component(3'd4, 956, 0, 0) != 8'd255 ||
            dut.pixel_component(3'd4, 955, 0, 0) != 8'd0 ||
            dut.pixel_component(3'd5, 0, 0, 0) != 8'd255 ||
            dut.pixel_component(3'd5, 960, 0, 1) != 8'd255 ||
            dut.pixel_component(3'd5, 0, 540, 2) != 8'd255 ||
            dut.pixel_component(3'd5, 960, 540, 0) != 8'd255) begin
            $display("FAIL: pattern reference pixel mismatch");
            $fatal(1);
        end
        write_bar2(32'h020, 32'h1234_5ff0);
        write_bar2(32'h024, 32'h0000_0001);
        write_bar2(32'h028, 32'h1234_6000);
        write_bar2(32'h02c, 32'h0000_0001);
        write_bar2(32'h014, 32'h0000_0007);
        write_bar2(32'h004, 32'h0000_0300);
        write_bar2(32'h004, 32'h0000_0001);

        wait (dma_packets == 1);
        wait (tx_sop && tx_data[489:480] == 10'd16);
        tx_wait = 1'b1;
        stalled_data = tx_data;
        repeat (3) @(posedge clk);
        if (!tx_sop || tx_data !== stalled_data || tx_valid !== 16'hffff) begin
            $display("FAIL: TLP changed under wait");
            $fatal(1);
        end
        @(negedge clk);
        tx_wait = 1'b0;
        wait (dma_packets == 2);
        wait (irq_pending);
        if (dut.buffer0_sequence !== 32'd0 ||
            dut.buffer0_pattern !== 3'd0 ||
            dut.buffer0_length !== 32'd80) begin
            $display("FAIL: frame completion metadata mismatch");
            $fatal(1);
        end

        read_bar2(32'h038);
        wait (completion_packets == 1);
        if (completion_payload !== 32'd80) begin
            $display("FAIL: BAR2 completion data mismatch: %h",
                     completion_payload);
            $fatal(1);
        end

        write_bar2(32'h010, 32'h0000_0001);
        repeat (3) @(negedge clk);
        if (irq_pending) begin
            $display("FAIL: frame IRQ did not clear");
            $fatal(1);
        end
        write_bar2(32'h004, 32'h0000_0100);
        wait (dut.interrupt_status[1]);
        if (dut.buffer1_sequence !== 32'd1 ||
            dut.buffer1_pattern !== 3'd0 ||
            dut.buffer1_length !== 32'd80 ||
            slot1_dma_packets != 1) begin
            $display("FAIL: alternating DMA buffer completion mismatch");
            $fatal(1);
        end
        write_bar2(32'h004, 32'h0000_0002);
        if (dut.dma_running || dut.frame_busy ||
            dut.buffer0_armed || dut.buffer1_armed) begin
            $display("FAIL: STOP did not disarm idle DMA slots");
            $fatal(1);
        end
        write_bar2(32'h010, 32'h0000_0007);
        write_bar2(32'h004, 32'h0000_0300);
        write_bar2(32'h004, 32'h0000_0001);
        wait (tx_sop && tx_data[511:509] == 3'b011);
        @(negedge clk);
        tx_wait = 1'b1;
        write_bar2(32'h004, 32'h0000_0002);
        if (!dut.dma_running || !dut.stop_pending) begin
            $display("FAIL: STOP did not wait for the in-flight frame");
            $fatal(1);
        end
        @(negedge clk);
        tx_wait = 1'b0;
        wait (!dut.dma_running);
        if (dut.frame_busy || dut.buffer0_length !== 32'd80 ||
            dut.frame_sequence !== 32'd1) begin
            $display("FAIL: in-flight frame did not finish before STOP");
            $fatal(1);
        end

        $display("PASS: BAR2 control, image TLP, 4 KiB split, metadata, dual buffer, IRQ and STOP");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $fatal(1);
    end
endmodule
