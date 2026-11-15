//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_ep_engine.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-10-17 15:26:58
//  Create        : 2022-07-12 11:03:47
//  Description   :
//                  1. rec iow  Pkg and respond cpl
//                  2. rec ior  Pkg and respond cpld
//                  3. rec memw pkg
//                  1. rec memr pkg and respond cpld
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

module  pcie_ep_engine(

    // Clock and Reset
    input       wire                tl_clk_user            ,
    input       wire                tl_rst_user            ,

    input       wire    [3:0]       tl_int_msix_trigger    ,

    // Rx interface
    output      wire                tl_rx_wait             ,
    output      wire                tl_rx_masknp           ,
    input       wire    [47:0]      tl_rx_bardec           ,
    input       wire    [511:0]     tl_rx_data             ,
    input       wire                tl_rx_eop              ,
    input       wire    [7:0]       tl_rx_err              ,
    input       wire    [11:0]      tl_rx_mchit            ,
    input       wire                tl_rx_sop              ,
    input       wire    [15:0]      tl_rx_valid            ,

    // TX interface
    output      reg     [511:0]     tl_tx_data             ,
    output      reg                 tl_tx_eop              ,
    output      wire    [7:0]       tl_tx_err              ,
    output      reg                 tl_tx_sop              ,
    output      wire                tl_tx_stream           ,
    output      reg     [15:0]      tl_tx_valid            ,
    input       wire                tl_tx_wait             ,
    input       wire    [95:0]      tl_tx_credits          ,

        // pcie ip
    input       wire    [12:0]      tl_cfg_busdev


);

`include "../common/TLP_FMT_TYPE.v"
`include "../common/BDF.v"

function [2:0] byte_enable_count;
    input [3:0] byte_enable;
    begin
        byte_enable_count = byte_enable[0] + byte_enable[1] +
                            byte_enable[2] + byte_enable[3];
    end
endfunction

function [1:0] first_enabled_byte;
    input [3:0] byte_enable;
    begin
        casez(byte_enable)
            4'b???1: first_enabled_byte = 2'd0;
            4'b??10: first_enabled_byte = 2'd1;
            4'b?100: first_enabled_byte = 2'd2;
            4'b1000: first_enabled_byte = 2'd3;
            default: first_enabled_byte = 2'd0;
        endcase
    end
endfunction

// ====================================================================
// Parameter|Wire|Reg
// ====================================================================

// pipeline for input signals
reg     [47:0]       tl_rx_bardec_ff        ;
reg     [511:0]      tl_rx_data_ff          ;
reg                  tl_rx_eop_ff           ;
reg     [7:0]        tl_rx_err_ff           ;
reg     [11:0]       tl_rx_mchit_ff         ;
reg                  tl_rx_sop_ff           ;
reg     [15:0]       tl_rx_valid_ff         ;

reg     [47:0]       tl_rx_bardec_2ff       ;
reg     [511:0]      tl_rx_data_2ff         ;
reg                  tl_rx_eop_2ff          ;
reg     [7:0]        tl_rx_err_2ff          ;
reg     [11:0]       tl_rx_mchit_2ff        ;
reg                  tl_rx_sop_2ff          ;
reg     [15:0]       tl_rx_valid_2ff        ;

reg     [47:0]       tl_rx_bardec_3ff       ;
reg     [511:0]      tl_rx_data_3ff         ;
reg                  tl_rx_eop_3ff          ;
reg     [7:0]        tl_rx_err_3ff          ;
reg     [11:0]       tl_rx_mchit_3ff        ;
reg                  tl_rx_sop_3ff          ;
reg     [15:0]       tl_rx_valid_3ff        ;

reg                  iow_flag               ;
reg                  ior_flag               ;
reg                  memwr_flag             ;
reg                  memrd_flag             ;
reg     [12:0]       memrd_addr             ;
reg     [12:0]       memrd_byte_count       ;
reg     [1:0]        memrd_first_byte       ;

reg     [15:0]       rc_bdf                 ;
reg     [7:0]        np_tag                 ;

reg     [31:0]       iodata_array[5:0]      ;
reg     [31:0]       iodata                 ;
reg     [5:0]        io_addr                ;

