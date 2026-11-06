
// -----------------------------------------------------
// common 
// -----------------------------------------------------
+incdir+../../Rtl/common/
../../Rtl/common/ph2_pcie_rst_sync.v
../../Rtl/common/eram.v
../../Rtl/common/ubus/pcie_uart.v
../../Rtl/common/ubus/bps_setting.v
../../Rtl/common/ubus/uart_rx_setting.v
../../Rtl/common/ubus/uart_tx_setting.v
../../Rtl/common/ubus/uart_cdc.v
../../Rtl/common/ubus/pcie_uprotocol.v
../../Rtl/common/ubus2pcie_apb.v
../../Rtl/common/ubus2phy_apb.v

// -----------------------------------------------------
// tb 
// -----------------------------------------------------
+incdir+../tb/
./pcie_subsystem_tb.v
./ubus_model_fast.v

// -----------------------------------------------------
// pcie rc side
// -----------------------------------------------------
../../Rtl/rc_side/ph2_pcie_rc_top.v
../../Prj/case_rc/al_ip/pcie_pll_rc.v
../../Prj/case_rc/al_ip/ph2_pcie_rc_subsystem.v
../../Rtl/rc_side/pcie_rc_tx_engine.v
../../Rtl/rc_side/pcie_rc_rx_engine.v
../../Rtl/rc_side/pcie_rc_int_handle.v
../../Rtl/rc_side/ubus_bridge/rc_ubus_bridge.v
../../Rtl/rc_side/ubus_bridge/ubus2tlp.v
../../Rtl/rc_side/pcie_prbs/prbs_chk_pcie.v
../../Rtl/rc_side/pcie_prbs/prbs_gen_pcie.v
../../Rtl/rc_side/si5344_5345/count_rst_n.v
../../Rtl/rc_side/si5344_5345/debounce.v
../../Rtl/rc_side/si5344_5345/i2c_timing_ctrl.v
../../Rtl/rc_side/si5344_5345/si5344_5345.v
../../Rtl/rc_side/si5344_5345/Si5345-RevD-Out9-100Mhz-Registers.v

// -----------------------------------------------------
// pcie ep side
// -----------------------------------------------------
../../Rtl/ep_side/ph2_pcie_ep_top.v
../../Prj/case_ep/al_ip/pcie_pll_ep.v
../../Prj/case_ep/al_ip/ph2_pcie_ep_subsystem.v
../../Rtl/ep_side/pcie_ep_engine.v
../../Rtl/ep_side/pcie_ep_int_handle.v
../../Rtl/ep_side/ubus_bridge/ep_ubus_bridge.v



