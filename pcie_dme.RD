# PH2A PCIe 1080p 图像 DMA 设计与实现记录

版本：V0.2（实现初稿，待硬件验证）
目标平台：现有 PH2A PCIe EP 和 Ubuntu Linux 主机（实际链路：PCIe Gen2 ×4）

## 1. 目标与范围

在当前已完成上板测试的分支基础上，FPGA 内部生成 1920×1080、1 帧/秒的测试图像；EP 通过 PCIe DMA 将完整图像写入主机内存，每帧完成后以中断通知驱动，Python 界面显示图像与运行信息。界面提供开始、停止和六种图案选择，图案选择经 PCIe 下发到 FPGA。

本文记录当前分支的 DMA 设计和实现初稿。RTL、Linux 驱动和 Python 界面已经加入工作区，但尚未在安路工具中综合、安装到目标主机或上板验证；通过定向仿真不代表端到端功能已完成。本次不设计物理串口输出；运行信息显示在 Python 界面日志区。

## 2. 当前基础与约束

- `README.md` 说明当前覆盖工程 BAR0 为 32 KiB，非预取 32 位 Memory BAR，设备 ID 为 `1edb:abcd`。现有 `tools/bar0_gui.py` 是 Ubuntu 下直接映射 BAR0 的读写界面，不提供 DMA 内存分配或中断等待。
- `config/Clipboard_Screenshot-3.png` 的 Interrupt 页面选中 **Legacy**、PF0 **INTA**，MSI 和 MSI-X 未选中；`fpga/Design/Rtl/common/ph2_pcie_case_param.v` 也启用 Legacy。故本方案使用 Legacy INTA，不要求切换 IP 中断模式。
- `config/PF.png` 显示 BAR0 为 32 KiB、BAR2 为 1 MiB 32-bit 非预取 Memory BAR，PF0 class code 为 `0x078000`；`config/Clipboard_Screenshot-5.png` 显示 Gen2 ×4、80 MHz。当前 `.ipc` 和生成的 PCIe wrapper 按这些配置同步；最终 BAR 资源仍以板卡实际枚举结果为准。
- 现有 EP engine 主要处理主机发起的 BAR 事务和响应；此方案需要新增 EP 主动发起 Memory Write 的 DMA 逻辑，不能把现有 BAR 读写当作 DMA。仓库原厂驱动压缩包包含 DMA/事件相关代码，但与本方案硬件寄存器协议是否兼容尚未确认，不假设可直接使用。
- PCIe IP 按 **Gen2 ×4** 配置，`tl_clk_user` 为 **80 MHz**。PCIe 链路速率与 FPGA 用户时钟频率是独立配置；代码使用 80,000,000 个用户时钟周期作为 1 秒帧节拍。DMA 仍读取 `tl_cfg_current_link_speed`、`tl_cfg_negotiated_width`、`tl_cfg_max_payload_size` 并以运行时值拆分 TLP。Gen2 ×4 对约 6.22 MB/s 的帧数据带宽充足，但仍须验证实际链路、TLP 流控和主机处理延迟。
- UG1112 1.2（2026.09）确认 EP 用户 TX 是 512-bit 接口，TLP Header Byte0 对应 `tl_tx_data[511:504]`，DW 内字节先高位后低位。`tl_tx_valid` 非末拍必须全 1、末拍标明有效 DW；`tl_tx_wait` 可在报文任意位置拉高，拉高期间所有发送输入须保持稳定。不得等 `tl_tx_wait==0` 后才开始新报文：`tl_tx_sop` 发起报文、`tl_tx_wait` 对传输施加反压。posted header/data credit 分别见 `tl_tx_credits[31:0]`；credit 更新有两个 `tl_clk_user` 周期延迟，应按手册信用规则和 IP 行为实现，不能只依赖 wait。
- UG1112 2.5.1 确认当前 Legacy INTA 配置使用 PF0：`tl_int_status[0]` 高有效表示 PF0 请求中断，`tl_int_pincontrol[0]` 高有效表示控制 INTA# 线路；`tl_int_pinstate[0]` 是观察 Root Port/Switch 线路状态的输出，不是 EP 中断完成确认。请求应保持到 Host 处理后清除，并在撤销前按截图/手册定义及平台观察验证。

