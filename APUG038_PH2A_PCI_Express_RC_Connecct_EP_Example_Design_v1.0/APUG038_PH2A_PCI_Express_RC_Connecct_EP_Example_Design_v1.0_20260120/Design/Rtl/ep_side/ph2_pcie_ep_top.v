//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph600_pcie_case_ep.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-10-31 15:55:39
//  Create        : 2022-05-19 14:57:39
//  Description   :
//
///////////////////////////////////////////////////////////////


`timescale 1ns/1ps 

 module ph2_pcie_ep_top( 

    // serdes high speed pin
    input      wire                      ref_pad_clk_p                           ,
    input      wire                      ref_pad_clk_n                           ,
    input      wire  [7:0]               pcie_rx_p                               ,
    input      wire  [7:0]               pcie_rx_n                               ,
    output     wire  [7:0]               pcie_tx_p                               ,
    output     wire  [7:0]               pcie_tx_n                               ,


    input      wire                      sys_clk                                 ,
    
    input      wire                      user_int_trigger                        ,
   
    // pcie ip reset
    input      wire                      pcie_mperst                             ,
    input      wire                      pcie_power_on_rst                       ,

    // uart signals
    input       wire                     rxd                                     ,
    output      wire                     txd                                     ,

    output     wire     [7:0]            debug_led

);

`include "../common/ph2_pcie_case_param.v"

