# PH2A PCIe 图像 DMA 工程

本分支从 APUG038 EP 示例提取了图像 DMA 所需文件，保留原厂 EP 顶层、
公共 RTL、板级约束、PLL 和 PCIe IP 配置，并整合 32 KiB BAR0 覆盖实现。
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
BAR0 为 32 KiB，BAR2 用于 DMA 控制，PF0 使用 Legacy INTA。现有 IP
生成文件中部分辅助文件来自原厂示例，不保证与 32 KiB 覆盖配置一致；
**构建前应根据本分支 `.ipc` 重新生成 PCIe IP 及其所有输出文件**。
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
```

完整 PCIe 链路仿真需要厂商 IP 模型，这两个测试不替代链路仿真。

## Ubuntu 主机

驱动需要目标运行内核匹配的 headers 和构建工具；编译命令为
`make -C driver`。界面支持 Ubuntu 20.04 的 Python 3.8，需要 Tkinter 和
`tools/requirements.txt` 中的 Pillow。运行 `python3 tools/pcie_image_gui.py`
并确保有权限访问 `/dev/pcie_image*`；设备不能同时绑定其他 PCI 驱动。

**当前为实现初稿**：驱动尚未在目标 Ubuntu 内核编译，FPGA 尚未完成厂商
综合/时序或上板联调，DMA 可见性、Legacy 中断和整帧正确性均待验证。