## 3. 数据格式与六种图案

固定 RGB888，内存字节顺序为 R、G、B，逐行从左到右、自上而下，无帧头和行填充。每行 5760 字节，每帧 **6,220,800 字节（0x5EEC00）**，1 fps 图像净带宽约 **6.22 MB/s**。内存尾部为页对齐预留空间，不计入帧数据。

定义像素坐标 `x=0..1919`、`y=0..1079`，每种图案在一帧内固定：

| ID | 图案 | 确定性定义 |
|---|---|---|
| 0 | 竖直彩条 | 按 `x/240` 分成 8 条，依次为白、黄、青、绿、品红、红、蓝、黑；分量为 0 或 255。 |
| 1 | 横向灰阶 | `R=G=B=floor(x×255/1919)`，从左黑到右白。 |
| 2 | 棋盘格 | 以 120×120 像素为格，`(floor(x/120)+floor(y/120))` 偶数为白，奇数为黑。 |
| 3 | RGB 渐变 | `R=floor(x×255/1919)`，`G=floor(y×255/1079)`，`B=128`。 |
| 4 | 中心十字 | 背景黑；`956<=x<=963` 或 `536<=y<=543` 为白。 |
| 5 | 彩色方块 | 四个象限分别为红、绿、蓝、白；左右边界 x=960，上下边界 y=540。 |

上位机可选择缩放显示，但原始图像与校验均使用完整 1920×1080。界面初始选择 ID 0；运行中变更仅在下一帧开始时生效，一帧内不混用图案。每帧记录实际生效 ID。

## 4. 总体架构

```text
Python Tk 界面（开始/停止/图案选择、画面和日志）
          │ ioctl / poll / mmap，帧拷贝
Linux PCI 驱动（BAR2 控制、双 DMA 缓冲区、INTA 处理）
          │ PCIe：控制寄存器 / Memory Write / Legacy INTA
PH2A EP：BAR2 寄存器 + DMA 发送仲裁 + 图案发生器
          └─ 现有 BAR0 32 KiB 存储读写路径保留
```

选择 **EP 主动写主机内存**（C2H）：驱动通过 Linux DMA API 分配缓冲区，设备只使用 DMA API 返回的 DMA 地址（可能是 IOVA），不使用 Python 虚拟地址或 CPU 物理地址。单帧 DMA 地址空间连续，设备按地址递增发送 PCIe Memory Write；无需 FPGA 侧整帧缓存，只需带背压的像素生成器、打包和小 FIFO。主机按 Ubuntu/Linux 驱动路径设计；驱动、接口和 Python 界面均属于本设计实现范围，不依赖用户提供现成驱动。

方案优先复用原设计的 PCIe IP、链路与 BAR0 配置，将新控制寄存器放到 BAR2。现有 `pcie_ep_engine.v` 的 BAR0 事务路径需扩展 BAR2 命中解码和响应；不改变 BAR0 的 32 KiB 读写语义。禁止同时运行直接访问 BAR2 的其他程序或绑定多个驱动；现有 BAR0 GUI 的独立测试应在 DMA 停止后进行。

## 5. DMA 与帧缓冲

### 5.1 内存与所有权

驱动使用 `dma_set_mask_and_coherent()` 协商 64 位 DMA 地址能力；若设备、平台或 IOMMU 不支持，启动明确报错，不截断地址。分配两个 `dma_alloc_coherent()` 缓冲区，每个按 4 KiB 向上取整为 **6,221,824 字节（0x5EF000）**，实际发送长度固定为 6,220,800 字节，合计分配约 11.87 MiB。分配失败时提示并拒绝开始，不回退到不安全的内存映射。该方案较简单，但大块一致性内存可能在某些系统上分配失败；若实测不满足，再单独评审 SG/描述符方案，而不是默认可用。