// ====================================================================
// Parameter/wire/reg
// ====================================================================

    // clock and reset signals
    wire                tl_clk_user                             /*synthesis keep*/;
    wire                hxt_apb4_pclk_in                        ;
    wire                uart_clk                                ;
    wire                tl_clk_locked                           ;
    wire                tl_clk_gate                             ;
    wire  [8:0]         tl_clk_user_freq                        ;
    wire                pcie_pll_locked                         ;
    wire                tl_rst_user                             ;
    reg                 power_on_rst_dly                        ;

    // user apb configure signals
    wire                tl_cfg_prst                             ;
    wire                tl_cfg_penable                          ;
    wire                tl_cfg_psel                             ;
    wire                tl_cfg_pwrite                           ;
    wire  [2:0]         tl_cfg_pprot                            ;
    wire  [31:0]        tl_cfg_paddr                            ;
    wire  [3:0]         tl_cfg_pstrb                            ;
    wire  [31:0]        tl_cfg_pwdata                           ;
    wire                tl_cfg_pready                           ;
    wire  [31:0]        tl_cfg_prdata                           ;
    wire                tl_cfg_pslverr                          ;

    wire  [7:0]         tl_cfg_tcvc                             ;
    wire  [12:0]        tl_cfg_busdev                           ;
    wire  [2:0]         tl_cfg_max_payload_size                 ;
    wire  [2:0]         tl_cfg_max_read_request_size            ;
    wire  [2:0]         tl_cfg_current_link_speed               ;
    wire  [3:0]         tl_cfg_negotiated_width                 ;
    wire                tl_cfg_read_completion_boundary         ;
    wire  [15:0]        tl_cfg_pfregs_cmd                       ;
    wire  [7:0]         tl_cfg_pf0_primary_bus = 8'd0           ;
    wire  [7:0]         tl_cfg_pf1_primary_bus = 8'd0           ;
    wire  [7:0]         tl_cfg_pf2_primary_bus = 8'd0           ;
    wire  [7:0]         tl_cfg_pf3_primary_bus = 8'd0           ;

    // physical ltssm signals
    wire  [1:0]         pl_equ_phase                            ;
    wire  [4:0]         tl_ltssm                                ;
    wire  [4:0]         pl_ltssm                                ;
    wire                pl_link_up                              ;
    wire                tl_ltssm_enable                         =1'b1;

    // Rx interface
    wire                tl_rx_wait                              ;
    wire                tl_rx_masknp                            ;
    wire  [47:0]        tl_rx_bardec                            ;
    wire  [511:0]       tl_rx_data                              ;
    wire                tl_rx_eop                               ;
    wire  [7:0]         tl_rx_err                               ;
    wire  [11:0]        tl_rx_mchit                             ;
    wire                tl_rx_sop                               ;
    wire  [15:0]        tl_rx_valid                             ;

    // TX interface
    wire  [511:0]       tl_tx_data                              ;
    wire                tl_tx_eop                               ;
    wire  [7:0]         tl_tx_err                               ;
    wire                tl_tx_sop                               ;
    wire                tl_tx_stream                            ;
    wire  [15:0]        tl_tx_valid                             ;
    wire                tl_tx_wait                              ;
    wire  [95:0]        tl_tx_credits                           ;

   `ifdef PH2_PCIE_LEGACY_INT_ENABLE
    wire  [3:0]         tl_int_status                           ;
    wire  [3:0]         tl_int_pincontrol                       ;
    wire  [3:0]         tl_int_pinstate                         ;
  `endif

  `ifdef PH2_PCIE_MSI_INT_ENABLE
    wire  [3:0]         tl_int_status                           ;
    wire  [3:0]         tl_int_msireq                           ;
    wire  [19:0]        tl_int_msinum                           ;
    wire  [3:0]         tl_int_msiack                           ;
    wire  [3:0]         tl_int_msi_enable                       ;
    wire  [11:0]        tl_int_msi_multi_enable                 ;
    wire  [31:0]        tl_int_pf0_msi_pending                  ;
    wire  [31:0]        tl_int_pf1_msi_pending                  ;
    wire  [31:0]        tl_int_pf2_msi_pending                  ;
    wire  [31:0]        tl_int_pf3_msi_pending                  ;
    wire  [31:0]        tl_int_pf0_msi_mask                     ;
    wire  [31:0]        tl_int_pf1_msi_mask                     ;
    wire  [31:0]        tl_int_pf2_msi_mask                     ;
    wire  [31:0]        tl_int_pf3_msi_mask                     ;
  `endif

  `ifdef PH2_PCIE_MSIX_INT_ENABLE
    wire  [3:0]         tl_cfg_msix_enable                      ;
    wire  [3:0]         tl_cfg_msix_function_mask               ;
  `endif

    // Ubus
    wire                ubus_pcie_wen                           ;
    wire  [31:0]        ubus_pcie_waddr                         ;
    wire  [31:0]        ubus_pcie_wdata                         ;
    wire                ubus_pcie_ren                           ;
    wire  [31:0]        ubus_pcie_raddr                         ;
    wire                ubus_pcie_bken                          ;
    wire  [31:0]        ubus_pcie_rdata                         ;

    wire                ubus_hxt_wen                            ;
    wire  [31:0]        ubus_hxt_waddr                          ;
    wire  [31:0]        ubus_hxt_wdata                          ;
    wire                ubus_hxt_ren                            ;
    wire  [31:0]        ubus_hxt_raddr                          ;
    wire                ubus_hxt_bken                           ;
    wire  [31:0]        ubus_hxt_rdata                          ;

    // ubus to logic
    wire                ubus_wen_logic                          ;
    wire  [31:0]        ubus_waddr_logic                        ;
    wire  [31:0]        ubus_wdata_logic                        ;
    wire                ubus_ren_logic                          ;
    wire  [31:0]        ubus_raddr_logic                        ;
    wire                ubus_bken_logic                         ;
    wire  [31:0]        ubus_rdata_logic                        ;

    // To PHY0 APB
    wire                hxt_phy0_penable                        ;
    wire                hxt_phy0_psel                           ;
    wire                hxt_phy0_pwrite                         ;
    wire    [2:0]       hxt_phy0_pprot                          ;
    wire    [31:0]      hxt_phy0_paddr                          ;
    wire    [3:0]       hxt_phy0_pstrb                          ;
    wire    [31:0]      hxt_phy0_pwdata                         ;
    wire                hxt_phy0_pready                         ;
    wire    [31:0]      hxt_phy0_prdata                         ;
    wire                hxt_phy0_pslverr                        ;

    // To PHY1 APB
    wire                hxt_phy1_penable                        ;
    wire                hxt_phy1_psel                           ;
    wire                hxt_phy1_pwrite                         ;
    wire    [2:0]       hxt_phy1_pprot                          ;
    wire    [31:0]      hxt_phy1_paddr                          ;
    wire    [3:0]       hxt_phy1_pstrb                          ;
    wire    [31:0]      hxt_phy1_pwdata                         ;
    wire                hxt_phy1_pready                         ;
    wire    [31:0]      hxt_phy1_prdata                         ;
    wire                hxt_phy1_pslverr                        ;

    wire  [3:0]         tl_int_msix_trigger                     ;
    /*

   (*MARK_DEBUG = "true"*)wire       [1:0]             device_version_o     ;     
    
   PH2_LOGIC_DEVICE_VERSION  PH2_LOGIC_DEVICE_VERSION_inst(
       
   . device_version_o     ( device_version_o)
   
   );   
   */ 

