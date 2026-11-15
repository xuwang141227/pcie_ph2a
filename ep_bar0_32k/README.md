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

## 1080p image DMA implementation draft

The overlay includes a BAR2 image-DMA controller in
`Rtl/ep_side/pcie_ep_image_dma.v` and a focused testbench. It generates six
RGB888 test patterns, writes frames to two host DMA slots, and signals frame
completion through the configured Legacy INTA path. The current RTL defaults
to 300,000,000 user-clock cycles per frame; confirm the actual user clock before
assuming this is one second.

Run the DMA unit simulation from the repository root:

```sh
iverilog -g2012 -Wall -I ep_bar0_32k/Design/Rtl/common \
  -s pcie_ep_image_dma_tb -o /tmp/pcie_ep_image_dma_tb \
  ep_bar0_32k/Design/Sim/tb/pcie_ep_image_dma_tb.v \
  ep_bar0_32k/Design/Rtl/ep_side/pcie_ep_image_dma.v
vvp /tmp/pcie_ep_image_dma_tb
```

The Linux driver is in `driver/`; build it against the headers for the target
host kernel with `make -C driver`. Install `tools/requirements.txt` in a Python
environment that provides Tkinter, then run `python3 tools/pcie_image_gui.py`
with permission to open `/dev/pcie_image*`. Bind the new driver only after
unbinding any existing driver for the device.

This is an implementation draft, not a board-validated release. The driver
build, vendor synthesis/timing, host DMA visibility ordering, actual Legacy
interrupt behavior, negotiated link, and full-frame image correctness still
require validation on the target Linux host and PH2A board.