驱动保存内核虚拟地址及 DMA 地址，并通过 `dma_mmap_coherent()` 只读映射给受控用户进程；分配、映射和释放均由驱动管理。最多一个采集客户端拥有设备。映射与 DMA 缓冲区生命周期绑定，进程退出、停止、解绑或异常时先停 DMA，再回收；映射仍存在时不得提前释放。

每个缓冲区的所有权状态：`FREE → DEVICE → READY → USER → FREE`。驱动在开始时提供两个地址并将空闲槽授权给 EP；EP 每次仅写已授权槽。完成后 FPGA 锁存槽号、帧号、图案、长度并置完成状态，驱动检查后将其交给用户；Python 将完整帧复制到自身显示内存后立即归还槽，不能持有 DMA 缓冲区继续显示。驱动/硬件均不得覆盖 READY 或 USER 槽。

可通过两个槽各自的完成状态及序号追踪多个尚未处理的帧，不能仅依靠一位中断标志计数。若无空闲槽，跳过该采集节拍，增加丢帧计数，不覆盖未消费帧，也不为未生成的帧发完成中断；恢复后在下个节拍继续。

### 5.2 发送与节拍

- START 生效后立即开始第一帧，此后以 80 MHz `tl_clk_user` 每 80,000,000 周期产生 1 秒采集节拍；当前帧尚未结束或无空槽时计一次丢帧并跳过该节拍，不补发。若修改用户时钟，EP 顶层的帧周期随 `EP_TL_CLK_REQ` 更新。
- 帧开始时锁存图案 ID 和帧序号，生成顺序像素并打包为字节流。发送逻辑按有效握手推进，`tl_tx_wait` 时保持相关输出稳定，FIFO 满时反压发生器。
- DMA 写地址和长度要合法、4 字节对齐、处于已授权帧缓冲范围内。每个 TLP 的 payload 不超过实时协商 MPS，且不跨越 4 KiB 边界；首尾字节使能、3DW/4DW 地址格式、字节顺序和 TX 接口位序按 UG1112 2.2.1–2.2.3 实现。使用 4DW Memory Write 支持 DMA API 返回的 64 位地址。遇到任意地址或长度异常时停止并报告，不得越界发送。
- 当前 RTL 每个 Memory Write payload 最多 64 字节（低于 PCIe 最小 MPS），并在 4 KiB 边界处分包；不是按运行时 MPS 动态产生更大 payload。TX 仲裁器在 DMA Memory Write 和原有 BAR Read Completion 等业务间仲裁，TLP 不可中途切换，并在未获仲裁期间向非所有者施加 wait。仅在 UG1112 定义的有效传输周期推进 TLP 状态。`tl_tx_credits` 用于 posted/non-posted 发送节流，并对 posted credit 更新留两周期保护；最终需用厂商 IP 仿真模型及上板确认 credit 位域和实际传输行为。`tl_tx_stream` 维持关闭。
- 配置空间 Bus Master Enable、链路和设备就绪均满足后才允许发送。帧全部写请求被 IP 接收不等于已被 CPU 观察到；可见性按第 6 节处理。

### 5.3 控制寄存器草案

以下偏移均为 BAR2 字节偏移，32 位对齐、32 位访问、小端；实现时以版本号约束 ABI，未列出的地址保留。BAR2 原有用途和系统分配需在实施前确认。64 位地址分低、高 32 位，**只允许空闲/停止状态写入**，完整写入并读回后才授权设备。