// ====================================================================
// PCIe Controller Clock & Reset Generate
// ====================================================================

//--------------------------------------------
// clock logic
//--------------------------------------------
pcie_pll_ep u_pcie_pll_ep(
  .clk_in0                                  (sys_clk                    ),
  .pll_reset                                (!pcie_power_on_rst         ),
  .lock                                     (pcie_pll_locked            ),
  .clk0_out                                 (uart_clk                   ),
  .clk1_out                                 (tl_clk_user                )
);

assign  tl_clk_user_freq    = `EP_TL_CLK_REQ;

assign  hxt_apb4_pclk_in    = uart_clk;

//--------------------------------------------
// reset logic
//--------------------------------------------
// pcie controller reset, it's controlled by pad pin named pcie_power_on_rst
// and rc goldfinger reset
always@( posedge tl_clk_user or negedge pcie_power_on_rst)
begin
    if( !pcie_power_on_rst ) begin
        power_on_rst_dly <= 1'b1;
    end else begin
        power_on_rst_dly <= !pcie_mperst;
    end
end

// user logic reset, when pcie controller has release reset, it's not mean can
// send or receive tlp, it should wait pcie controller read and link up
ph2_pcie_rst_sync#(
    .LTSSM_VAULE                             (5'h10                                   )
) u_ph2_pcie_rst_sync(
    .clk                                     (tl_clk_user                             ),
    .rst                                     (power_on_rst_dly                        ),
    .tl_ltssm                                (tl_ltssm                                ),
    .pl_link_up                              (pl_link_up&tl_clk_locked&pcie_pll_locked),
    .rst_sync                                (tl_rst_user                             )
);

// ====================================================================
// PCIE IP Inst
// ====================================================================
ph2_pcie_ep_subsystem u_ph2_pcie_ep_subsystem(
    // serdes high speed pin
    .ref_pad_clk_p                           (ref_pad_clk_p                           ),
    .ref_pad_clk_n                           (ref_pad_clk_n                           ),
    .pcie_rx_p                               (pcie_rx_p                               ),
    .pcie_rx_n                               (pcie_rx_n                               ),
    .pcie_tx_p                               (pcie_tx_p                               ),
    .pcie_tx_n                               (pcie_tx_n                               ),

    // transcation layer clock signals
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_clk_locked                           (tl_clk_locked                           ),

    // clock and reset signals
    .tl_clk_gate                             (tl_clk_gate                             ),
    .tl_clk_user_freq                        (tl_clk_user_freq                        ),
    .tl_power_on_rst                         (power_on_rst_dly                        ),

    // user apb configure signals
    .tl_cfg_penable                          (tl_cfg_penable                          ),
    .tl_cfg_psel                             (tl_cfg_psel                             ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                           ),
    .tl_cfg_pprot                            (tl_cfg_pprot                            ),
    .tl_cfg_paddr                            (tl_cfg_paddr                            ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                            ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                           ),
    .tl_cfg_pready                           (tl_cfg_pready                           ),
    .tl_cfg_prdata                           (tl_cfg_prdata                           ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                          ),

    // cfg direct access
    .tl_cfg_tcvc                             (tl_cfg_tcvc                             ),
    .tl_cfg_busdev                           (tl_cfg_busdev                           ),
    .tl_cfg_max_payload_size                 (tl_cfg_max_payload_size                 ),
    .tl_cfg_max_read_request_size            (tl_cfg_max_read_request_size            ),
    .tl_cfg_current_link_speed               (tl_cfg_current_link_speed               ),
    .tl_cfg_negotiated_width                 (tl_cfg_negotiated_width                 ),
    .tl_cfg_read_completion_boundary         (tl_cfg_read_completion_boundary         ),
    .tl_cfg_pfregs_cmd                       (tl_cfg_pfregs_cmd                       ),
    .tl_cfg_pf0_primary_bus                  (tl_cfg_pf0_primary_bus                  ),
    .tl_cfg_pf1_primary_bus                  (tl_cfg_pf1_primary_bus                  ),
    .tl_cfg_pf2_primary_bus                  (tl_cfg_pf2_primary_bus                  ),
    .tl_cfg_pf3_primary_bus                  (tl_cfg_pf3_primary_bus                  ),

    // pf legacy int / msi
    `ifdef PH2_PCIE_LEGACY_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_pincontrol                       (tl_int_pincontrol                       ),
    .tl_int_pinstate                         (tl_int_pinstate                         ),
    `endif

    `ifdef PH2_PCIE_MSI_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_msireq                           (tl_int_msireq                           ),
    .tl_int_msinum                           (tl_int_msinum                           ),
    .tl_int_msiack                           (tl_int_msiack                           ),
    .tl_int_msi_enable                       (tl_int_msi_enable                       ),
    .tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 ),
    .tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  ),
    .tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  ),
    .tl_int_pf2_msi_pending                  (tl_int_pf2_msi_pending                  ),
    .tl_int_pf3_msi_pending                  (tl_int_pf3_msi_pending                  ),
    .tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     ),
    .tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     ),
    .tl_int_pf2_msi_mask                     (tl_int_pf2_msi_mask                     ),
    .tl_int_pf3_msi_mask                     (tl_int_pf3_msi_mask                     ),
    `endif

    // pf msi
    `ifdef PH2_PCIE_MSIX_INT_ENABLE
    .tl_cfg_msix_enable                      (tl_cfg_msix_enable                      ),
    .tl_cfg_msix_function_mask               (tl_cfg_msix_function_mask               ),
    `endif

    // physical ltssm signals
    .pl_equ_phase                            (pl_equ_phase                            ),
    .tl_ltssm                                (tl_ltssm                                ),
    .pl_ltssm                                (pl_ltssm                                ),
    .pl_link_up                              (pl_link_up                              ),
    .tl_ltssm_enable                         (tl_ltssm_enable                         ),

    // Rx interface
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),

    // TX interface
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           ),

    .hxt_apb4_pclk_in                        (hxt_apb4_pclk_in                        ),
    .phy0_master_apb4_paddr_in               (hxt_phy0_paddr                          ),
    .phy0_master_apb4_penable_in             (hxt_phy0_penable                        ),
    .phy0_master_apb4_pprot_in               (hxt_phy0_pprot                          ),
    .phy0_master_apb4_psel_in                (hxt_phy0_psel                           ),
    .phy0_master_apb4_pstrobe_in             (hxt_phy0_pstrb                          ),
    .phy0_master_apb4_pwdata_in              (hxt_phy0_pwdata                         ),
    .phy0_master_apb4_pwrite_in              (hxt_phy0_pwrite                         ),
    .phy0_master_apb4_prdata_out             (hxt_phy0_prdata                         ),
    .phy0_master_apb4_pready_out             (hxt_phy0_pready                         ),
    .phy0_master_apb4_pslverr_out            (hxt_phy0_pslverr                        ),
    .phy1_master_apb4_paddr_in               (hxt_phy1_paddr                          ),
    .phy1_master_apb4_penable_in             (hxt_phy1_penable                        ),
    .phy1_master_apb4_pprot_in               (hxt_phy1_pprot                          ),
    .phy1_master_apb4_psel_in                (hxt_phy1_psel                           ),
    .phy1_master_apb4_pstrobe_in             (hxt_phy1_pstrb                          ),
    .phy1_master_apb4_pwdata_in              (hxt_phy1_pwdata                         ),
    .phy1_master_apb4_pwrite_in              (hxt_phy1_pwrite                         ),
    .phy1_master_apb4_prdata_out             (hxt_phy1_prdata                         ),
    .phy1_master_apb4_pready_out             (hxt_phy1_pready                         ),
    .phy1_master_apb4_pslverr_out            (hxt_phy1_pslverr                        )
);

pcie_ep_engine u_pcie_ep_engine(

    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),
    // Rx interface
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),
`ifdef PH2_PCIE_MSIX_INT_ENABLE
    .tl_int_msix_trigger                     (tl_int_msix_trigger                     ),
