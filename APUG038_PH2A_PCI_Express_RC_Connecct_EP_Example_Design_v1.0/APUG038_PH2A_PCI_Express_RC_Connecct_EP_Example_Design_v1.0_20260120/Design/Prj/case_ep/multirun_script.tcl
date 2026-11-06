# Tcl script created by Tang Dynasty Release_2026.2

import_device  -package  -speed 2
open_project {ph2_pcie_ep_top.al}
# Reset all syn/phy runs by default.
reset_runs { syn_1 }
# Launch all runs by default.
# Note that runs need to be reset first before launch.
launch_runs { syn_1 phy_1 } -jobs 2
# Waiting runs to finish one by one.
# Note that all launched runs before need to call this tcl command
wait_run syn_1 -quiet
wait_run phy_1 -quiet
save_best_bits
exit