| 偏移 | 名称 | 用途 |
|---|---|---|
| 0x000 | ID_VERSION | 只读签名与协议版本；驱动不匹配即拒绝运行。 |
| 0x004 | CONTROL | 写命令：START、STOP、槽 0/1 授权；命令互斥及非法操作置错误。 |
| 0x008 | STATUS | 只读：运行、停止完成、链路/总线主控可用、设备忙、错误。 |
| 0x00C | PATTERN | 待生效图案 ID 0～5；非法值报错、不改变当前设置。 |
| 0x010 | IRQ_STATUS | 槽 0/1 完成及错误的粘滞 pending 位；W1C 清除。新事件与清除同周期时新事件优先。 |
| 0x014 | IRQ_ENABLE | 对应 pending 位的中断使能。 |
| 0x018 | ERROR | 粘滞错误码，例如非法配置、链路中断；停止后 W1C 清除。 |
| 0x01C | DROP_COUNT | 跳过的节拍数，32 位饱和计数；开始新会话清零。 |
| 0x020/0x024 | BUF0_ADDR_LO/HI | 槽 0 DMA 地址。 |
| 0x028/0x02C | BUF1_ADDR_LO/HI | 槽 1 DMA 地址。 |
| 0x030/0x034/0x038 | BUF0_SEQ/PATTERN/LENGTH | 槽 0 已完成帧的序号、图案 ID、有效字节数。 |
| 0x040/0x044/0x048 | BUF1_SEQ/PATTERN/LENGTH | 槽 1 对应信息。 |

开始新会话时序号从 0 开始递增（32 位回绕），槽元数据在该槽被再次授权前保持稳定。驱动在申请开始前分配内存、清理旧状态、配置地址和图案、授权槽、开启中断，再写 START；对 MMIO posted write 使用读回保证寄存器编程顺序。

## 6. Legacy INTA 与内存可见性

保留 IP 的 Legacy INTA 设置。改造原演示用 `pcie_ep_int_handle.v`：原逻辑由外部触发边沿产生演示脉冲，不能直接当作可靠帧完成协议。新逻辑依据 `(IRQ_STATUS & IRQ_ENABLE) != 0` 管理 PF0 INTA：有未处理事件时置 `tl_int_status[0]` 并驱动 `tl_int_pincontrol[0]` 请求 INTA；没有 pending 时撤销请求。`tl_int_pinstate[0]` 仅作线路状态观测，不作为 EP 的 ack。Legacy INTA 可能共享或合并多项 pending，故 Host IRQ handler 必须读取硬件槽状态并循环处理，不将一次 IRQ 等同于仅一帧。错误事件也通过该中断报告。

驱动使用 Linux PCI IRQ 分配接口限定 Legacy、注册共享 IRQ 处理器（`IRQF_SHARED`）。处理器先读 BAR2 pending：无本设备 pending 则返回 `IRQ_NONE`；有 pending 则读取所有已完成槽的元数据、检查槽和长度、W1C 已处理位、读回状态并唤醒 `poll()` 等待的用户。若处理期间出现新 pending，Legacy INTA 保持/重新触发并由后续 handler 处理。两个槽同时完成不能丢事件，重复中断和共享中断均可处理。

帧数据的所有 Memory Write 必须先于该帧完成状态发布，且与 Legacy 中断满足 PCIe 顺序要求：相同 Requester ID、TC，禁用 Relaxed Ordering 等会破坏顺序的属性。Legacy 中断有可能越过未完成的 posted writes，因此驱动在接到中断后先执行该设备的非 posted BAR 状态读取及其完成，再按 Linux DMA API 内存屏障要求读取/发布帧数据；一致性内存不需要把 DMA 地址当 CPU 地址，也不应对其误用 streaming DMA 同步接口。该读回作为顺序屏障的有效性，以及 IP 发出 Assert 和最后写包之间的顺序，必须结合 PH2A IP、平台及 PCIe 规则在仿真和上板验证；无法证明时不能宣布帧完成可靠。

## 7. 驱动与 Python 界面

计划新增专用 Linux PCI 驱动，绑定 `1edb:abcd`，检查 BAR2 长度、ID_VERSION 和 Legacy IRQ，启用设备及 bus mastering，使用 char device 提供：

- `ioctl`：获取能力/状态、设置图案、开始、停止、获取下一已完成帧的槽/序号/图案/长度、归还槽。驱动只接受拥有该设备的客户端发起的控制；用户不能自行下发 DMA 地址。
- `poll()`：等待完成帧或错误事件；等待可被停止、关闭或设备移除唤醒。事件来自真正硬件中断，不用定时轮询伪造完成。
- `mmap()`：按槽号选择只读映射；每个槽映射长度为对齐分配长度，应用只读取有效帧长度。UI 消费后先复制再归还。

