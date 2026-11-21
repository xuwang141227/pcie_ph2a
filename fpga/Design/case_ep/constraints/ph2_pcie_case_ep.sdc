create_clock -name sys_clk 	   -period 40 -waveform {0 20} [get_ports {sys_clk}]

derive_clocks
rename_clock -name {uart_clk}    -source [get_ports {sys_clk}] -master_clock {sys_clk} [get_pins {u_pcie_pll_ep/pll_inst.clkc[0]}]
rename_clock -name {tl_clk_user} -source [get_ports {sys_clk}] -master_clock {sys_clk} [get_pins {u_pcie_pll_ep/pll_inst.clkc[1]}]