`else
    .tl_int_msix_trigger                     (4'b0                                    ),
`endif
    // TX interface
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           ),
    .tl_cfg_busdev                           (tl_cfg_busdev                           )
);

pcie_ep_int_handle u_pcie_ep_int_handle(
    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             )
   ,.tl_rst_user                             (tl_rst_user                             )
   ,.user_int_trigger                        (!user_int_trigger                       )
`ifdef PH2_PCIE_LEGACY_INT_ENABLE
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_pincontrol                       (tl_int_pincontrol                       )
   ,.tl_int_pinstate                         (tl_int_pinstate                         )
`endif
`ifdef PH2_PCIE_MSI_INT_ENABLE
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_msireq                           (tl_int_msireq                           )
   ,.tl_int_msinum                           (tl_int_msinum                           )
   ,.tl_int_msiack                           (tl_int_msiack                           )
   ,.tl_int_msi_enable                       (tl_int_msi_enable                       )
   ,.tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 )
   ,.tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  )
   ,.tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  )
   ,.tl_int_pf2_msi_pending                  (tl_int_pf2_msi_pending                  )
   ,.tl_int_pf3_msi_pending                  (tl_int_pf3_msi_pending                  )
   ,.tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     )
   ,.tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     )
   ,.tl_int_pf2_msi_mask                     (tl_int_pf2_msi_mask                     )
   ,.tl_int_pf3_msi_mask                     (tl_int_pf3_msi_mask                     )
`endif
`ifdef PH2_PCIE_MSIX_INT_ENABLE
   ,.tl_int_msix_trigger                     (tl_int_msix_trigger                     )
`endif
);

