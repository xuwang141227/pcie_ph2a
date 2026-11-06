# PH2A EP BAR0 32 KiB implementation

This directory is an implementation overlay based on the APUG038 EP demo.
The APUG038 source directory in the repository is left unchanged. This overlay
contains the updated EP transaction engine, BAR0 IP configuration and generated
wrapper, a focused testbench, and the common RTL files required to run that
testbench.

## Simulation

From this directory, run:

```sh
cd Design
iverilog -g2012 -Wall -I Rtl/common -s ep_bar0_32k_tb \
  -o /tmp/ep_bar0_32k_tb \
  Sim/tb/ep_bar0_32k_tb.v Rtl/ep_side/pcie_ep_engine.v Rtl/common/eram.v
vvp /tmp/ep_bar0_32k_tb
```

The test checks BAR0 upper-bound access, bank crossing, multi-beat memory
transfers, and byte enables. The full APUG038 RC/EP link-level test requires
the vendor PCIe IP simulation models and is not included in this overlay.

## Integrating into a hardware build

Use the files in this overlay as the updated EP implementation sources when
building a separate APUG038 working copy. The BAR0 is a non-prefetchable
32-bit memory BAR with a 32 KiB aperture (`mask = 32'hffff8000`). Regenerate
the subsystem from `Design/Prj/case_ep/al_ip/ph2_pcie_ep_subsystem.ipc` using
the Anlogic tool before rebuilding the FPGA image. Do not mix the 32 KiB
software interface with a bitstream built using the original 1 MiB BAR.

The EP is configured as vendor/device `1edb:abcd`.