integer i;
reg     [13:0]       bar0_wr_word_addr      ;
reg     [13:0]       bar0_wr_word_tmp       ;
reg     [10:0]       bar0_wr_dw_count       ;
reg     [10:0]       bar0_wr_len            ;
reg     [3:0]        bar0_wr_first_be       ;
reg     [3:0]        bar0_wr_last_be        ;
integer              bar0_wr_lane           ;
integer              bar0_wr_count_tmp      ;
reg     [31:0]       bar0_wr_data_tmp       ;
reg     [3:0]        bar0_wr_be_tmp          ;
integer              bar0_rd_lane           ;
reg     [13:0]       bar0_rd_word_addr      ;
reg     [15:0]       bar0_bank_we           ;
reg     [63:0]       bar0_bank_be           ;
reg     [143:0]      bar0_bank_wr_addr      ;
reg     [511:0]      bar0_bank_wr_data      ;
reg     [143:0]      bar0_bank_rd_addr      ;
wire    [511:0]      bar0_bank_rd_data      ;
integer              bar0_bank              ;

reg     [15:0]       mrdata_cycle_valid     ;
reg     [9:0]        mrdata_cycle           ;

wire    [25:0]       mrdata_cycle_valid_32bit;
wire    [31:0]       mrdata_cycle_valid_tmp ;

reg     [5:0]        mrdata_rd_addr         ;
reg     [5:0]        mrdata_rd_addr_dly     ;
reg     [511:0]      mrdata_rd_data         ;
reg     [511:0]      mrdata_rd_data_ff      ;

reg                  mem_first_cycle        ;
reg                  mem_addr_is_64bit      ;
reg     [10:0]       tl_mr_len_ff           ;