若当前主机已经绑定原厂驱动，需先正常停止并解绑，才能绑定新驱动；不能两个驱动同时拥有设备。驱动、应用错误均显示明确原因，例如 BAR 不匹配、DMA 分配失败、IRQ 不可用、链路异常。

Python 使用 Tkinter 窗口，建议 Pillow 处理 RGB888 和缩放；主线程负责控件与画面，工作线程等待驱动事件并复制帧，通过线程安全队列和 `after()` 更新界面。界面包含设备状态、开始/停止按钮、六项图案下拉框及应用按钮、图像显示区、可滚动日志区；日志示例：`frame=42 pattern=棋盘格 bytes=6220800 dropped=0`，并显示错误、实际帧率、所选/当前生效图案。窗口关闭时先停止线程与设备并释放资源。界面日志不是物理串口，也不依赖 UART。

## 8. 停止、错误与恢复

- STOP 不开启新帧；若有在途帧，正常情况下允许其写完并报告完成，然后停止。驱动等待停止完成及设备发送路径排空，再屏蔽中断、清理 pending，并唤醒用户；不能在 DMA 仍可能写入时释放缓冲区。等待设明确超时并显示错误。
- 超时、链路断开、驱动解绑或进程异常时，禁止继续提交 DMA 并撤销 bus mastering，使用平台支持的 PCIe 复位/设备隔离及事务排空机制确认设备已无法继续访问后，才解除 DMA 映射和释放内存；无法保证安全时保留相关资源并报告致命错误，不能假装成功。具体复位手段须根据 PH2A IP 与主机能力验证，本 IP 配置未启用 FLR。
- 中断丢失或超时只报告故障，不把部分帧当完整帧显示。无空槽属于可恢复丢帧；发生器、DMA 地址、长度或链路错误进入错误状态，必须停止并重新初始化。
- 启停、图案切换和缓冲归还由驱动串行化；禁止在 DEVICE/READY/USER 状态改变槽地址或重复授权。帧完成和 STOP 并发时保留已完成元数据，用户只显示完整帧。

## 9. 验证与验收计划

1. **RTL 单元仿真**：六种图案的边界像素与字节顺序、完整帧长度、帧间图案切换；分别注入 `tl_tx_wait`、credit 不足、FIFO 背压，检查无漏字节、重复或越界。
2. **PCIe 事务仿真**：验证 64 位地址、不同 MPS、4 KiB 边界及尾包、TX 仲裁、BAR0 原有读写和 BAR2 寄存器；通过总线模型重建每帧并与软件参考图逐字节比较。
3. **中断仿真**：帧完成后 Assert、W1C 后 Deassert、双槽 pending、处理时新事件、共享中断及错误路径；验证最后数据写、完成状态和中断的顺序。
4. **驱动测试**：DMA 分配失败、IOMMU 开关和高于 4 GiB 的 DMA 地址、IRQ 不可用、错误长度、无空槽、进程退出、反复启停、设备移除/超时与资源生命周期；共享 IRQ 非本设备返回 `IRQ_NONE`。
5. **上板验收**：首先复测原 BAR0 32 KiB 读写；确认 `lspci` 的 BAR、实际链路、Legacy INTA 和 bus master 状态。六图案各连续采集至少 10 帧，按完整 RGB 字节与参考图比较；无丢帧条件下连续运行 10 分钟，检查至少 600 个完成中断与对应完整帧，帧间周期以设备时钟为基准 1.000 秒，目标误差不超过 1%，并记录 Host 接收抖动、丢帧和错误。人为延迟消费验证丢帧策略和无撕裂，运行中切换图案、停止/重启及异常处理均须符合上述协议。

性能与可靠性以实测为准；无空槽或系统中断被屏蔽时不承诺每秒都能显示一帧。板上图像、IRQ、DMA 安全及时序收敛均需实际验证，不应因目前 BAR0 上板成功而视为已完成。

