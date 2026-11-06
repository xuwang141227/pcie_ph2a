#!/usr/bin/env python3
"""Tk GUI for byte-range access to the demo EP's BAR0."""

import mmap
import os
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

VENDOR_ID = "0x1edb"
DEVICE_ID = "0xabcd"
BAR0_SIZE = 32 * 1024
PCI_DEVICES = Path("/sys/bus/pci/devices")


def parse_integer(value: str) -> int:
    return int(value.strip(), 0)


class Bar0Gui:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("PCIe EP BAR0 ERAM")
        self.root.minsize(620, 420)
        self.devices: dict[str, Path] = {}
        self.device_choice = tk.StringVar()
        self.address = tk.StringVar(value="0x0")
        self.length = tk.StringVar(value="16")
        self.status = tk.StringVar(value="正在扫描 PCIe EP...")

        frame = ttk.Frame(root, padding=12)
        frame.pack(fill=tk.BOTH, expand=True)
        frame.columnconfigure(1, weight=1)
        frame.rowconfigure(4, weight=1)

        ttk.Label(frame, text="PCIe EP").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        self.device_box = ttk.Combobox(
            frame, textvariable=self.device_choice, state="readonly"
        )
        self.device_box.grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(frame, text="刷新设备", command=self.refresh_devices).grid(
            row=0, column=2, padx=(8, 0), pady=4
        )

        ttk.Label(frame, text="BAR0 偏移").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(frame, textvariable=self.address).grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Label(frame, text="长度（字节）").grid(row=2, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(frame, textvariable=self.length).grid(row=2, column=1, sticky="ew", pady=4)

        ttk.Label(frame, text="写入数据（十六进制字节，空格可选）").grid(
            row=3, column=0, columnspan=3, sticky="w", pady=(8, 2)
        )
        self.data = tk.Text(frame, height=5, wrap=tk.WORD)
        self.data.grid(row=4, column=0, columnspan=3, sticky="nsew")
        self.data.insert("1.0", "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f")

        buttons = ttk.Frame(frame)
        buttons.grid(row=5, column=0, columnspan=3, sticky="ew", pady=8)
        ttk.Button(buttons, text="读取", command=self.read_bar).pack(side=tk.LEFT)
        ttk.Button(buttons, text="写入", command=self.write_bar).pack(side=tk.LEFT, padx=8)
        ttk.Label(frame, textvariable=self.status, wraplength=580).grid(
            row=6, column=0, columnspan=3, sticky="w"
        )
        self.refresh_devices()

    def refresh_devices(self) -> None:
        self.devices.clear()
        options = []
        if PCI_DEVICES.exists():
            for path in sorted(PCI_DEVICES.iterdir()):
                try:
                    vendor = (path / "vendor").read_text().strip().lower()
                    device = (path / "device").read_text().strip().lower()
                    if vendor != VENDOR_ID or device != DEVICE_ID:
                        continue
                    resources = (path / "resource").read_text().splitlines()
                    start, end, flags = (int(value, 16) for value in resources[0].split())
                    size = end - start + 1 if end >= start else 0
                    if not (flags & 0x200) or size < BAR0_SIZE:
                        continue
                    label = f"{path.name} ({vendor[2:]}:{device[2:]})"
                    self.devices[label] = path
                    options.append(label)
                except (OSError, ValueError, IndexError):
                    continue

        self.device_box["values"] = options
        if options:
            if self.device_choice.get() not in self.devices:
                self.device_choice.set(options[0])
            self.status.set(f"已识别 {len(options)} 个设备；BAR0 至少 {BAR0_SIZE} 字节。")
        else:
            self.device_choice.set("")
            self.status.set(
                f"未找到 {VENDOR_ID}:{DEVICE_ID} 且 BAR0 不小于 32 KiB 的设备。"
            )

    def get_range(self) -> tuple[Path, int, int]:
        label = self.device_choice.get()
        if label not in self.devices:
            raise ValueError("请先选择已识别的 PCIe EP。")
        offset = parse_integer(self.address.get())
        length = parse_integer(self.length.get())
        if offset < 0 or length <= 0 or offset + length > BAR0_SIZE:
            raise ValueError(f"访问范围必须在 BAR0 的 0x0–0x{BAR0_SIZE:x} 内。")
        return self.devices[label], offset, length

    @staticmethod
    def map_bar(device: Path) -> tuple[int, mmap.mmap]:
        fd = os.open(device / "resource0", os.O_RDWR)
        try:
            mapping = mmap.mmap(
                fd,
                BAR0_SIZE,
                flags=mmap.MAP_SHARED,
                prot=mmap.PROT_READ | mmap.PROT_WRITE,
            )
        except Exception:
            os.close(fd)
            raise
        return fd, mapping

    def read_bar(self) -> None:
        try:
            device, offset, length = self.get_range()
            fd, mapping = self.map_bar(device)
            try:
                result = mapping[offset : offset + length]
            finally:
                mapping.close()
                os.close(fd)
            lines = []
            for index in range(0, length, 16):
                chunk = result[index : index + 16]
                lines.append(" ".join(f"{byte:02x}" for byte in chunk))
            self.data.delete("1.0", tk.END)
            self.data.insert("1.0", "\n".join(lines))
            self.status.set(f"读取完成：{length} 字节，BAR0+0x{offset:x}。")
        except (OSError, ValueError, OverflowError) as error:
            self.show_error(error)

    def write_bar(self) -> None:
        try:
            device, offset, length = self.get_range()
            payload = bytes.fromhex(self.data.get("1.0", tk.END))
            if len(payload) != length:
                raise ValueError(f"写入数据为 {len(payload)} 字节，长度栏为 {length} 字节。")
            fd, mapping = self.map_bar(device)
            try:
                mapping[offset : offset + length] = payload
            finally:
                mapping.close()
                os.close(fd)
            self.status.set(f"写入完成：{length} 字节，BAR0+0x{offset:x}。")
        except (OSError, ValueError, OverflowError) as error:
            self.show_error(error)

    def show_error(self, error: Exception) -> None:
        self.status.set(f"访问失败：{error}")
        messagebox.showerror("BAR0 访问失败", str(error), parent=self.root)


def main() -> None:
    root = tk.Tk()
    Bar0Gui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
