`timescale 1ns/1ps
`include "../common/TLP_FMT_TYPE.v"

module pcie_ep_image_dma #(
    parameter integer FRAME_BYTES = 6220800,
    parameter integer FRAME_PERIOD_CYCLES = 80000000
) (
    input wire tl_clk_user,
    input wire tl_rst_user,
    input wire [47:0] tl_rx_bardec,
    input wire [511:0] tl_rx_data,
    input wire tl_rx_sop,
    input wire tl_rx_eop,
    input wire [15:0] tl_rx_valid,
    input wire [12:0] tl_cfg_busdev,
    input wire [15:0] tl_cfg_pfregs_cmd,
    input wire [2:0] tl_cfg_current_link_speed,
    input wire [3:0] tl_cfg_negotiated_width,
    input wire [2:0] tl_cfg_max_payload_size,
    input wire pl_link_up,
    input wire [95:0] tl_tx_credits,
    input wire tl_tx_wait,
    output reg [511:0] tl_tx_data,
    output reg tl_tx_eop,
    output wire [7:0] tl_tx_err,
    output reg tl_tx_sop,
    output wire tl_tx_stream,
    output reg [15:0] tl_tx_valid,
    output wire irq_pending
);

    localparam [31:0] REG_ID_VERSION   = 32'h000;
    localparam [31:0] REG_CONTROL      = 32'h004;
    localparam [31:0] REG_STATUS       = 32'h008;
    localparam [31:0] REG_PATTERN      = 32'h00c;
    localparam [31:0] REG_IRQ_STATUS   = 32'h010;
    localparam [31:0] REG_IRQ_ENABLE   = 32'h014;
    localparam [31:0] REG_ERROR        = 32'h018;
    localparam [31:0] REG_DROP_COUNT   = 32'h01c;
    localparam [31:0] REG_BUF0_ADDR_LO = 32'h020;
    localparam [31:0] REG_BUF0_ADDR_HI = 32'h024;
    localparam [31:0] REG_BUF1_ADDR_LO = 32'h028;
    localparam [31:0] REG_BUF1_ADDR_HI = 32'h02c;
    localparam [31:0] REG_BUF0_SEQ     = 32'h030;
    localparam [31:0] REG_BUF0_PATTERN = 32'h034;
    localparam [31:0] REG_BUF0_LENGTH  = 32'h038;
    localparam [31:0] REG_BUF1_SEQ     = 32'h040;
    localparam [31:0] REG_BUF1_PATTERN = 32'h044;
    localparam [31:0] REG_BUF1_LENGTH  = 32'h048;

    localparam [3:0] DMA_IRQ_SLOT0 = 4'h1;
    localparam [3:0] DMA_IRQ_SLOT1 = 4'h2;
    localparam [3:0] DMA_IRQ_ERROR = 4'h4;
    localparam [31:0] DMA_CONTROL_START = 32'h1;
    localparam [31:0] DMA_CONTROL_STOP = 32'h2;
    localparam [31:0] DMA_REARM0 = 32'h100;
    localparam [31:0] DMA_REARM1 = 32'h200;
    localparam integer FRAME_TIMER_WIDTH =
        FRAME_PERIOD_CYCLES > 1 ? $clog2(FRAME_PERIOD_CYCLES) : 1;

    reg [63:0] buffer0_address;
    reg [63:0] buffer1_address;
    reg [31:0] buffer0_sequence;
    reg [31:0] buffer1_sequence;
    reg [2:0] buffer0_pattern;
    reg [2:0] buffer1_pattern;
    reg [31:0] buffer0_length;
    reg [31:0] buffer1_length;
    reg buffer0_armed;
    reg buffer1_armed;
    reg [2:0] pattern_select;
    reg [3:0] interrupt_status;
    reg [3:0] interrupt_enable;
    reg [31:0] error_status;
    reg [31:0] dropped_frames;

    reg dma_running;
    reg stop_pending;
    reg frame_due;
    reg frame_busy;
    reg current_slot;
    reg next_slot;
    reg [2:0] current_pattern;
    reg [31:0] byte_offset;
    reg [FRAME_TIMER_WIDTH-1:0] frame_timer;
    reg [31:0] frame_sequence;
    reg [63:0] current_dma_address;
    reg [10:0] pixel_x;
    reg [10:0] pixel_y;
    reg [1:0] pixel_component_offset;
    reg tx_pending;
    reg tx_is_dma;
    reg tx_phase;
    reg packet_generate;
    reg packet_ready;
    reg [4:0] packet_generate_word;
    reg [511:0] packet_payload;
    reg [31:0] pixel_word_pipeline;
    reg [4:0] pixel_word_index;
    reg pixel_word_valid;
    reg pixel_word_last;
    reg [1:0] posted_credit_delay;
    reg [31:0] tx_packet_bytes;
    reg [4:0] tx_packet_dwords;
    reg completion_pending;
    reg [15:0] completion_requester;
    reg [7:0] completion_tag;
    reg [6:0] completion_lower_address;
    reg [31:0] completion_data;

    wire [2:0] rx_fmt = tl_rx_data[511:509];
    wire [9:0] rx_length = tl_rx_data[489:480];
    wire [3:0] rx_first_be = tl_rx_data[451:448];
    wire [3:0] rx_last_be = tl_rx_data[455:452];
    wire [31:0] rx_bar2_offset = (rx_fmt == `MWR_FMT_4DW ||
                                  rx_fmt == `MRD_FMT_4DW)
                               ? {12'd0, tl_rx_data[403:386], 2'b00}
                               : {12'd0, tl_rx_data[435:418], 2'b00};
    wire [31:0] rx_bar2_write_data =
        (rx_fmt == `MWR_FMT_4DW) ? tl_rx_data[383:352] : tl_rx_data[415:384];
    wire [15:0] rx_requester = tl_rx_data[479:464];
    wire [7:0] rx_tag = tl_rx_data[463:456];
    wire control_write =
        tl_rx_sop && tl_rx_valid != 16'd0 && tl_rx_bardec[2] && tl_rx_eop &&
        rx_length == 10'd1 && rx_first_be == 4'hf &&
        (rx_last_be == 4'h0 || rx_last_be == 4'hf) &&
        (rx_fmt == `MWR_FMT_4DW || rx_fmt == `MWR_FMT_3DW);
    wire stop_command = control_write && rx_bar2_offset == REG_CONTROL &&
                        rx_bar2_write_data[1];

    wire [31:0] status_register = {
        16'd0,
        tl_cfg_negotiated_width,
        1'b0,
        tl_cfg_current_link_speed,
        6'd0,
        !dma_running,
        dma_running
    };
    wire [31:0] frame_bytes_remaining = FRAME_BYTES - byte_offset;
    wire [31:0] bytes_to_4k_boundary = 32'd4096 -
                                        {20'd0, current_dma_address[11:0]};
    wire [31:0] packet_bytes_remaining =
        frame_bytes_remaining < bytes_to_4k_boundary
        ? frame_bytes_remaining : bytes_to_4k_boundary;
    wire [31:0] packet_bytes =
        packet_bytes_remaining < 32'd64 ? packet_bytes_remaining : 32'd64;
    wire [1:0] pixel_x_step =
        pixel_component_offset == 2'd2 ? 2'd2 : 2'd1;
    wire [11:0] pixel_x_advanced =
        {1'b0, pixel_x} + {10'd0, pixel_x_step};
    wire selected_slot =
        buffer0_armed && buffer1_armed ? next_slot : !buffer0_armed;
    wire [4:0] packet_dwords = packet_bytes[6:2];
    wire [4:0] first_beat_dwords =
        tx_packet_dwords > 5'd12 ? 5'd12 : tx_packet_dwords;
    wire [15:0] first_beat_valid =
        16'hffff << (16 - (4 + first_beat_dwords));
    wire [4:0] posted_data_credits_needed =
        (tx_packet_dwords + 5'd3) >> 2;
    wire [4:0] completion_data_credits_needed = 5'd1;
    wire can_send_posted =
        (tl_tx_credits[15] ||
         (tl_tx_credits[14:0] >= posted_data_credits_needed)) &&
        (tl_tx_credits[27] || (tl_tx_credits[26:16] != 11'd0));
    wire can_send_completion =
        (tl_tx_credits[79] ||
         (tl_tx_credits[78:64] >= completion_data_credits_needed)) &&
        (tl_tx_credits[91] || (tl_tx_credits[90:80] != 11'd0));
    assign tl_tx_err = 8'd0;
    assign tl_tx_stream = 1'b0;
    assign irq_pending = |(interrupt_status & interrupt_enable);

    function checker_half;
        input [10:0] coordinate;
        integer threshold;
        begin
            checker_half = 1'b0;
            for (threshold = 120; threshold <= 2040; threshold = threshold + 120)
                checker_half = checker_half ^ (coordinate >= threshold);
        end
    endfunction

    function [7:0] pixel_component;
        input [2:0] pattern;
        input [10:0] x;
        input [10:0] y;
        input [1:0] component;
        reg [28:0] scaled_value;
        reg [7:0] value;
        begin
            value = 8'd0;
            scaled_value = 29'd0;
            case (pattern)
                3'd0: begin
                    case (component)
                        2'd0: value = (x < 11'd480 ||
                                       (x >= 11'd960 && x < 11'd1440))
                                      ? 8'hff : 8'd0;
                        2'd1: value = x < 11'd960 ? 8'hff : 8'd0;
                        2'd2: value = (x < 11'd240 ||
                                       (x >= 11'd480 && x < 11'd720) ||
                                       (x >= 11'd960 && x < 11'd1200) ||
                                       (x >= 11'd1440 && x < 11'd1680))
                                      ? 8'hff : 8'd0;
                        default: value = 8'd0;
                    endcase
                end
                3'd1: begin
                    // Exact floor(coordinate * 255 / dimension) for 11-bit coordinates.
                    scaled_value = x * 18'd139337;
                    value = scaled_value >> 20;
                end
                3'd2:
                    value = (checker_half(x) ^ checker_half(y))
                            ? 8'd0 : 8'hff;
                3'd3: begin
                    if (component == 2'd0) begin
                        scaled_value = x * 18'd139337;
                        value = scaled_value >> 20;
                    end else if (component == 2'd1) begin
                        scaled_value = y * 17'd123905;
                        value = scaled_value >> 19;
                    end else
                        value = 8'd128;
                end
                3'd4: value = ((x >= 11'd956 && x <= 11'd963) ||
                               (y >= 11'd536 && y <= 11'd543))
                              ? 8'hff : 8'd0;
                3'd5: begin
                    if (y < 11'd540)
                        value = (x < 11'd960)
                              ? (component == 2'd0 ? 8'hff : 8'd0)
                              : (component == 2'd1 ? 8'hff : 8'd0);
                    else
                        value = (x < 11'd960)
                              ? (component == 2'd2 ? 8'hff : 8'd0)
                              : 8'hff;
                end
                default: value = 8'd0;
            endcase
            pixel_component = value;
        end
    endfunction

    function [31:0] pixel_dword;
        input [10:0] x;
        input [10:0] y;
        input [1:0] component_offset;
        input [2:0] pattern;
        integer lane;
        reg [2:0] lane_component_sum;
        reg [10:0] lane_x;
        reg [10:0] lane_y;
        begin
            pixel_dword = 32'd0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                lane_component_sum = {1'b0, component_offset} + lane;
                lane_x = x;
                lane_y = y;
                if (lane_component_sum >= 3'd3) begin
                    lane_component_sum = lane_component_sum - 3'd3;
                    if (x == 11'd1919) begin
                        lane_x = 11'd0;
                        lane_y = y + 1'b1;
                    end else
                        lane_x = x + 1'b1;
                end
                pixel_dword[31-lane*8 -: 8] =
                    pixel_component(pattern, lane_x, lane_y,
                                    lane_component_sum[1:0]);
            end
        end
    endfunction

    function [31:0] register_read;
        input [31:0] address;
        begin
            case (address)
                REG_ID_VERSION: register_read = 32'h00010001;
                REG_CONTROL: register_read = 32'd0;
                REG_STATUS: register_read = status_register;
                REG_PATTERN: register_read = {29'd0, pattern_select};
                REG_IRQ_STATUS: register_read = {28'd0, interrupt_status};
                REG_IRQ_ENABLE: register_read = {28'd0, interrupt_enable};
                REG_ERROR: register_read = error_status;
                REG_DROP_COUNT: register_read = dropped_frames;
                REG_BUF0_ADDR_LO: register_read = buffer0_address[31:0];
                REG_BUF0_ADDR_HI: register_read = buffer0_address[63:32];
                REG_BUF1_ADDR_LO: register_read = buffer1_address[31:0];
                REG_BUF1_ADDR_HI: register_read = buffer1_address[63:32];
                REG_BUF0_SEQ: register_read = buffer0_sequence;
                REG_BUF0_PATTERN: register_read = {29'd0, buffer0_pattern};
                REG_BUF0_LENGTH: register_read = buffer0_length;
                REG_BUF1_SEQ: register_read = buffer1_sequence;
                REG_BUF1_PATTERN: register_read = {29'd0, buffer1_pattern};
                REG_BUF1_LENGTH: register_read = buffer1_length;
                default: register_read = 32'd0;
            endcase
        end
    endfunction

    always @(posedge tl_clk_user or posedge tl_rst_user) begin
        if (tl_rst_user) begin
            buffer0_address <= 64'd0;
            buffer1_address <= 64'd0;
            buffer0_sequence <= 32'd0;
            buffer1_sequence <= 32'd0;
            buffer0_pattern <= 3'd0;
            buffer1_pattern <= 3'd0;
            buffer0_length <= 32'd0;
            buffer1_length <= 32'd0;
            buffer0_armed <= 1'b0;
            buffer1_armed <= 1'b0;
            pattern_select <= 3'd0;
            interrupt_status <= 4'd0;
            interrupt_enable <= 4'd0;
            error_status <= 32'd0;
            dropped_frames <= 32'd0;
            dma_running <= 1'b0;
            stop_pending <= 1'b0;
            frame_due <= 1'b0;
            frame_busy <= 1'b0;
            current_slot <= 1'b0;
            next_slot <= 1'b0;
            current_pattern <= 3'd0;
            byte_offset <= 32'd0;
            frame_timer <= {FRAME_TIMER_WIDTH{1'b0}};
            frame_sequence <= 32'd0;
            current_dma_address <= 64'd0;
            pixel_x <= 11'd0;
            pixel_y <= 11'd0;
            pixel_component_offset <= 2'd0;
            tx_pending <= 1'b0;
            tx_is_dma <= 1'b0;
            tx_phase <= 1'b0;
            packet_generate <= 1'b0;
            packet_ready <= 1'b0;
            packet_generate_word <= 5'd0;
            packet_payload <= 512'd0;
            pixel_word_pipeline <= 32'd0;
            pixel_word_index <= 5'd0;
            pixel_word_valid <= 1'b0;
            pixel_word_last <= 1'b0;
            posted_credit_delay <= 2'd0;
            tx_packet_bytes <= 32'd0;
            tx_packet_dwords <= 5'd0;
            completion_pending <= 1'b0;
            completion_requester <= 16'd0;
            completion_tag <= 8'd0;
            completion_lower_address <= 7'd0;
            completion_data <= 32'd0;
            tl_tx_data <= 512'd0;
            tl_tx_eop <= 1'b0;
            tl_tx_sop <= 1'b0;
            tl_tx_valid <= 16'd0;
        end else begin
            if (tl_rx_sop && tl_rx_valid != 16'd0 && tl_rx_bardec[2]) begin
                if (rx_fmt == `MWR_FMT_4DW || rx_fmt == `MWR_FMT_3DW) begin
                    if (rx_length != 10'd1 || rx_first_be != 4'hf ||
                        (rx_last_be != 4'h0 && rx_last_be != 4'hf) ||
                        !tl_rx_eop) begin
                        error_status <= 32'h00000001;
                        interrupt_status[2] <= 1'b1;
                    end else begin
                        case (rx_bar2_offset)
                            REG_CONTROL: begin
                                if (rx_bar2_write_data & DMA_REARM0) begin
                                    buffer0_armed <= 1'b1;
                                    buffer0_length <= 32'd0;
                                end
                                if (rx_bar2_write_data & DMA_REARM1) begin
                                    buffer1_armed <= 1'b1;
                                    buffer1_length <= 32'd0;
                                end
                                if (rx_bar2_write_data & DMA_CONTROL_START) begin
                                    if (!pl_link_up || !tl_cfg_pfregs_cmd[2] ||
                                        !buffer0_armed || !buffer1_armed ||
                                        tl_cfg_max_payload_size > 3'd5 ||
                                        buffer0_address[1:0] != 2'b00 ||
                                        buffer1_address[1:0] != 2'b00) begin
                                        error_status <= 32'h00000002;
                                        interrupt_status[2] <= 1'b1;
                                    end else begin
                                        dma_running <= 1'b1;
                                        stop_pending <= 1'b0;
                                        frame_due <= 1'b1;
                                        frame_timer <= {FRAME_TIMER_WIDTH{1'b0}};
                                        frame_sequence <= 32'd0;
                                        dropped_frames <= 32'd0;
                                        error_status <= 32'd0;
                                        next_slot <= 1'b0;
                                    end
                                end
                                if (rx_bar2_write_data & DMA_CONTROL_STOP) begin
                                    frame_due <= 1'b0;
                                    if (frame_busy)
                                        stop_pending <= 1'b1;
                                    else begin
                                        dma_running <= 1'b0;
                                        stop_pending <= 1'b0;
                                        buffer0_armed <= 1'b0;
                                        buffer1_armed <= 1'b0;
                                    end
                                end
                            end
                            REG_PATTERN: begin
                                if (rx_bar2_write_data[31:3] != 29'd0 ||
                                    rx_bar2_write_data[2:0] >= 3'd6) begin
                                    error_status <= 32'h00000003;
                                    interrupt_status[2] <= 1'b1;
                                end else
                                    pattern_select <= rx_bar2_write_data[2:0];
                            end
                            REG_IRQ_STATUS:
                                interrupt_status <= interrupt_status &
                                                    ~rx_bar2_write_data[3:0];
                            REG_IRQ_ENABLE:
                                interrupt_enable <= rx_bar2_write_data[3:0];
                            REG_ERROR:
                                error_status <= error_status & ~rx_bar2_write_data;
                            REG_BUF0_ADDR_LO, REG_BUF0_ADDR_HI: begin
                                if (dma_running || frame_busy)
                                    begin
                                        error_status <= 32'h00000006;
                                        interrupt_status[2] <= 1'b1;
                                    end
                                else if (rx_bar2_offset == REG_BUF0_ADDR_LO)
                                    buffer0_address[31:0] <= rx_bar2_write_data;
                                else
                                    buffer0_address[63:32] <= rx_bar2_write_data;
                            end
                            REG_BUF1_ADDR_LO, REG_BUF1_ADDR_HI: begin
                                if (dma_running || frame_busy)
                                    begin
                                        error_status <= 32'h00000006;
                                        interrupt_status[2] <= 1'b1;
                                    end
                                else if (rx_bar2_offset == REG_BUF1_ADDR_LO)
                                    buffer1_address[31:0] <= rx_bar2_write_data;
                                else
                                    buffer1_address[63:32] <= rx_bar2_write_data;
                            end
                            default: begin
                                error_status <= 32'h00000004;
                                interrupt_status[2] <= 1'b1;
                            end
                        endcase
                    end
                end
                if ((rx_fmt == `MRD_FMT_4DW || rx_fmt == `MRD_FMT_3DW) &&
                    rx_length == 10'd1 && rx_first_be == 4'hf && tl_rx_eop) begin
                    if (completion_pending) begin
                        error_status <= 32'h00000005;
                        interrupt_status[2] <= 1'b1;
                    end else begin
                        completion_pending <= 1'b1;
                        completion_requester <= rx_requester;
                        completion_tag <= rx_tag;
                        completion_lower_address <= rx_bar2_offset[6:0];
                        completion_data <= register_read(rx_bar2_offset);
                    end
                end
            end

            if (dma_running && !stop_pending && FRAME_PERIOD_CYCLES > 0) begin
                if (frame_timer == FRAME_PERIOD_CYCLES - 1) begin
                    frame_timer <= {FRAME_TIMER_WIDTH{1'b0}};
                    if (!frame_due) begin
                        if (frame_busy || (!buffer0_armed && !buffer1_armed))
                            dropped_frames <= dropped_frames + 1'b1;
                        else
                            frame_due <= 1'b1;
                    end
                end else
                    frame_timer <= frame_timer + 1'b1;
            end else
                frame_timer <= {FRAME_TIMER_WIDTH{1'b0}};

            if (dma_running && frame_due && !frame_busy && !stop_command) begin
                if (buffer0_armed || buffer1_armed) begin
                    current_slot <= selected_slot;
                    next_slot <= !selected_slot;
                    current_pattern <= pattern_select;
                    current_dma_address <= selected_slot ? buffer1_address :
                                                           buffer0_address;
                    byte_offset <= 32'd0;
                    pixel_x <= 11'd0;
                    pixel_y <= 11'd0;
                    pixel_component_offset <= 2'd0;
                    frame_busy <= 1'b1;
                    frame_due <= 1'b0;
                end else begin
                    frame_due <= 1'b0;
                    dropped_frames <= dropped_frames + 1'b1;
                end
            end

            if (posted_credit_delay != 2'd0)
                posted_credit_delay <= posted_credit_delay - 1'b1;

            if (frame_busy && dma_running && !packet_generate &&
                !pixel_word_valid && !packet_ready && !tx_pending) begin
                tx_packet_bytes <= packet_bytes;
                tx_packet_dwords <= packet_dwords;
                packet_generate_word <= 5'd0;
                packet_generate <= 1'b1;
            end

            pixel_word_valid <= packet_generate;
            if (packet_generate) begin
                pixel_word_pipeline <= pixel_dword(pixel_x, pixel_y,
                                                  pixel_component_offset, current_pattern);
                pixel_word_index <= packet_generate_word;
                pixel_word_last <= packet_generate_word + 1'b1 == tx_packet_dwords;
                pixel_component_offset <= pixel_component_offset == 2'd2
                                        ? 2'd0
                                        : pixel_component_offset + 1'b1;
                if (pixel_x_advanced >= 12'd1920) begin
                    pixel_x <= pixel_x_advanced - 12'd1920;
                    pixel_y <= pixel_y + 1'b1;
                end else
                    pixel_x <= pixel_x_advanced[10:0];
                if (packet_generate_word + 1'b1 == tx_packet_dwords) begin
                    packet_generate <= 1'b0;
                end else
                    packet_generate_word <= packet_generate_word + 1'b1;
            end
            if (pixel_word_valid) begin
                packet_payload[511 - pixel_word_index*32 -: 32] <= pixel_word_pipeline;
                if (pixel_word_last)
                    packet_ready <= 1'b1;
            end

            if (tx_pending && !tl_tx_wait) begin
                if (tx_is_dma)
                    posted_credit_delay <= 2'd2;
                if (tx_is_dma && !tx_phase && tx_packet_dwords > 5'd12) begin
                    tx_phase <= 1'b1;
                    tl_tx_sop <= 1'b0;
                    tl_tx_eop <= 1'b1;
                    tl_tx_valid <=
                        16'hffff << (16 - (tx_packet_dwords - 5'd12));
                    tl_tx_data <= {packet_payload[127:0], 384'd0};
                end else begin
                    tx_pending <= 1'b0;
                    tx_phase <= 1'b0;
                    tl_tx_valid <= 16'd0;
                    tl_tx_sop <= 1'b0;
                    tl_tx_eop <= 1'b0;
                    if (tx_is_dma) begin
                        if (byte_offset + tx_packet_bytes == FRAME_BYTES) begin
                            frame_busy <= 1'b0;
                            frame_sequence <= frame_sequence + 1'b1;
                            if (current_slot) begin
                                buffer1_sequence <= frame_sequence;
                                buffer1_pattern <= current_pattern;
                                buffer1_length <= FRAME_BYTES;
                                buffer1_armed <= 1'b0;
                                interrupt_status[1] <= 1'b1;
                            end else begin
                                buffer0_sequence <= frame_sequence;
                                buffer0_pattern <= current_pattern;
                                buffer0_length <= FRAME_BYTES;
                                buffer0_armed <= 1'b0;
                                interrupt_status[0] <= 1'b1;
                            end
                            if (stop_pending || stop_command) begin
                                dma_running <= 1'b0;
                                stop_pending <= 1'b0;
                                buffer0_armed <= 1'b0;
                                buffer1_armed <= 1'b0;
                            end
                        end else begin
                            byte_offset <= byte_offset + tx_packet_bytes;
                            current_dma_address <= current_dma_address +
                                                   tx_packet_bytes;
                        end
                        packet_ready <= 1'b0;
                    end else
                        completion_pending <= 1'b0;
                end
            end else if (!tx_pending &&
                ((completion_pending && can_send_completion) ||
                 (!completion_pending && can_send_posted &&
                  posted_credit_delay == 2'd0))) begin
                if (completion_pending) begin
                    tl_tx_data <= {
                        `CPLD_FMT, `CPLD_TYPE, 1'b0, 3'b000, 1'b0, 1'b0,
                        1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 10'd1,
                        {tl_cfg_busdev, 3'b000}, 3'b000, 1'b0, 12'd4,
                        completion_requester, completion_tag, 1'b0,
                        completion_lower_address, completion_data, 384'd0
                    };
                    tl_tx_valid <= 16'hf000;
                    tx_is_dma <= 1'b0;
                    tx_pending <= 1'b1;
                    tx_phase <= 1'b0;
                    tl_tx_eop <= 1'b1;
                end else if (frame_busy && dma_running && packet_ready) begin
                    tl_tx_data <= {
                        `MWR_FMT_4DW, `MWR_TYPE, 1'b0, 3'b000, 1'b0, 1'b0,
                        1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00,
                        {5'd0, tx_packet_dwords},
                        {tl_cfg_busdev, 3'b000}, 8'd0,
                        (tx_packet_dwords > 5'd1 ? 4'hf : 4'h0), 4'hf,
                        current_dma_address[63:32],
                        current_dma_address[31:2], 2'b00,
                        packet_payload[511:128]
                    };
                    tl_tx_valid <= first_beat_valid;
                    tx_is_dma <= 1'b1;
                    tx_pending <= 1'b1;
                    tx_phase <= 1'b0;
                    tl_tx_eop <= tx_packet_dwords <= 5'd12;
                end
                if (completion_pending ||
                    (frame_busy && dma_running && packet_ready)) begin
                    tl_tx_sop <= 1'b1;
                end
            end
        end
    end

endmodule
