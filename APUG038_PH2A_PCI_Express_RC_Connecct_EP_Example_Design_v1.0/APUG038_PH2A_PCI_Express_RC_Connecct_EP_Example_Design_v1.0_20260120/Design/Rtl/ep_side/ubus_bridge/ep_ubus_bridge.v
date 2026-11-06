//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ubus_bridge.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-09-19 17:55:55
//  Create        : 2022-06-23 15:40:13
//  Description   :
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module ep_ubus_bridge(

    input       wire                tl_clk_user     ,
    input       wire                uart_clk        ,
    input       wire                rst             ,
    input       wire                tl_clk_locked   ,

    // pcie Ubus
    input       wire                ubus_pcie_wen   ,
    input       wire    [31:0]      ubus_pcie_waddr ,
    input       wire    [31:0]      ubus_pcie_wdata ,
    input       wire                ubus_pcie_ren   ,
    input       wire    [31:0]      ubus_pcie_raddr ,
    output      wire                ubus_pcie_bken  ,
    output      wire    [31:0]      ubus_pcie_rdata ,

    // hxt Ubus
    input       wire                ubus_hxt_wen    ,
    input       wire    [31:0]      ubus_hxt_waddr  ,
    input       wire    [31:0]      ubus_hxt_wdata  ,
    input       wire                ubus_hxt_ren    ,
    input       wire    [31:0]      ubus_hxt_raddr  ,
    output      wire                ubus_hxt_bken   ,
    output      wire    [31:0]      ubus_hxt_rdata  ,

    // To fabric logic
    output      wire                ubus_wen_logic  ,
    output      wire    [31:0]      ubus_waddr_logic,
    output      wire    [31:0]      ubus_wdata_logic,
    output      wire                ubus_ren_logic  ,
    output      wire    [31:0]      ubus_raddr_logic,
    input       wire                ubus_bken_logic ,
    input       wire    [31:0]      ubus_rdata_logic,

    // To PCIe APB
    output      wire                tl_cfg_prst     ,
    output      wire                tl_cfg_penable  ,
    output      wire                tl_cfg_psel     ,
    output      wire                tl_cfg_pwrite   ,
    output      wire    [2:0]       tl_cfg_pprot    ,
    output      wire    [31:0]      tl_cfg_paddr    ,
    output      wire    [3:0]       tl_cfg_pstrb    ,
    output      wire    [31:0]      tl_cfg_pwdata   ,
    input       wire                tl_cfg_pready   ,
    input       wire    [31:0]      tl_cfg_prdata   ,
    input       wire                tl_cfg_pslverr  ,

    // To PHY0 APB
    output      wire                hxt_phy0_penable  ,
    output      wire                hxt_phy0_psel     ,
    output      wire                hxt_phy0_pwrite   ,
    output      wire    [2:0]       hxt_phy0_pprot    ,
    output      wire    [31:0]      hxt_phy0_paddr    ,
    output      wire    [3:0]       hxt_phy0_pstrb    ,
    output      wire    [31:0]      hxt_phy0_pwdata   ,
    input       wire                hxt_phy0_pready   ,
    input       wire    [31:0]      hxt_phy0_prdata   ,
    input       wire                hxt_phy0_pslverr  ,

    // To PHY1 APB
    output      wire                hxt_phy1_penable  ,
    output      wire                hxt_phy1_psel     ,
    output      wire                hxt_phy1_pwrite   ,
    output      wire    [2:0]       hxt_phy1_pprot    ,
    output      wire    [31:0]      hxt_phy1_paddr    ,
    output      wire    [3:0]       hxt_phy1_pstrb    ,
    output      wire    [31:0]      hxt_phy1_pwdata   ,
    input       wire                hxt_phy1_pready   ,
    input       wire    [31:0]      hxt_phy1_prdata   ,
    input       wire                hxt_phy1_pslverr
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================
    localparam          UBUS_BRDGE_TLP  =   8'hFF,
                        UBUS_BRDGE_PHY0 =   8'hF1,
                        UBUS_BRDGE_PHY1 =   8'hF0,
                        UBUS_BRDGE_APB  =   8'h00;

    reg                 ubus_pcie_wen_dly     ;
    reg     [31:0]      ubus_pcie_waddr_dly   ;
    reg     [31:0]      ubus_pcie_wdata_dly   ;
    reg                 ubus_pcie_ren_dly     ;
    reg     [31:0]      ubus_pcie_raddr_dly   ;
    reg                 ubus_pcie_bken_dly    ;
    reg     [31:0]      ubus_pcie_rdata_dly   ;

    reg                 ubus_hxt_wen_dly      ;
    reg     [31:0]      ubus_hxt_waddr_dly    ;
    reg     [31:0]      ubus_hxt_wdata_dly    ;
    reg                 ubus_hxt_ren_dly      ;
    reg     [31:0]      ubus_hxt_raddr_dly    ;
    reg                 ubus_hxt_bken_dly     ;
    reg     [31:0]      ubus_hxt_rdata_dly    ;


    reg                 ubus_wen_apb          ;
    reg     [31:0]      ubus_waddr_apb        ;
    reg     [31:0]      ubus_wdata_apb        ;
    reg                 ubus_ren_apb          ;
    reg     [31:0]      ubus_raddr_apb        ;
    wire                ubus_bken_apb         ;
    wire    [31:0]      ubus_rdata_abp        ;

    reg                 ubus_wen_tlp          ;
    reg     [31:0]      ubus_waddr_tlp        ;
    reg     [31:0]      ubus_wdata_tlp        ;
    reg                 ubus_ren_tlp          ;
    reg     [31:0]      ubus_raddr_tlp        ;
    wire                ubus_bken_tlp         ;
    wire    [31:0]      ubus_rdata_tlp        ;

    reg                 ubus_wen_phy0         ;
    reg     [31:0]      ubus_waddr_phy0       ;
    reg     [31:0]      ubus_wdata_phy0       ;
    reg                 ubus_ren_phy0         ;
    reg     [31:0]      ubus_raddr_phy0       ;
    wire                ubus_bken_phy0        ;
    wire    [31:0]      ubus_rdata_phy0       ;

    reg                 ubus_wen_phy1         ;
    reg     [31:0]      ubus_waddr_phy1       ;
    reg     [31:0]      ubus_wdata_phy1       ;
    reg                 ubus_ren_phy1         ;
    reg     [31:0]      ubus_raddr_phy1       ;
    wire                ubus_bken_phy1        ;
    wire    [31:0]      ubus_rdata_phy1       ;

// ====================================================================
// Main Code
// ====================================================================

//pcie ubus from uart module
always@(posedge tl_clk_user or posedge rst)
begin
    if(rst) begin
        ubus_pcie_wen_dly     <= 'b0;
        ubus_pcie_waddr_dly   <= 'b0;
        ubus_pcie_wdata_dly   <= 'b0;
        ubus_pcie_ren_dly     <= 'b0;
        ubus_pcie_raddr_dly   <= 'b0;
    end else begin
        ubus_pcie_wen_dly     <= ubus_pcie_wen     ;
        ubus_pcie_waddr_dly   <= ubus_pcie_waddr   ;
        ubus_pcie_wdata_dly   <= ubus_pcie_wdata   ;
        ubus_pcie_ren_dly     <= ubus_pcie_ren     ;
        ubus_pcie_raddr_dly   <= ubus_pcie_raddr   ;
    end
end

//hxt ubus from uart module
always@(posedge uart_clk or posedge rst)
begin
    if(rst) begin
        ubus_hxt_wen_dly      <= 'b0;
        ubus_hxt_waddr_dly    <= 'b0;
        ubus_hxt_wdata_dly    <= 'b0;
        ubus_hxt_ren_dly      <= 'b0;
        ubus_hxt_raddr_dly    <= 'b0;
    end else begin
        ubus_hxt_wen_dly      <= ubus_hxt_wen     ;
        ubus_hxt_waddr_dly    <= ubus_hxt_waddr   ;
        ubus_hxt_wdata_dly    <= ubus_hxt_wdata   ;
        ubus_hxt_ren_dly      <= ubus_hxt_ren     ;
        ubus_hxt_raddr_dly    <= ubus_hxt_raddr   ;
    end
end

// mux to tlp channel
always@(posedge tl_clk_user  or posedge rst)
begin
    if(rst) begin
        ubus_wen_tlp    <= 'b0;
        ubus_waddr_tlp  <= 'b0;
        ubus_wdata_tlp  <= 'b0;
        ubus_ren_tlp    <= 'b0;
        ubus_raddr_tlp  <= 'b0;
    end else begin

        if(ubus_pcie_wen_dly & (ubus_pcie_waddr_dly[31:24] == UBUS_BRDGE_TLP && ubus_pcie_waddr_dly[23:16] != UBUS_BRDGE_PHY0 && ubus_pcie_waddr_dly[23:16] != UBUS_BRDGE_PHY1 )) begin        
            ubus_wen_tlp    <= ubus_pcie_wen_dly  ;
            ubus_waddr_tlp  <= ubus_pcie_waddr_dly;
            ubus_wdata_tlp  <= ubus_pcie_wdata_dly;
        end else begin
            ubus_wen_tlp    <= 'b0;
            ubus_waddr_tlp  <= 'b0;
            ubus_wdata_tlp  <= 'b0;
        end

        if(ubus_pcie_ren_dly & (ubus_pcie_raddr_dly[31:24] == UBUS_BRDGE_TLP && ubus_pcie_raddr_dly[23:16] != UBUS_BRDGE_PHY0 && ubus_pcie_raddr_dly[23:16] != UBUS_BRDGE_PHY1 )) begin
            ubus_ren_tlp    <= ubus_pcie_ren_dly    ;
            ubus_raddr_tlp  <= ubus_pcie_raddr_dly  ;
        end else begin
            ubus_ren_tlp    <= 'b0;
            ubus_raddr_tlp  <= 'b0;
        end
    end
end

// mux to apb channel
always@(posedge tl_clk_user or posedge rst)
begin
    if(rst) begin
        ubus_wen_apb    <= 'b0;
        ubus_waddr_apb  <= 'b0;
        ubus_wdata_apb  <= 'b0;
        ubus_ren_apb    <= 'b0;
        ubus_raddr_apb  <= 'b0;
    end else begin

        if(ubus_pcie_wen_dly & (ubus_pcie_waddr_dly[31:24] == UBUS_BRDGE_APB && ubus_pcie_waddr_dly[23:16] != UBUS_BRDGE_PHY0 && ubus_pcie_waddr_dly[23:16] != UBUS_BRDGE_PHY1 )) begin     
            ubus_wen_apb    <= ubus_pcie_wen_dly  ;
            ubus_waddr_apb  <= ubus_pcie_waddr_dly;
            ubus_wdata_apb  <= ubus_pcie_wdata_dly;
        end else begin
            ubus_wen_apb    <= 'b0;
            ubus_waddr_apb  <= 'b0;
            ubus_wdata_apb  <= 'b0;
        end

        if(ubus_pcie_ren_dly & (ubus_pcie_raddr_dly[31:24] == UBUS_BRDGE_APB && ubus_pcie_raddr_dly[23:16] != UBUS_BRDGE_PHY0 && ubus_pcie_raddr_dly[23:16] != UBUS_BRDGE_PHY1 )) begin     
            ubus_ren_apb    <= ubus_pcie_ren_dly    ;
            ubus_raddr_apb  <= ubus_pcie_raddr_dly  ;
        end else begin
            ubus_ren_apb    <= 'b0;
            ubus_raddr_apb  <= 'b0;
        end
    end
end

// mux to phy0 channel
always@(posedge uart_clk or posedge rst)
begin
    if(rst) begin
        ubus_wen_phy0    <= 'b0;
        ubus_waddr_phy0  <= 'b0;
        ubus_wdata_phy0  <= 'b0;
        ubus_ren_phy0    <= 'b0;
        ubus_raddr_phy0  <= 'b0;
    end else begin

        if(ubus_hxt_wen_dly & (ubus_hxt_waddr_dly[23:16] == UBUS_BRDGE_PHY0)) begin
            ubus_wen_phy0    <= ubus_hxt_wen_dly  ;
            ubus_waddr_phy0  <= ubus_hxt_waddr_dly;
            ubus_wdata_phy0  <= ubus_hxt_wdata_dly;
        end else begin
            ubus_wen_phy0    <= 'b0;
            ubus_waddr_phy0  <= 'b0;
            ubus_wdata_phy0  <= 'b0;
        end

        if(ubus_hxt_ren_dly & (ubus_hxt_raddr_dly[23:16] == UBUS_BRDGE_PHY0)) begin
            ubus_ren_phy0   <= ubus_hxt_ren_dly    ;
            ubus_raddr_phy0 <= ubus_hxt_raddr_dly  ;
        end else begin
            ubus_ren_phy0   <= 'b0;
            ubus_raddr_phy0 <= 'b0;
        end
    end
end

// mux to phy1 channel
always@(posedge uart_clk  or posedge rst)
begin
    if(rst) begin
        ubus_wen_phy1    <= 'b0;
        ubus_waddr_phy1  <= 'b0;
        ubus_wdata_phy1  <= 'b0;
        ubus_ren_phy1    <= 'b0;
        ubus_raddr_phy1  <= 'b0;
    end else begin

        if(ubus_hxt_wen_dly & (ubus_hxt_waddr_dly[23:16] == UBUS_BRDGE_PHY1)) begin
            ubus_wen_phy1    <= ubus_hxt_wen_dly  ;
            ubus_waddr_phy1  <= ubus_hxt_waddr_dly;
            ubus_wdata_phy1  <= ubus_hxt_wdata_dly;
        end else begin
            ubus_wen_phy1    <= 'b0;
            ubus_waddr_phy1  <= 'b0;
            ubus_wdata_phy1  <= 'b0;
        end

        if(ubus_hxt_ren_dly & (ubus_hxt_raddr_dly[23:16] == UBUS_BRDGE_PHY1)) begin
            ubus_ren_phy1   <= ubus_hxt_ren_dly    ;
            ubus_raddr_phy1 <= ubus_hxt_raddr_dly  ;
        end else begin
            ubus_ren_phy1   <= 'b0;
            ubus_raddr_phy1 <= 'b0;
        end
    end
end

// readback data mux to pcie ubus
always@(posedge tl_clk_user or posedge rst)
begin
    if(rst) begin
        ubus_pcie_bken_dly    <= 'b0;
        ubus_pcie_rdata_dly   <= 'b0;
    end else begin

        ubus_pcie_bken_dly    <= ubus_bken_apb | ubus_bken_tlp ;

        if( ubus_bken_apb )
        ubus_pcie_rdata_dly   <= ubus_rdata_abp ;
        else if( ubus_bken_tlp )
        ubus_pcie_rdata_dly   <= ubus_rdata_tlp ;
    end
end

assign  ubus_pcie_bken = ubus_pcie_bken_dly;
assign  ubus_pcie_rdata= ubus_pcie_rdata_dly;

// readback data mux to hxt ubus
always@(posedge uart_clk or posedge rst)
begin
    if(rst) begin
        ubus_hxt_bken_dly    <= 'b0;
        ubus_hxt_rdata_dly   <= 'b0;
    end else begin

        ubus_hxt_bken_dly    <= ubus_bken_phy0 | ubus_bken_phy1 ;

        if( ubus_bken_phy0 )
        ubus_hxt_rdata_dly   <= ubus_rdata_phy0;
        else if( ubus_bken_phy1 )
        ubus_hxt_rdata_dly   <= ubus_rdata_phy1;
    end
end

assign  ubus_hxt_bken = ubus_hxt_bken_dly;
assign  ubus_hxt_rdata= ubus_hxt_rdata_dly;

// ====================================================================
// UBUS to TLP bridge
// ====================================================================

    assign  ubus_wen_logic    = ubus_wen_tlp    ;
    assign  ubus_waddr_logic  = ubus_waddr_tlp  ;
    assign  ubus_wdata_logic  = ubus_wdata_tlp  ;
    assign  ubus_ren_logic    = ubus_ren_tlp    ;
    assign  ubus_raddr_logic  = ubus_raddr_tlp  ;
    assign  ubus_bken_tlp     = ubus_bken_logic ;
    assign  ubus_rdata_tlp    = ubus_rdata_logic;

// ====================================================================
// UBUS to PCIe APB bridge
// ====================================================================
ubus2pcie_apb u_ubus2apb_pcie
(
    .clk             (tl_clk_user     ),
    .rst             (rst             ),
    .ubus2apb_idle   (),

    // UBUS
    .ubus_wen        (ubus_wen_apb    ),
    .ubus_waddr      (ubus_waddr_apb  ),
    .ubus_wdata      (ubus_wdata_apb  ),
    .ubus_ren        (ubus_ren_apb    ),
    .ubus_raddr      (ubus_raddr_apb  ),
    .ubus_bken       (ubus_bken_apb   ),
    .ubus_rdata      (ubus_rdata_abp  ),

    // APB
    .tl_cfg_prst     (tl_cfg_prst     ),
    .tl_cfg_penable  (tl_cfg_penable  ),
    .tl_cfg_psel     (tl_cfg_psel     ),
    .tl_cfg_pwrite   (tl_cfg_pwrite   ),
    .tl_cfg_pprot    (tl_cfg_pprot    ),
    .tl_cfg_paddr    (tl_cfg_paddr    ),
    .tl_cfg_pstrb    (tl_cfg_pstrb    ),
    .tl_cfg_pwdata   (tl_cfg_pwdata   ),
    .tl_cfg_pready   (tl_cfg_pready   ),
    .tl_cfg_prdata   (tl_cfg_prdata   ),
    .tl_cfg_pslverr  (tl_cfg_pslverr  )
);



// ====================================================================
// UBUS to PHY0 APB bridge
// ====================================================================
 ubus2phy_apb u_phy0_ubus2apb
(
    .clk             (uart_clk          ),
    .rst             (rst               ),
    // UBUS
    .ubus_wen        (ubus_wen_phy0     ),
    .ubus_waddr      (ubus_waddr_phy0   ),
    .ubus_wdata      (ubus_wdata_phy0   ),
    .ubus_ren        (ubus_ren_phy0     ),
    .ubus_raddr      (ubus_raddr_phy0   ),
    .ubus_bken       (ubus_bken_phy0    ),
    .ubus_rdata      (ubus_rdata_phy0   ),

    // APB
    .tl_cfg_prst     (),
    .tl_cfg_penable  (hxt_phy0_penable  ),
    .tl_cfg_psel     (hxt_phy0_psel     ),
    .tl_cfg_pwrite   (hxt_phy0_pwrite   ),
    .tl_cfg_pprot    (hxt_phy0_pprot    ),
    .tl_cfg_paddr    (hxt_phy0_paddr    ),
    .tl_cfg_pstrb    (hxt_phy0_pstrb    ),
    .tl_cfg_pwdata   (hxt_phy0_pwdata   ),
    .tl_cfg_pready   (hxt_phy0_pready   ),
    .tl_cfg_prdata   (hxt_phy0_prdata   ),
    .tl_cfg_pslverr  (hxt_phy0_pslverr  )
);

// ====================================================================
// UBUS to PHY1 APB bridge
// ====================================================================
 ubus2phy_apb u_phy1_ubus2apb
(
    .clk             (uart_clk          ),
    .rst             (rst               ),
    // UBUS
    .ubus_wen        (ubus_wen_phy1     ),
    .ubus_waddr      (ubus_waddr_phy1   ),
    .ubus_wdata      (ubus_wdata_phy1   ),
    .ubus_ren        (ubus_ren_phy1     ),
    .ubus_raddr      (ubus_raddr_phy1   ),
    .ubus_bken       (ubus_bken_phy1    ),
    .ubus_rdata      (ubus_rdata_phy1   ),

    // APB
    .tl_cfg_prst     (),
    .tl_cfg_penable  (hxt_phy1_penable  ),
    .tl_cfg_psel     (hxt_phy1_psel     ),
    .tl_cfg_pwrite   (hxt_phy1_pwrite   ),
    .tl_cfg_pprot    (hxt_phy1_pprot    ),
    .tl_cfg_paddr    (hxt_phy1_paddr    ),
    .tl_cfg_pstrb    (hxt_phy1_pstrb    ),
    .tl_cfg_pwdata   (hxt_phy1_pwdata   ),
    .tl_cfg_pready   (hxt_phy1_pready   ),
    .tl_cfg_prdata   (hxt_phy1_prdata   ),
    .tl_cfg_pslverr  (hxt_phy1_pslverr  )
);

endmodule