`ifdef PH2_PCIE_MSIX_INT_ENABLE
reg     [3:0]       tl_int_msix_trigger_ff  ;
reg     [63:0]      tl_msix_sgm_addr_ff     ;
reg     [31:0]      tl_msix_sgm_data_ff     ;
reg     [63:0]      tl_msix_sgm_addr_0      ;
reg     [31:0]      tl_msix_sgm_data_0      ;
reg     [63:0]      tl_msix_sgm_addr_1      ;
reg     [31:0]      tl_msix_sgm_data_1      ;
reg     [63:0]      tl_msix_sgm_addr_2      ;
reg     [31:0]      tl_msix_sgm_data_2      ;
reg     [63:0]      tl_msix_sgm_addr_3      ;
reg     [31:0]      tl_msix_sgm_data_3      ;
`else
wire    [3:0]       tl_int_msix_trigger_ff='d0;
wire    [63:0]      tl_msix_sgm_addr_ff='d0;
wire    [31:0]      tl_msix_sgm_data_ff='d0;
`endif

// ====================================================================
// Main Code
// ====================================================================

assign      tl_rx_wait      = 1'b0;
assign      tl_rx_masknp    = 1'b0;

// pipeline input signals
always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin
        tl_rx_bardec_ff       <= 'd0;
        tl_rx_data_ff         <= 'd0;
        tl_rx_eop_ff          <= 'd0;
        tl_rx_err_ff          <= 'd0;
        tl_rx_mchit_ff        <= 'd0;
        tl_rx_sop_ff          <= 'd0;
        tl_rx_valid_ff        <= 'd0;
        tl_rx_bardec_2ff      <= 'd0;
        tl_rx_data_2ff        <= 'd0;
        tl_rx_eop_2ff         <= 'd0;
        tl_rx_err_2ff         <= 'd0;
        tl_rx_mchit_2ff       <= 'd0;
        tl_rx_sop_2ff         <= 'd0;
        tl_rx_valid_2ff       <= 'd0;
        tl_rx_bardec_3ff      <= 'd0;
        tl_rx_data_3ff        <= 'd0;
        tl_rx_eop_3ff         <= 'd0;
        tl_rx_err_3ff         <= 'd0;
        tl_rx_mchit_3ff       <= 'd0;
        tl_rx_sop_3ff         <= 'd0;
        tl_rx_valid_3ff       <= 'd0;
    end else begin
        tl_rx_bardec_ff       <= tl_rx_bardec    ;
        tl_rx_data_ff         <= tl_rx_data      ;
        tl_rx_eop_ff          <= tl_rx_eop       ;
        tl_rx_err_ff          <= tl_rx_err       ;
        tl_rx_mchit_ff        <= tl_rx_mchit     ;
        tl_rx_sop_ff          <= tl_rx_sop       ;
        tl_rx_valid_ff        <= tl_rx_valid     ;
        tl_rx_bardec_2ff      <= tl_rx_bardec_ff ;
        tl_rx_data_2ff        <= tl_rx_data_ff   ;
        tl_rx_eop_2ff         <= tl_rx_eop_ff    ;
        tl_rx_err_2ff         <= tl_rx_err_ff    ;
        tl_rx_mchit_2ff       <= tl_rx_mchit_ff  ;
        tl_rx_sop_2ff         <= tl_rx_sop_ff    ;
        tl_rx_valid_2ff       <= tl_rx_valid_ff  ;
        tl_rx_bardec_3ff      <= tl_rx_bardec_2ff;
        tl_rx_data_3ff        <= tl_rx_data_2ff  ;
        tl_rx_eop_3ff         <= tl_rx_eop_2ff   ;
        tl_rx_err_3ff         <= tl_rx_err_2ff   ;
        tl_rx_mchit_3ff       <= tl_rx_mchit_2ff ;
        tl_rx_sop_3ff         <= tl_rx_sop_2ff   ;
        tl_rx_valid_3ff       <= tl_rx_valid_2ff ;
    end
end

//--------------------------------------------
// Tl interface decode
//--------------------------------------------
always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin
        iow_flag   <= 1'b0;
        ior_flag   <= 1'b0;
        memwr_flag <= 1'b0;
        memrd_flag <= 1'b0;
        io_addr    <= 6'd0;
        memrd_addr <= 13'd0;
        memrd_byte_count <= 13'd0;
        memrd_first_byte <= 2'd0;
    end else begin
        if(tl_rx_sop_ff) begin
            if( tl_rx_bardec_ff[0] &&
                (tl_rx_data_ff[511:509] == `MWR_FMT_3DW  || tl_rx_data_ff[511:509] == `MWR_FMT_4DW  ) &&
                tl_rx_data_ff[508:504] == `MWR_TYPE )
            memwr_flag <= 1'b1;
        end else if(tl_rx_eop_2ff) begin
            memwr_flag <= 1'b0;
        end
        if( tl_rx_eop_2ff ) begin
            iow_flag   <= 1'b0;
            ior_flag   <= 1'b0;
            memrd_flag <= 1'b0;
        end else if( tl_rx_sop_ff ) begin
            if( tl_rx_data_ff[511:509] == `IOWR_FMT  & tl_rx_data_ff[508:504] == `IOWR_TYPE  ) begin
                iow_flag   <= 1'b1;
                io_addr    <= tl_rx_data_ff[423:418]; // dw align
            end
            if( tl_rx_data_ff[511:509] == `IORD_FMT  & tl_rx_data_ff[508:504] == `IORD_TYPE  ) begin
                ior_flag   <= 1'b1;
                io_addr    <= tl_rx_data_ff[423:418]; // dw align
            end
            if( tl_rx_bardec_ff[0] &&
                tl_rx_data_ff[511:509] == `MRD_FMT_3DW && tl_rx_data_ff[508:504] == `MRD_TYPE  ) begin
                memrd_flag <= 1'b1;
                memrd_addr <= tl_rx_data_ff[430:418];
                memrd_first_byte <= first_enabled_byte(tl_rx_data_ff[451:448]);
                if(tl_rx_data_ff[489:480] == 10'd0)
                    memrd_byte_count <= 13'd4096;
                else if(tl_rx_data_ff[489:480] == 10'd1)
                    memrd_byte_count <= byte_enable_count(tl_rx_data_ff[451:448]);
                else
                    memrd_byte_count <=
                        (({3'd0, tl_rx_data_ff[489:480]} - 13'd2) * 13'd4) +
                        byte_enable_count(tl_rx_data_ff[451:448]) +
                        byte_enable_count(tl_rx_data_ff[455:452]);
            end
            if( tl_rx_bardec_ff[0] &&
                tl_rx_data_ff[511:509] == `MRD_FMT_4DW  && tl_rx_data_ff[508:504] == `MRD_TYPE  ) begin
                memrd_flag <= 1'b1;
                memrd_addr <= tl_rx_data_ff[398:386];
                memrd_first_byte <= first_enabled_byte(tl_rx_data_ff[451:448]);
                if(tl_rx_data_ff[489:480] == 10'd0)
                    memrd_byte_count <= 13'd4096;
                else if(tl_rx_data_ff[489:480] == 10'd1)
                    memrd_byte_count <= byte_enable_count(tl_rx_data_ff[451:448]);
                else
                    memrd_byte_count <=
                        (({3'd0, tl_rx_data_ff[489:480]} - 13'd2) * 13'd4) +
                        byte_enable_count(tl_rx_data_ff[451:448]) +
                        byte_enable_count(tl_rx_data_ff[455:452]);
            end

        end
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin
        rc_bdf     <= 16'd0;
        np_tag     <= 8'd0;
    end else if( tl_rx_sop_ff ) begin
        rc_bdf     <= tl_rx_data_ff[479:464];
        np_tag     <= tl_rx_data_ff[463:456];
    end
end

//--------------------------------------------
// IOw & IOr
//--------------------------------------------
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        for(i=0;i<=5;i=i+1)begin : ep_io_array_rest
          iodata_array[i] <= 32'd0;
        end
    end else if(iow_flag & tl_rx_sop_2ff ) begin
        for(i=0;i<=5;i=i+1)begin : ep_io_array_vaule
          if(io_addr==i)
            iodata_array[i] <= tl_rx_data_2ff[415:384];
        end
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        iodata <= 32'd0;
    end else begin
        iodata <= iodata_array[io_addr];
    end
end

//--------------------------------------------
// MEMw & MEMr
//--------------------------------------------
// Sixteen dword-wide banks sustain one 512-bit receive beat per cycle.
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        bar0_wr_word_addr <= 14'd0;
        bar0_wr_dw_count <= 11'd0;
        bar0_wr_len <= 11'd0;
        bar0_wr_first_be <= 4'd0;
        bar0_wr_last_be <= 4'd0;
    end else begin
        if(tl_rx_sop_ff && tl_rx_bardec_ff[0] &&
           (tl_rx_data_ff[511:509] == `MWR_FMT_3DW ||
            tl_rx_data_ff[511:509] == `MWR_FMT_4DW) &&
           tl_rx_data_ff[508:504] == `MWR_TYPE) begin
            bar0_wr_word_addr <= (tl_rx_data_ff[511:509] == `MWR_FMT_4DW)
                               ? tl_rx_data_ff[398:386]
                               : tl_rx_data_ff[430:418];
            bar0_wr_dw_count <= 11'd0;
            bar0_wr_len <= (|tl_rx_data_ff[489:480])
                         ? {1'b0, tl_rx_data_ff[489:480]} : 11'd1024;
            bar0_wr_first_be <= tl_rx_data_ff[451:448];
            bar0_wr_last_be <= tl_rx_data_ff[455:452];
        end
        if(memwr_flag) begin
            bar0_wr_word_addr <= bar0_wr_word_tmp;
            bar0_wr_dw_count <= bar0_wr_count_tmp[10:0];
        end
    end
end

always@(*) begin
    bar0_bank_we = 16'd0;
    bar0_bank_be = 64'd0;
    bar0_bank_wr_addr = 144'd0;
    bar0_bank_wr_data = 512'd0;
    bar0_wr_word_tmp = bar0_wr_word_addr;
    bar0_wr_count_tmp = bar0_wr_dw_count;
    bar0_wr_data_tmp = 32'd0;
    bar0_wr_be_tmp = 4'd0;
    if(memwr_flag) begin
        for(bar0_wr_lane = 15; bar0_wr_lane >= 0; bar0_wr_lane = bar0_wr_lane - 1) begin
            if(tl_rx_valid_2ff[bar0_wr_lane] &&
               (!tl_rx_sop_2ff ||
                (mem_addr_is_64bit ? (bar0_wr_lane <= 11) : (bar0_wr_lane <= 12)))) begin
                bar0_wr_data_tmp = tl_rx_data_2ff[bar0_wr_lane*32 +: 32];
                if(bar0_wr_count_tmp == 0)
                    bar0_wr_be_tmp = bar0_wr_first_be;
                else if(bar0_wr_count_tmp == bar0_wr_len - 1'b1)
                    bar0_wr_be_tmp = bar0_wr_last_be;
                else
                    bar0_wr_be_tmp = 4'hf;

                if(bar0_wr_word_tmp < 14'd8192) begin
                    bar0_bank_we[bar0_wr_word_tmp[3:0]] = 1'b1;
                    bar0_bank_be[bar0_wr_word_tmp[3:0]*4 +: 4] = bar0_wr_be_tmp;
                    bar0_bank_wr_addr[bar0_wr_word_tmp[3:0]*9 +: 9] =
                        bar0_wr_word_tmp[12:4];
                    bar0_bank_wr_data[bar0_wr_word_tmp[3:0]*32 +: 32] =
                        bar0_wr_data_tmp;
                end
                bar0_wr_word_tmp = bar0_wr_word_tmp + 1'b1;
                bar0_wr_count_tmp = bar0_wr_count_tmp + 1;
            end
        end
    end

    bar0_rd_word_addr = 14'd0;
    bar0_bank_rd_addr = 144'd0;
    bar0_rd_word_addr = memrd_addr + {mrdata_rd_addr, 4'b0};
    for(bar0_bank = 0; bar0_bank < 16; bar0_bank = bar0_bank + 1) begin
        if(bar0_bank >= bar0_rd_word_addr[3:0])
            bar0_bank_rd_addr[bar0_bank*9 +: 9] = bar0_rd_word_addr[12:4];
        else
            bar0_bank_rd_addr[bar0_bank*9 +: 9] = bar0_rd_word_addr[12:4] + 1'b1;
    end

    mrdata_rd_data = 512'd0;
    for(bar0_rd_lane = 0; bar0_rd_lane < 16; bar0_rd_lane = bar0_rd_lane + 1) begin
        bar0_rd_word_addr = memrd_addr + {mrdata_rd_addr_dly, 4'b0} + (15 - bar0_rd_lane);
        if(bar0_rd_word_addr < 14'd8192)
            mrdata_rd_data[bar0_rd_lane*32 +: 32] =
                bar0_bank_rd_data[bar0_rd_word_addr[3:0]*32 +: 32];
    end
end

genvar bar0_bank_gen;
generate
    for(bar0_bank_gen = 0; bar0_bank_gen < 16; bar0_bank_gen = bar0_bank_gen + 1) begin : g_bar0_ram
        ram #(
            .MODE           ("DP"       ),
            .BYTE_SIZE      (8          ),
            .USE_BYTE_WEA   (1          ),
            .DATAWIDTH_A    (32         ),
            .ADDRWIDTH_A    (9          ),
            .DATADEPTH_A    (512        ),
            .USE_BYTE_WEB   (1          ),
            .DATAWIDTH_B    (32         ),
            .ADDRWIDTH_B    (9          ),
            .DATADEPTH_B    (512        )
        ) u_bar0_bank (
            .clka           (tl_clk_user),
            .rsta           (tl_rst_user),
            .cea            (bar0_bank_we[bar0_bank_gen]),
            .ocea           (1'b1),
            .wea            (bar0_bank_be[bar0_bank_gen*4 +: 4]),
            .dia            (bar0_bank_wr_data[bar0_bank_gen*32 +: 32]),
            .addra          (bar0_bank_wr_addr[bar0_bank_gen*9 +: 9]),
            .doa            (),
            .clkb           (tl_clk_user),
            .rstb           (tl_rst_user),
            .ceb            (1'b1),
            .oceb           (1'b1),
            .web            (4'b0),
            .dib            (32'b0),
            .addrb          (bar0_bank_rd_addr[bar0_bank_gen*9 +: 9]),
            .dob            (bar0_bank_rd_data[bar0_bank_gen*32 +: 32]),
            .ecc_sbiterrinj (1'b0),
            .ecc_dbiterrinj (1'b0),
            .ecc_pipece     (1'b0),
            .ecc_sbiterr    (),
            .ecc_dbiterr    (),
            .ecc_erraddr    ()
        );
    end
endgenerate


// ====================================================================
// TX Engine
// ====================================================================

reg   [4:0]  tl_tx_state;
localparam   TL_TX_IDLE     = 5'b0_0001,
             TL_TX_ACK_IOW  = 5'b0_0010,
             TL_TX_ACK_IOR  = 5'b0_0100,
             TL_TX_ACK_MEMR = 5'b0_1000,
             TL_TX_ACK_MSIX = 5'b1_0000;

assign  tl_tx_err    = 8'b0;
assign  tl_tx_stream = 1'b0;

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        tl_tx_state <= TL_TX_IDLE;
        tl_tx_data  <= 'd0;
        tl_tx_eop   <= 'd0;
        tl_tx_sop   <= 'd0;
        tl_tx_valid <= 'd0;
    end else begin
       case( tl_tx_state )
            TL_TX_IDLE: begin
                if(iow_flag)
                    tl_tx_state <= TL_TX_ACK_IOW;
                else if(ior_flag)
                    tl_tx_state <= TL_TX_ACK_IOR;
                else if(memrd_flag)
                    tl_tx_state <= TL_TX_ACK_MEMR;
                else if(tl_int_msix_trigger_ff)
                    tl_tx_state <= TL_TX_ACK_MSIX;
                else
                    tl_tx_state <= tl_tx_state;
            end

            TL_TX_ACK_IOW:begin  // ack cpl
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 16'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 16'hE000;
                end

                tl_tx_data <= {`CPL_FMT                              ,
                               `CPL_TYPE                             ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'b1                                , // length(dw)
                             //  `EP_PF0_BDF                           , // completer id
                               {tl_cfg_busdev,3'b000}               , // completer id
                               3'b000                               , // status
                               1'b0                                 , // bcm
                               12'h0                                , // byte count
                               rc_bdf[15:0]                         , // requester id
                               np_tag[7:0]                          , // np_tag
                               1'b0                                 , // R
                               1'b0                                 , // tile to 1'b0
                               io_addr[5:0]                         , // Lower Address
                               416'd0
                              };
            end

            TL_TX_ACK_IOR:begin  // ack cpld with only one dw
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 16'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 16'hF000;
                end

                //tl_tx_data <= {    `MRD_FMT_4DW                         ,
                //                   `MRD_TYPE                            ,
                //                   1'b0                                 , // R
                //                   3'b0                                 , // tc
                //                   1'b0                                 , // R
                //                   1'b0                                 , // attr[2]
                //                   1'b0                                 , // R
                //                   1'b0                                 , // th
                //                   1'b0                                 , // td
                //                   1'b0                                 , // ep
                //                   2'b0                                 , // attr
                //                   2'b0                                 , // AT
                //                   10'h10                               , // length(dw)
                //                   16'h0e                               , // requester id
                //                   8'd0                                 , // np_tag
                //                   4'hf                                 , // last be
                //                   4'hf                                 , // first be
                //                   64'h00000009_57064000                , // address
                //                   //2'b0                               , // ph
                //                   384'd0
                //                   };
                tl_tx_data <= {`CPLD_FMT                            ,
                               `CPLD_TYPE                           ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'b1                                , // length(dw)
//                               `EP_PF0_BDF                          , // completer id
                               {tl_cfg_busdev,3'b000}               , // completer id
                               3'b000                               , // status
                               1'b0                                 , // bcm
                               12'h4                                , // byte count
                               rc_bdf[15:0]                         , // requester id
                               np_tag[7:0]                          , // np_tag
                               1'b0                                 , // R
//                               1'b0                                 , // tile to 1'b0
//                               io_addr[5:0]                         , // Lower Address
                               io_addr[4:0],2'b00                         , // Lower Address
                               iodata[31:0]                         , // Read Data
                               384'd0
                              };
            end

            TL_TX_ACK_MEMR:begin
                if( mem_first_cycle ) // first cycle
                    tl_tx_sop <= 1'b1;
                else
                    tl_tx_sop <= 1'b0;

                if(tl_tx_eop & (!tl_tx_wait))
                    tl_tx_eop <= 1'b0;
                else if( mem_first_cycle & mrdata_cycle == 10'd0 )
                    tl_tx_eop <= 1'b1;
                else if(tl_tx_valid[15] & (!tl_tx_wait) & (mrdata_cycle == 10'd0) )
                    tl_tx_eop <= 1'b1;

                if(mem_first_cycle | tl_tx_valid[15] & (!tl_tx_wait) )
                    tl_tx_valid <= mrdata_cycle_valid;

                if(mem_first_cycle)
                    tl_tx_data <= {`CPLD_FMT                            ,
                                   `CPLD_TYPE                           ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mr_len_ff[9:0]                    , // length(dw)
//                                   `EP_PF0_BDF                          , // completer id
                                   {tl_cfg_busdev,3'b000}               , // completer id
                                   3'b000                               , // status
                                   1'b0                                 , // bcm
                                   memrd_byte_count[11:0]               , // byte count
                                   rc_bdf[15:0]                         , // requester id
                                   np_tag[7:0]                          , // np_tag
                                   1'b0                                 , // R
//                                   memrd_addr[6:0]                      , // Lower Address
                                  ({memrd_addr[4:0],2'b00} +
                                   {5'd0,memrd_first_byte})              , // Lower Address
                                   mrdata_rd_data[511:96]
                                   };
                else if(tl_tx_valid[15] & (!tl_tx_wait) )
                     tl_tx_data <=  { mrdata_rd_data_ff[95:0], mrdata_rd_data[511:96] };

                if( tl_tx_eop & tl_tx_valid[15] & (!tl_tx_wait)  )
                    tl_tx_state     <= TL_TX_IDLE;
            end

            TL_TX_ACK_MSIX:begin

                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 16'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 16'hF800;
                end

                tl_tx_data <= {`MWR_FMT_4DW                         ,
                               `MWR_TYPE                            ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'd1                                , // length(dw)
//                               `EP_PF0_BDF                           , // requester id
                               {tl_cfg_busdev,3'b000}               , // completer id
                               8'd0                                 , // np_tag
                               4'h0                                 , // last be
                               4'hf                                 , // first be
                               tl_msix_sgm_addr_ff[63:2]            , // address
                               2'b0                                 , // ph
                               tl_msix_sgm_data_ff[31:0]            ,
                               352'd0
                              };
            end
       endcase
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        mem_first_cycle <= 1'b1;
    else if(tl_tx_state == TL_TX_IDLE  )
        mem_first_cycle <= 1'b1;
    else
        mem_first_cycle <= 1'b0;
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        mem_addr_is_64bit <= 1'b0;
    else if( tl_rx_sop_ff  )
        if( ( tl_rx_data_ff[511:509] == `MRD_FMT_4DW ) | ( tl_rx_data_ff[511:509] ==`MWR_FMT_4DW  )  )
            mem_addr_is_64bit <= 1'b1;
        else
            mem_addr_is_64bit <= 1'b0;
   else
        mem_addr_is_64bit <= mem_addr_is_64bit;
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        tl_mr_len_ff <= 11'b0;
    else if( tl_rx_sop_ff  )
        if( (tl_rx_data_ff[511:509] == `MRD_FMT_3DW || tl_rx_data_ff[511:509] == `MRD_FMT_4DW )  & tl_rx_data_ff[508:504] == `MRD_TYPE )
            tl_mr_len_ff  <= (|tl_rx_data_ff[489:480]) ? {1'b0,tl_rx_data_ff[489:480]}  : 11'd1024 ; // max is 1024*4 = 4096 bytes
   else
        tl_mr_len_ff   <= tl_mr_len_ff;
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        mrdata_rd_data_ff <= 512'd0;
    end else if(tl_tx_state == TL_TX_ACK_MEMR) begin
        if(tl_tx_valid[15] & (!tl_tx_wait) | mem_first_cycle)begin
        mrdata_rd_data_ff <= mrdata_rd_data;
        end
	end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        mrdata_rd_addr_dly <= 6'd0;
    end else begin
        mrdata_rd_addr_dly <= mrdata_rd_addr;
    end
end

always@( * ) begin
    if(tl_tx_state == TL_TX_ACK_MEMR) begin
        if(tl_tx_valid[15] & (!tl_tx_wait) | mem_first_cycle)begin
           mrdata_rd_addr <= mrdata_rd_addr_dly + 1'b1 ;
        end else begin
           mrdata_rd_addr <= mrdata_rd_addr_dly;
        end
    end else begin
        mrdata_rd_addr    <= 6'b0;
    end
end

assign  mrdata_cycle_valid_32bit = 26'h3ff_e000  >> (tl_mr_len_ff[3:0] );
assign  mrdata_cycle_valid_tmp   = 32'hffff_0000 >> (mrdata_cycle[3:0] );

always@(posedge tl_clk_user or posedge tl_rst_user) begin
     if(tl_rst_user) begin
        mrdata_cycle <= 13'd0;
     end else begin
        case(tl_tx_state)
            TL_TX_IDLE : begin
                mrdata_cycle        <= tl_mr_len_ff[10:0] > 13 ? tl_mr_len_ff[10:0] - 13 : 12'd0;
                mrdata_cycle_valid  <= tl_mr_len_ff[10:0] > 13 ? 16'hffff                : {3'h7,mrdata_cycle_valid_32bit[12:0] };
            end
            TL_TX_ACK_MEMR :begin
                if( tl_tx_valid[15] & (!tl_tx_wait) | mem_first_cycle ) begin
                    mrdata_cycle        <= mrdata_cycle > 16 ? mrdata_cycle - 16 : 12'd0;
                    mrdata_cycle_valid  <= mrdata_cycle > 16 ? 16'hffff : mrdata_cycle_valid_tmp;
                end
            end
        default:;
        endcase
     end
end

// ====================================================================
// MSIx Rec
// default 64bit bar4 is msix bar
// ====================================================================
`ifdef PH2_PCIE_MSIX_INT_ENABLE
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        tl_msix_sgm_addr_0 <= 64'd0;
        tl_msix_sgm_addr_1 <= 64'd0;
        tl_msix_sgm_addr_2 <= 64'd0;
        tl_msix_sgm_addr_3 <= 64'd0;
        tl_msix_sgm_data_0 <= 32'd0;
        tl_msix_sgm_data_1 <= 32'd0;
        tl_msix_sgm_data_2 <= 32'd0;
        tl_msix_sgm_data_3 <= 32'd0;
//  end else begin
//        tl_msix_sgm_addr_0 <= `MSIX_MSG_ADDR0;
//        tl_msix_sgm_addr_1 <= `MSIX_MSG_ADDR1;
//        tl_msix_sgm_addr_2 <= `MSIX_MSG_ADDR2;
//        tl_msix_sgm_addr_3 <= `MSIX_MSG_ADDR3;
//        tl_msix_sgm_data_0 <= `MSIX_MSG_DATA0;
//        tl_msix_sgm_data_1 <= `MSIX_MSG_DATA1;
//        tl_msix_sgm_data_2 <= `MSIX_MSG_DATA2;
//        tl_msix_sgm_data_3 <= `MSIX_MSG_DATA3;
    end else if( memwr_flag ) begin
        // msg0
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 )         ) begin
            tl_msix_sgm_addr_0[31:0] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h4 ) begin
            tl_msix_sgm_addr_0[63:32] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h8 ) begin
            tl_msix_sgm_data_0[31:0]  <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        // msg1
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h10 ) begin
            tl_msix_sgm_addr_1[31:0] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h14 ) begin
            tl_msix_sgm_addr_1[63:32] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h18 ) begin
            tl_msix_sgm_data_1[31:0]  <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        // msg2
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h20 ) begin
            tl_msix_sgm_addr_2[31:0] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h24 ) begin
            tl_msix_sgm_addr_2[63:32] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h28 ) begin
            tl_msix_sgm_data_2[31:0]  <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        // msg3
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h30 ) begin
            tl_msix_sgm_addr_3[31:0] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h34 ) begin
            tl_msix_sgm_addr_3[63:32] <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[399:384] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h38 ) begin
            tl_msix_sgm_data_3[31:0]  <= {tl_rx_data_2ff[359:352],tl_rx_data_2ff[367:360],tl_rx_data_2ff[375:368],tl_rx_data_2ff[383:376]};
        end
    end
end

always@(posedge tl_clk_user ) begin
    tl_int_msix_trigger_ff  <= tl_int_msix_trigger;
    case(tl_int_msix_trigger_ff)
    4'b0001: begin
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_0;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_0;
    end
    4'b0010: begin
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_1;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_1;
    end
    4'b0100: begin
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_2;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_2;
    end
    4'b1000: begin
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_3;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_3;
    end
    default: ;
    endcase
end
`endif

endmodule