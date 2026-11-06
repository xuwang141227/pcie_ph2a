quit -sim

if [file exists work] { 
    file delete -force work 
    } 

if {![file exists work]} { 
    vlib work 
    }

# -----------------------------------------------------
# tb 
# -----------------------------------------------------
vlog \
    -sv                                                                  \
    +incdir+../../Rtl/common/                                            \
    +incdir+../tb/                                                       \
    ../tb/pcie_subsystem_tb.v                                            \
    ../tb/ubus_model_fast.v                                               

# -----------------------------------------------------
# common 
# -----------------------------------------------------
vlog  \
    +incdir+../../Rtl/common/                                            \
    +incdir+../tb/                                                       \
    ../../Rtl/common/ph2_pcie_rst_sync.v                                 \
    ../../Rtl/common/eram.v                                              \
    ../../Rtl/common/ubus/pcie_uart.v                                    \
    ../../Rtl/common/ubus/bps_setting.v                                  \
    ../../Rtl/common/ubus/uart_rx_setting.v                              \
    ../../Rtl/common/ubus/uart_tx_setting.v                              \
    ../../Rtl/common/ubus/uart_cdc.v                                     \
    ../../Rtl/common/ubus/pcie_uprotocol.v                               \
    ../../Rtl/common/ubus2pcie_apb.v                                     \
    ../../Rtl/common/ubus2phy_apb.v                                      

# -----------------------------------------------------
# pcie rc side
# -----------------------------------------------------
vlog \
    ../../Rtl/rc_side/ph2_pcie_rc_top.v                                 \
    ../../Prj/case_rc/al_ip/ph2_pcie_rc_subsystem.v                     \
    ../../Prj/case_rc/al_ip/pcie_pll_rc.v                               \
    ../../Rtl/rc_side/pcie_rc_tx_engine.v                               \
    ../../Rtl/rc_side/pcie_rc_rx_engine.v                               \
    ../../Rtl/rc_side/pcie_rc_int_handle.v                              \
    ../../Rtl/rc_side/ubus_bridge/rc_ubus_bridge.v                      \
    ../../Rtl/rc_side/ubus_bridge/ubus2tlp.v                            \
    ../../Rtl/rc_side/pcie_prbs/prbs_chk_pcie.v                         \
    ../../Rtl/rc_side/pcie_prbs/prbs_gen_pcie.v                         \
    ../../Rtl/rc_side/si5344_5345/count_rst_n.v                         \
    ../../Rtl/rc_side/si5344_5345/debounce.v                            \
    ../../Rtl/rc_side/si5344_5345/i2c_timing_ctrl.v                     \
    ../../Rtl/rc_side/si5344_5345/si5344_5345.v                         \
    ../../Rtl/rc_side/si5344_5345/Si5345-RevD-Out9-100Mhz-Registers.v   

# -----------------------------------------------------
# pcie ep side
# -----------------------------------------------------
vlog \
    ../../Rtl/ep_side/ph2_pcie_ep_top.v                                 \
    ../../Prj/case_ep/al_ip/ph2_pcie_ep_subsystem.v                     \
    ../../Prj/case_ep/al_ip/pcie_pll_ep.v                               \
    ../../Rtl/ep_side/pcie_ep_engine.v                                  \
    ../../Rtl/ep_side/pcie_ep_int_handle.v                              \
    ../../Rtl/ep_side/ubus_bridge/ep_ubus_bridge.v                      

# -----------------------------------------------------
# hxt ip
# -----------------------------------------------------
vlog \
    -sv                                                                  \
    +define+FAST_SIM                                                     \
    +define+AWAVE_BUMPS_AS_LOGIC_NRZ                                     \
    -svinputport=relaxed                                                 \
    -suppress 13215 -suppress 13174 -suppress 2583                       \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_hxt_v1.sv


# -----------------------------------------------------
# pcie ip and other lib ip
# -----------------------------------------------------
vlog \
    -sv                                                                             \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/common/al_phy_glbl.v   \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_gsr.v      \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_sbuf.v     \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_pll.v      \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_hpiol.sv   \
    /software1/yywang/td_rel/TD_6.2.2_Engineer_186082/sim_release/ph2/ph2_phy_pcie_v1.sv 
 
#/users/dxguo/Workdir/project/bring_up/AL7000/PCIE/pcie_simmodel/simmodel_gen/ph2_phy_pcie_v1.origin.sv
# -----------------------------------------------------
# Start evaluation test 
# -----------------------------------------------------
vsim +nospecify -t 1fs -suppress 3009 -suppress 8630 -suppress 8604 -vopt -voptargs="+acc" -nowlfopt -t 1ps pcie_subsystem_tb -l log.txt -do "log -r *"







# -----------------------------------------------------
# View the simulation results 
# -----------------------------------------------------
# View the simulation results 
view structure 
view signals 
view wave
do   wave.do
run -all