pcie_uart
#(
    .BAUDRATE                                (115200                                   ),
    .CLK_RATE                                (20                                       )// Period
)u_pcie_uart (
    .aux_clk                                 (uart_clk                                 ),
    .core_clk                                (tl_clk_user                              ),
    .rst_n                                   (power_on_rst_dly                         ),

    .rx                                      (rxd                                      ),
    .tx                                      (txd                                      ),

    .ubus_pcie_wen                           (ubus_pcie_wen                            ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                          ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                          ),
    .ubus_pcie_ren                           (ubus_pcie_ren                            ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                          ),
    .ubus_pcie_bken                          (ubus_pcie_bken                           ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                          ),

    .ubus_hxt_wen                            (ubus_hxt_wen                             ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                           ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                           ),
    .ubus_hxt_ren                            (ubus_hxt_ren                             ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                           ),
    .ubus_hxt_bken                           (ubus_hxt_bken                            ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                           )
);

ep_ubus_bridge u_ep_ubus_bridge(
    .tl_clk_user                             (tl_clk_user                            ),
    .uart_clk                                (uart_clk                               ),
    // lpbk register config must before link up, so the rst signal of ubus_bridge must
    // use the origin rst from pad
    .rst                                     (power_on_rst_dly                       ),
    .tl_clk_locked                           (tl_clk_locked                          ),

    // pcie Ubus
    .ubus_pcie_wen                           (ubus_pcie_wen                          ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                        ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                        ),
    .ubus_pcie_ren                           (ubus_pcie_ren                          ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                        ),
    .ubus_pcie_bken                          (ubus_pcie_bken                         ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                        ),

    // hxt Ubus
    .ubus_hxt_wen                            (ubus_hxt_wen                           ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                         ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                         ),
    .ubus_hxt_ren                            (ubus_hxt_ren                           ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                         ),
    .ubus_hxt_bken                           (ubus_hxt_bken                          ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                         ),

    // To fabric logic
    .ubus_wen_logic                          (ubus_wen_logic                         ),
    .ubus_waddr_logic                        (ubus_waddr_logic                       ),
    .ubus_wdata_logic                        (ubus_wdata_logic                       ),
    .ubus_ren_logic                          (ubus_ren_logic                         ),
    .ubus_raddr_logic                        (ubus_raddr_logic                       ),
    .ubus_bken_logic                         (ubus_bken_logic                        ),
    .ubus_rdata_logic                        (ubus_rdata_logic                       ),

    // To PCIe APB
    .tl_cfg_prst                             (tl_cfg_prst                            ),
    .tl_cfg_penable                          (tl_cfg_penable                         ),
    .tl_cfg_psel                             (tl_cfg_psel                            ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                          ),
    .tl_cfg_pprot                            (tl_cfg_pprot                           ),
    .tl_cfg_paddr                            (tl_cfg_paddr                           ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                           ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                          ),
    .tl_cfg_pready                           (tl_cfg_pready                          ),
    .tl_cfg_prdata                           (tl_cfg_prdata                          ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                         ),

    // To PHY0 APB
    .hxt_phy0_penable                        (hxt_phy0_penable                        ),
    .hxt_phy0_psel                           (hxt_phy0_psel                           ),
    .hxt_phy0_pwrite                         (hxt_phy0_pwrite                         ),
    .hxt_phy0_pprot                          (hxt_phy0_pprot                          ),
    .hxt_phy0_paddr                          (hxt_phy0_paddr                          ),
    .hxt_phy0_pstrb                          (hxt_phy0_pstrb                          ),
    .hxt_phy0_pwdata                         (hxt_phy0_pwdata                         ),
    .hxt_phy0_pready                         (hxt_phy0_pready                         ),
    .hxt_phy0_prdata                         (hxt_phy0_prdata                         ),
    .hxt_phy0_pslverr                        (hxt_phy0_pslverr                        ),

    // To PHY1 APB
    .hxt_phy1_penable                        (hxt_phy1_penable                        ),
    .hxt_phy1_psel                           (hxt_phy1_psel                           ),
    .hxt_phy1_pwrite                         (hxt_phy1_pwrite                         ),
    .hxt_phy1_pprot                          (hxt_phy1_pprot                          ),
    .hxt_phy1_paddr                          (hxt_phy1_paddr                          ),
    .hxt_phy1_pstrb                          (hxt_phy1_pstrb                          ),
    .hxt_phy1_pwdata                         (hxt_phy1_pwdata                         ),
    .hxt_phy1_pready                         (hxt_phy1_pready                         ),
    .hxt_phy1_prdata                         (hxt_phy1_prdata                         ),
    .hxt_phy1_pslverr                        (hxt_phy1_pslverr                        )
);

