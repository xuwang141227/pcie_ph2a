//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_ep_int_handle.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-11-01 10:45:51
//  Create        : 2022-07-21 09:26:26
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

`include "../common/ph2_pcie_case_param.v"


module  pcie_ep_int_handle(

    // Clock and Reset
     input       wire                tl_clk_user            
    ,input       wire                tl_rst_user                

    ,input       wire                user_int_trigger       

`ifdef PH2_PCIE_LEGACY_INT_ENABLE  
    ,output      reg   [3:0]         tl_int_status
    ,output      reg   [3:0]         tl_int_pincontrol      
    ,input       wire  [3:0]         tl_int_pinstate        
`elsif PH2_PCIE_MSI_INT_ENABLE
    ,output      reg   [3:0]         tl_int_status
    ,output      reg   [3:0]         tl_int_msireq
    ,output      reg   [19:0]        tl_int_msinum
    ,input       wire  [3:0]         tl_int_msiack
    ,input       wire  [3:0]         tl_int_msi_enable
    ,input       wire  [11:0]        tl_int_msi_multi_enable
    ,output      wire  [31:0]        tl_int_pf0_msi_pending
    ,output      wire  [31:0]        tl_int_pf1_msi_pending
    ,output      wire  [31:0]        tl_int_pf2_msi_pending
    ,output      wire  [31:0]        tl_int_pf3_msi_pending
    ,input       wire  [31:0]        tl_int_pf0_msi_mask
    ,input       wire  [31:0]        tl_int_pf1_msi_mask
    ,input       wire  [31:0]        tl_int_pf2_msi_mask
    ,input       wire  [31:0]        tl_int_pf3_msi_mask
`elsif PH2_PCIE_MSIX_INT_ENABLE
    ,output      reg   [3:0]         tl_int_msix_trigger
`endif

);



// ====================================================================
// Parameter/wire/reg
// ====================================================================

    reg   [1:0]      user_int_trigger_ff;       

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) 
            user_int_trigger_ff <= 2'b11;
          else 
            user_int_trigger_ff <= {user_int_trigger_ff[0],user_int_trigger};
    end


// ====================================================================
// PH2_PCIE_LEGACY_INT_ENABLE
// ====================================================================
`ifdef PH2_PCIE_LEGACY_INT_ENABLE

      reg   [3:0]   tl_int_pincontrol_ff;      
        
      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_pincontrol_ff <= 4'b1;      
            else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) // posedge detect
                tl_int_pincontrol_ff <= {tl_int_pincontrol_ff[2:0],tl_int_pincontrol_ff[3]};      
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_pincontrol <= 4'b0;      
                tl_int_status     <= 4'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_pincontrol <= tl_int_pincontrol_ff;      
                tl_int_status     <= 4'b1;
                $display("tb info : ep send legacy int to rc");
            end else begin 
                tl_int_pincontrol <= 4'b0;      
                tl_int_status     <= 4'b0;
            end
      end

// ====================================================================
// PH2_PCIE_MSI_INT_ENABLE
// ====================================================================
`elsif PH2_PCIE_MSI_INT_ENABLE

      reg   [3:0]   tl_int_msiack_ff;

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_msiack_ff <= 4'b0;      
            else 
                tl_int_msiack_ff <= tl_int_msiack;      
      end


      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_status     <= 4'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_status     <= 4'b1;
            end else if(tl_int_msiack_ff[0]) begin 
                tl_int_status     <= 4'b0;
                /*synthesis translate_off*/
                $display("tb info : ep send msi int to rc");
                /*synthesis translate_on*/ 
            end
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msireq     <= 4'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_msireq     <= 4'b1;
            end else begin 
                tl_int_msireq     <= 4'b0;
            end
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msinum     <=20'd0;
            end else if(tl_int_msiack_ff[0] & tl_int_status[0] ) begin // posedge detect
                tl_int_msinum     <= tl_int_msinum=='d3 ? 'd0 : tl_int_msinum + 1'b1;
            end 
      end

    assign  tl_int_pf0_msi_pending = 32'b0;  
    assign  tl_int_pf1_msi_pending = 32'b0;  
    assign  tl_int_pf2_msi_pending = 32'b0;  
    assign  tl_int_pf3_msi_pending = 32'b0;  

// ====================================================================
// PH2_PCIE_MSIX_INT_ENABLE
// ====================================================================
 `elsif PH2_PCIE_MSIX_INT_ENABLE

      reg   [3:0]   tl_int_msix_trigger_ff;      
        
      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_msix_trigger_ff <= 4'b1;      
            else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) // posedge detect
                tl_int_msix_trigger_ff <= {tl_int_msix_trigger_ff[2:0],tl_int_msix_trigger_ff[3]};      
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msix_trigger <= 4'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_msix_trigger <= tl_int_msix_trigger_ff;
                /*synthesis translate_off*/
                $display("tb info : ep send msix to rc");                
                /*synthesis translate_on*/                
            end else begin 
                tl_int_msix_trigger <= 4'b0;
            end
      end

`endif


endmodule
