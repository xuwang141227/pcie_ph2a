//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph2_pcie_case_param.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-02-09 10:54:25
//  Create        : 2023-02-06 15:50:55
//  Description   : 
//   
///////////////////////////////////////////////////////////////


//`ifndef PH2_PCIE_CASE_PARAM___H
//`define PH2_PCIE_CASE_PARAM___H

    // rc project redef 
    `define     RC_TL_CLK_REQ               9'd300
    
    
    // ep project  redef 
    `define     EP_TL_CLK_REQ               9'd300

    // Interrupt Sel, only enable one of them
    `define   PH2_PCIE_LEGACY_INT_ENABLE
    //`define   PH2_PCIE_MSI_INT_ENABLE
    //`define   PH2_PCIE_MSIX_INT_ENABLE
    
    
    //`define     ERROR_DEBUG
    
    


//`endif  //PH2_PCIE_CASE_PARAM___H