// Debug Logic
    reg                 ubus_wen_logic_dly                          ;
    reg   [31:0]        ubus_waddr_logic_dly                        ;
    reg   [31:0]        ubus_wdata_logic_dly                        ;
    reg                 ubus_ren_logic_dly                          ;
    reg   [31:0]        ubus_raddr_logic_dly                        ;
    reg                 ubus_bken_logic_dly                         =1'b0;
    reg   [31:0]        ubus_rdata_logic_dly                        =32'd0;

    reg   [31:0]        rd_data0                                    ;
    reg   [31:0]        rd_data1                                    ;
    reg   [31:0]        rd_data2                                    ;
    reg   [31:0]        rd_data3                                    ;
    reg   [31:0]        rd_data4                                    ;

    reg   [4:0]         ltssm_reg                                   =5'd0;
    reg   [4:0]         ltssm_reg_dly                               =5'd0;
    reg   [4:0]         ltssm_debug[19:0]                           ;
    reg   [31:0]        ltssm_change_cnt                            ;

assign  ubus_bken_logic = ubus_bken_logic_dly ;
assign  ubus_rdata_logic= ubus_rdata_logic_dly;

always@(posedge tl_clk_user )
begin
    ubus_wen_logic_dly   <= ubus_wen_logic   ;
    ubus_waddr_logic_dly <= ubus_waddr_logic ;
    ubus_wdata_logic_dly <= ubus_wdata_logic ;
    ubus_ren_logic_dly   <= ubus_ren_logic   ;
    ubus_raddr_logic_dly <= ubus_raddr_logic ;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly )
        ubus_bken_logic_dly <= 1'b0;
    else
        ubus_bken_logic_dly  <= ubus_bken_logic_dly  ? 1'b0 :
                                ubus_ren_logic_dly   ? 1'b1 : ubus_bken_logic_dly;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_reg     <= 5'd0;
        ltssm_reg_dly <= 5'd0;
    end else begin
        ltssm_reg     <= tl_ltssm;
        ltssm_reg_dly <= ltssm_reg;
    end
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly )
        ltssm_change_cnt <= 5'd0;
    else if( ltssm_reg != ltssm_reg_dly)
        ltssm_change_cnt <= ltssm_change_cnt + 1'b1;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_debug[0]  <= 5'b0;
        ltssm_debug[1]  <= 5'b0;
        ltssm_debug[2]  <= 5'b0;
        ltssm_debug[3]  <= 5'b0;
        ltssm_debug[4]  <= 5'b0;
        ltssm_debug[5]  <= 5'b0;
        ltssm_debug[6]  <= 5'b0;
        ltssm_debug[7]  <= 5'b0;
        ltssm_debug[8]  <= 5'b0;
        ltssm_debug[9]  <= 5'b0;
        ltssm_debug[10] <= 5'b0;
        ltssm_debug[11] <= 5'b0;
        ltssm_debug[12] <= 5'b0;
        ltssm_debug[13] <= 5'b0;
        ltssm_debug[14] <= 5'b0;
        ltssm_debug[15] <= 5'b0;
        ltssm_debug[16] <= 5'b0;
        ltssm_debug[17] <= 5'b0;
        ltssm_debug[18] <= 5'b0;
        ltssm_debug[19] <= 5'b0;
    end else if( ltssm_reg != ltssm_reg_dly ) begin
        ltssm_debug[ltssm_change_cnt] <= ltssm_reg_dly;
    end