## 10. 已知实施基线与验证边界

- PCIe IP 按 Gen2 ×4 配置，Linux 驱动和 Python UI 由本项目新增；工具以仓库已有 Ubuntu GUI 为平台线索。驱动构建需匹配实际运行内核的 headers，实施时通过标准内核接口处理版本差异。
- 当前配置为 BAR0 32 KiB 32-bit Memory、BAR2 1 MiB 32-bit 非预取 Memory，BAR2 仍通过 PCI resource index 2 访问；BAR2 的 32-bit 属性不要求驱动改用其他 BAR index。PF0 class code 为 `0x078000`，不影响驱动按 `1edb:abcd` 匹配。真实运行 BAR、class code 和训练链路仍须由主机枚举确认，并检查其与 bitstream 一致性。
- Host DMA 分配、驱动安装和 UI 是本方案必做工作，不作为要求用户另行提供的功能。硬件 IP 行为通过 UG1112、已有 RTL、可用仿真/测试和板上数据逐步验证；若器件配置或工具模型缺失，则明确标注受限项，不把它们作为已验证事实。
- 本版固定 RGB888、六种图案、双缓冲；若连续一致性 DMA 缓冲无法分配，当前版本报告错误，不静默降级到 SG。是否另行设计 SG 为后续优化事项，不影响本版协议正确性。

当前分支已包含 RTL、驱动、Python 界面及定向仿真初稿。具体硬件时序、BAR 地址、IP 端口时序和链路结果仍以安路工具构建及上板实测为准；未通过这些检查前不得用于宣称 DMA 已实现完成。

## 11. 当前实现与验证状态

- 新增 `fpga/Design/Rtl/ep_side/pcie_ep_image_dma.v`：BAR2 寄存器接口、6 种 RGB888 图案、64 字节最大 payload 的 4DW Memory Write、4 KiB 边界拆分、双槽帧状态和错误/完成中断。START 后立即产生首帧，后续按 `FRAME_PERIOD_CYCLES` 计时；当前默认 80,000,000 个 `tl_clk_user` 周期，对应 80 MHz 下 1 fps。图像生成使用递增的 x/y/分量计数器，不再从每个 DWORD 的字节偏移执行宽位除法/取模。
- EP 顶层通过 TX 仲裁器连接原 BAR engine 与新 DMA engine，并在非仲裁所有者一侧施加 wait；Legacy PF0 INTA pending 由 DMA 中断状态和使能共同驱动，同时保留原 demo 外部触发脉冲。
- 新增 `driver/pcie_image_drv.c` / `pcie_image.h`：绑定 `1edb:abcd`、检查 BAR2 ABI、分配两个 coherent DMA buffer、提供 `mmap/poll/ioctl` 和 Legacy IRQ。停止超时时清除 bus mastering 并隔离 buffer，避免释放仍可能被设备访问的内存；该保护不等于验证了设备已被物理隔离。
- 新增 `tools/pcie_image_gui.py`：Tkinter 开始/停止、图案选择、画面显示和日志；须按 `tools/requirements.txt` 安装 Pillow。日志显示帧序号、图案、长度、协商链路及丢帧计数，不输出至物理串口。
- 已通过 `fpga/Design/Sim/tb/pcie_ep_image_dma_tb.v` 定向 RTL 仿真，覆盖 BAR2 读写、Memory Write 头/数据、4 KiB 拆包、TX wait 保持、帧元数据/W1C 中断、图案参考像素、双缓冲槽地址轮转，以及 STOP 等待在途帧完成。已通过现有 BAR0 回归、EP 顶层/包装器语法检查和 Python 语法/ioctl ABI 大小检查。
- 当前未验证：完整端到端 PCIe 仿真、安路综合/时序、Linux 内核模块编译、实际 GUI 与板卡联调、上板 1080p 图像逐字节比对、DMA/INTA 顺序和长时间稳定性。缺少目标内核 headers 与厂商综合/IP 仿真环境时，须将其作为明确的验证阻塞项；不得据此宣称功能已完成。
