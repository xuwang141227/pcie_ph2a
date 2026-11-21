# PH2A PCIe 图像 DMA 工程

本分支从 APUG038 EP 示例提取了图像 DMA 所需文件，保留原厂 EP 顶层、
公共 RTL、板级约束、PLL 和 PCIe IP 配置，并整合 BAR0 测试存储实现。
原始示例和其他文件仍保留在 `copilot/ep-bar0-32k` 分支，不在本分支重复存放。

| 路径 | 内容 |
|---|---|
| `fpga/Design/Prj/case_ep/ph2_pcie_ep_top.al` | Tang Dynasty EP 工程入口 |
| `fpga/Design/Prj/case_ep/al_ip/` | PCIe、PLL IP 配置及原厂生成文件 |
| `fpga/Design/Prj/case_ep/constraints/` | 板级引脚和时序约束 |
| `fpga/Design/Rtl/` | 原厂 EP 基础 RTL、BAR0 引擎和图像 DMA RTL |
| `fpga/Design/Sim/tb/` | BAR0 和图像 DMA 定向仿真 |
| `driver/` | Linux PCI C 驱动（不是 VFIO） |
| `tools/pcie_image_gui.py` | Python 图像界面 |
| `tools/bar0_gui.py` | 原 BAR0 测试界面 |
| `pcie_dme.RD` | DMA 方案、实现及验证状态 |
| `config/` | 原配置截图与参考资料 |

## FPGA 工程

在 Tang Dynasty 中打开上述 `.al` 文件，使用本目录下的 PCIe IP 配置：
Gen2 ×4，`tl_clk_user` 为 80 MHz；BAR0 为 32 KiB 32-bit 非预取
Memory BAR，但内部只有 1 KiB RAM，整个 BAR0 按低 10 位地址循环镜像。
BAR1 是 256 字节 I/O，BAR2/3 是 1 MiB 64-bit 非预取 Memory BAR
（DMA 控制），BAR4/5 是 1 MiB 64-bit 预取 Memory BAR（当前未实现业务）。
PF0 class code 为 `0x040000`，使用 Legacy INTA；驱动仍通过 PCI resource
index 2 访问 BAR2，并要求其为 64 位、1 MiB。
工程入口下的 `.ipc` 和 PCIe wrapper 已与 `config/` 截图及
`fpga/Design/case_ep/al_ip/` 中的生成文件同步。若修改 IP 配置，应重新生成
PCIe IP 及全部输出，并以实际枚举结果为准。
PLL 的 `tl_clk_user` 输出配置为 80 MHz，EP 顶层按 `EP_TL_CLK_REQ`
设置帧周期；80,000,000 个时钟周期对应 1 fps。实际 PCIe 链路按用户环境为
Gen2 ×4，链路速率与用户时钟频率是独立配置。

## 仿真

在仓库根目录执行（需要 Icarus Verilog）：

```sh
iverilog -g2012 -Wall -I fpga/Design/Rtl/common -s ep_bar0_32k_tb \
  -o /tmp/ep_bar0_32k_tb fpga/Design/Sim/tb/ep_bar0_32k_tb.v \
  fpga/Design/Rtl/ep_side/pcie_ep_engine.v fpga/Design/Rtl/common/eram.v
vvp /tmp/ep_bar0_32k_tb

iverilog -g2012 -Wall -I fpga/Design/Rtl/common -s pcie_ep_image_dma_tb \
  -o /tmp/pcie_ep_image_dma_tb fpga/Design/Sim/tb/pcie_ep_image_dma_tb.v \
  fpga/Design/Rtl/ep_side/pcie_ep_image_dma.v
vvp /tmp/pcie_ep_image_dma_tb

iverilog -g2012 -Wall -I fpga/Design/Rtl/common -s pcie_ep_bar2_tb \
  -o /tmp/pcie_ep_bar2_tb fpga/Design/Sim/tb/pcie_ep_bar2_tb.v \
  fpga/Design/Rtl/ep_side/pcie_ep_image_dma.v
vvp /tmp/pcie_ep_bar2_tb

# No vendor IP model: exercise the top-level user TX/RX logic with forced signals.
iverilog -g2012 -i -I fpga/Design/Rtl/common -s pcie_ep_shared_tx_tb \
  -o /tmp/pcie_ep_shared_tx_tb fpga/Design/Sim/tb/pcie_ep_shared_tx_tb.v \
  fpga/Design/Rtl/ep_side/ph2_pcie_ep_top.v \
  fpga/Design/Rtl/ep_side/pcie_ep_engine.v \
  fpga/Design/Rtl/ep_side/pcie_ep_image_dma.v \
  fpga/Design/Rtl/ep_side/pcie_ep_int_handle.v fpga/Design/Rtl/common/eram.v
vvp /tmp/pcie_ep_shared_tx_tb
```

完整 PCIe 链路仿真需要厂商 IP 模型，这些测试不替代链路仿真。

## Ubuntu 主机

驱动需要目标运行内核匹配的 headers 和构建工具；编译命令为
`make -C driver`。界面支持 Ubuntu 20.04 的 Python 3.8，需要 Tkinter 和
`tools/requirements.txt` 中的 Pillow。运行 `python3 tools/pcie_image_gui.py`
并确保有权限访问 `/dev/pcie_image*`；设备不能同时绑定其他 PCI 驱动。

BAR2 的 `ID_VERSION` 位于偏移 `0x0`，32 位读值为 `0x00010001`，
按地址递增的字节为 `01 00 01 00`。BAR2 地址由系统分配，不应假设固定为
`0xfe900000`。如果驱动加载失败，查看 `lspci -d 1edb:abcd -vv` 中
的 Region 2、Memory enable 状态和 `dmesg` 中的 `pcie_image` 报错；
驱动失败退出后设备可能已禁用，此时 `/dev/mem` 读全 `ff` 不能单独证明
RTL 出错。新 RTL 须重新综合、烧录后再进行测试。
BAR2 控制寄存器支持单 DWORD 内的字节、半字和 DWORD 访问；多 DWORD
读请求返回 Unsupported Request，多 DWORD 写请求不执行并设置错误状态。
驱动仅使用对齐的 DWORD 访问。接口对应手册 UG1112 1.2 第 2.2、2.3 节。

驱动加载时先禁用 bus mastering、发送 STOP 并确认硬件停止，再允许 DMA；
START 前读回两个槽的完整 DMA 地址。START 失败也必须执行 STOP，停止超时或
状态读回全 `ff` 时隔离缓冲区，禁止复用。此时需复位板卡后重新加载驱动。

**当前为实现初稿**：FPGA 尚未完成厂商综合/时序或上板联调；目标内核、
DMA 可见性、Legacy 中断和整帧正确性均待验证。
