//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_rc_int_handle.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-02-03 11:08:31
//  Create        : 2022-07-21 10:12:09
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

`include "../common/ph2_pcie_case_param.v"


module  pcie_rc_int_handle(

    // Clock and Reset
     input       wire                tl_clk_user            
    ,input       wire                tl_rst_user                

    // INT
    ,input		 wire                legacy_int_clear
    ,output      reg                 inta           
    ,output      reg                 intb           
    ,output      reg                 intc           
    ,output      reg                 intd           
 
`ifdef PH2_PCIE_LEGACY_INT_ENABLE                            
    ,output      wire   [3:0]        tl_int_status
    ,output      wire   [3:0]        tl_int_pincontrol      
    ,input       wire   [3:0]        tl_int_pinstate   
`endif  
      
);

// ====================================================================
// LEGACY_INT
// ====================================================================
`ifdef PH2_PCIE_LEGACY_INT_ENABLE

    reg           legacy_int_clear_ff;
    reg   [3:0]   tl_int_pinstate_ff;      
    reg   [3:0]   tl_int_pinstate_2ff;      

    assign  tl_int_pincontrol = 4'b0; // rc not send legacy int      
    assign  tl_int_status     = 4'b0; // rc not send legacy int      

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) 
            legacy_int_clear_ff <= 4'b0;
          else 
            legacy_int_clear_ff <= legacy_int_clear ;
    end

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) 
            tl_int_pinstate_ff <= 4'b0;
          else 
            tl_int_pinstate_ff  <= tl_int_pinstate;
    end

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) begin
            inta <= 1'b0;           
            intb <= 1'b0;           
            intc <= 1'b0;           
            intd <= 1'b0;           
          end else if(legacy_int_clear_ff) begin 
            inta <= 1'b0;           
            intb <= 1'b0;           
            intc <= 1'b0;           
            intd <= 1'b0;           
          end else if(!tl_int_pinstate_2ff[0] & tl_int_pinstate_ff[0]) begin 
            inta <= 1'b1;           
            $display("tb info : rc get legacy inta interrput");
          end else if(!tl_int_pinstate_2ff[1] & tl_int_pinstate_ff[1]) begin 
            intb <= 1'b1;           
            $display("tb info : rc get legacy intb interrput");
          end else if(!tl_int_pinstate_2ff[2] & tl_int_pinstate_ff[2]) begin 
            intc <= 1'b1;           
            $display("tb info : rc get legacy intc interrput");
          end else if(!tl_int_pinstate_2ff[3] & tl_int_pinstate_ff[3]) begin 
            intd <= 1'b1;           
            $display("tb info : rc get legacy intd interrput");
          end
    end

    assign  msi_ctrl_int     = 1'b0;
    assign  msi_ctrl_int_vec = 32'd0;
    
// ====================================================================
// MSI_INT
// ====================================================================
`elsif PH2_PCIE_MSI_INT_ENABLE


// ====================================================================
// MSIX_INT
// ====================================================================
`elsif PH2_PCIE_MSIX_INT_ENABLE 


`endif


endmodule