end

// read logic
always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly) begin
        rd_data0 <= 32'd0;
        rd_data1 <= 32'd0;
        rd_data2 <= 32'd0;
        rd_data3 <= 32'd0;
        ubus_rdata_logic_dly <= 32'd0;
    end else begin
        rd_data0             <= {27'b0,tl_ltssm[4:0]};
        rd_data1             <= {pl_link_up,11'd0,tl_clk_locked,2'd0,1'b0,
                                 12'd0,4'd0};
        rd_data2             <= {23'b0,tl_clk_user_freq[8:0]};
        rd_data3             <= {5'd0,tl_cfg_max_read_request_size[2:0],5'd0,tl_cfg_max_payload_size[2:0],
                                 5'd0,tl_cfg_current_link_speed[2:0],   4'd0,tl_cfg_negotiated_width[3:0]};
        case(ubus_raddr_logic_dly[7:0])
            8'd0 : ubus_rdata_logic_dly <= rd_data0;
            8'd1 : ubus_rdata_logic_dly <= rd_data1;
            8'd2 : ubus_rdata_logic_dly <= rd_data2;
            8'd3 : ubus_rdata_logic_dly <= rd_data3;
            8'd4 : ubus_rdata_logic_dly <= rd_data3;
            8'd5 : ubus_rdata_logic_dly <= rd_data3;//tl_rx_data[31:0];
            8'd6 : ubus_rdata_logic_dly <= ltssm_change_cnt;
            8'd10: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[0]};
            8'd11: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[1]};
            8'd12: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[2]};
            8'd13: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[3]};
            8'd14: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[4]};
            8'd15: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[5]};
            8'd16: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[6]};
            8'd17: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[7]};
            8'd18: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[9]};
            8'd19: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[10]};
            8'd20: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[11]};
            8'd21: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[12]};
            8'd22: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[13]};
            8'd23: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[14]};
            8'd24: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[15]};
            8'd25: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[16]};
            8'd26: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[17]};
            8'd27: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[18]};
            8'd28: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[19]};
        default:;
        endcase
    end
end

assign  debug_led[0] = power_on_rst_dly;
assign  debug_led[1] = pl_link_up;
assign  debug_led[2] = tl_clk_locked;
assign  debug_led[3] = ltssm_reg_dly[4];
assign  debug_led[4] = ltssm_reg_dly[3];
assign  debug_led[5] = ltssm_reg_dly[2];
assign  debug_led[6] = ltssm_reg_dly[1];
assign  debug_led[7] = ltssm_reg_dly[0];

endmodule