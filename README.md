# PCIe PH2A EP BAR0 32 KiB demo

The original APUG038 demo files are unchanged. The BAR0 RTL/configuration
overlay, focused simulator testbench, and integration instructions are in
[`ep_bar0_32k/`](ep_bar0_32k/README.md).

## Ubuntu BAR0 GUI

`tools/bar0_gui.py` discovers the APUG038 EP (`1edb:abcd`) and maps Linux
`resource0` for byte-level reads and writes. It supports a user-selected
offset and length from 1 to 32768 bytes:

```sh
sudo apt install python3-tk
sudo python3 tools/bar0_gui.py
```

Enter the BAR0 offset (decimal or `0x`-prefixed), byte length, and for writes
exactly that many hexadecimal bytes. Access requires a 32 KiB BAR0 assigned by
the host and an accessible `resource0`; the GUI does not unbind kernel drivers
or change PCI configuration.
