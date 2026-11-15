#!/usr/bin/env python3
"""Display 1080p frames received by the PH2A PCIe image DMA driver."""

import ctypes
import errno
import fcntl
import glob
import mmap
import os
import queue
import select
import struct
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

from PIL import Image, ImageTk

WIDTH = 1920
HEIGHT = 1080
FRAME_BYTES = WIDTH * HEIGHT * 3
SLOT_BYTES = 6_221_824
SLOT_COUNT = 2
PATTERNS = (
    "竖直彩条",
    "横向灰阶",
    "棋盘格",
    "RGB 渐变",
    "中心十字",
    "彩色方块",
)


class ImageInfo(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_uint32),
        ("height", ctypes.c_uint32),
        ("frame_bytes", ctypes.c_uint32),
        ("slot_bytes", ctypes.c_uint32),
        ("slot_count", ctypes.c_uint32),
        ("pattern_count", ctypes.c_uint32),
        ("pixel_format", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
    ]


class ImageFrame(ctypes.Structure):
    _fields_ = [
        ("slot", ctypes.c_uint32),
        ("sequence", ctypes.c_uint32),
        ("pattern", ctypes.c_uint32),
        ("length", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
    ]


class ImageStatus(ctypes.Structure):
    _fields_ = [
        ("running", ctypes.c_uint32),
        ("error", ctypes.c_uint32),
        ("dropped_frames", ctypes.c_uint32),
        ("link_speed", ctypes.c_uint32),
        ("link_width", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
    ]


def _ioc(direction: int, number: int, size: int = 0) -> int:
    return (direction << 30) | (size << 16) | (ord("P") << 8) | number


IOC_GET_INFO = _ioc(2, 1, ctypes.sizeof(ImageInfo))
IOC_START = _ioc(1, 2, ctypes.sizeof(ctypes.c_uint32))
IOC_STOP = _ioc(0, 3)
IOC_SET_PATTERN = _ioc(1, 4, ctypes.sizeof(ctypes.c_uint32))
IOC_DEQUEUE = _ioc(2, 5, ctypes.sizeof(ImageFrame))
IOC_RELEASE_SLOT = _ioc(1, 6, ctypes.sizeof(ctypes.c_uint32))
IOC_GET_STATUS = _ioc(2, 7, ctypes.sizeof(ImageStatus))


def ioctl_value(fd: int, command: int, value: int = 0) -> None:
    fcntl.ioctl(fd, command, struct.pack("=I", value))


def ioctl_struct(fd: int, command: int, result: ctypes.Structure) -> ctypes.Structure:
    buffer = bytearray(ctypes.string_at(ctypes.addressof(result), ctypes.sizeof(result)))
    fcntl.ioctl(fd, command, buffer, True)
    ctypes.memmove(ctypes.addressof(result), bytes(buffer), ctypes.sizeof(result))
    return result


def find_devices() -> list[str]:
    return sorted(glob.glob("/dev/pcie_image[0-9]*"))


class ImageGui:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("PH2A PCIe 1080p DMA")
        self.root.minsize(900, 650)
        self.fd: int | None = None
        self.maps: list[mmap.mmap] = []
        self.worker: threading.Thread | None = None
        self.stop_event = threading.Event()
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.running = False
        self.device = tk.StringVar()
        self.pattern = tk.StringVar(value=PATTERNS[0])
        self.status = tk.StringVar(value="请选择 PCIe 图像设备")
        self.frame_image: ImageTk.PhotoImage | None = None

        controls = ttk.Frame(root, padding=10)
        controls.pack(fill=tk.X)
        ttk.Label(controls, text="设备").pack(side=tk.LEFT)
        self.device_box = ttk.Combobox(
            controls, textvariable=self.device, state="readonly", width=26
        )
        self.device_box.pack(side=tk.LEFT, padx=(6, 12))
        ttk.Button(controls, text="刷新设备", command=self.refresh_devices).pack(
            side=tk.LEFT
        )
        ttk.Label(controls, text="图案").pack(side=tk.LEFT, padx=(18, 4))
        self.pattern_box = ttk.Combobox(
            controls, textvariable=self.pattern, values=PATTERNS, state="readonly", width=14
        )
        self.pattern_box.pack(side=tk.LEFT)
        ttk.Button(controls, text="应用图案", command=self.set_pattern).pack(
            side=tk.LEFT, padx=6
        )
        self.start_button = ttk.Button(controls, text="开始", command=self.start)
        self.start_button.pack(side=tk.LEFT, padx=(12, 4))
        self.stop_button = ttk.Button(
            controls, text="停止", command=self.stop, state=tk.DISABLED
        )
        self.stop_button.pack(side=tk.LEFT)

        self.canvas = ttk.Label(root, anchor=tk.CENTER, text="等待图像帧")
        self.canvas.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 8))
        ttk.Label(root, textvariable=self.status, anchor=tk.W).pack(
            fill=tk.X, padx=10, pady=(0, 6)
        )
        self.log = tk.Text(root, height=8, state=tk.DISABLED, wrap=tk.WORD)
        self.log.pack(fill=tk.X, padx=10, pady=(0, 10))

        self.refresh_devices()
        self.root.after(50, self.process_events)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def refresh_devices(self) -> None:
        devices = find_devices()
        self.device_box["values"] = devices
        if self.device.get() not in devices:
            self.device.set(devices[0] if devices else "")
        self.status.set(
            f"发现 {len(devices)} 个设备" if devices else "未发现 /dev/pcie_image*；请检查驱动"
        )

    def connect(self) -> None:
        path = self.device.get()
        if not path:
            raise RuntimeError("请先选择 PCIe 图像设备")
        self.fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
        info = ioctl_struct(self.fd, IOC_GET_INFO, ImageInfo())
        if (
            info.width != WIDTH
            or info.height != HEIGHT
            or info.frame_bytes != FRAME_BYTES
            or info.slot_bytes != SLOT_BYTES
            or info.slot_count != SLOT_COUNT
        ):
            raise RuntimeError("驱动返回的图像能力与 GUI ABI 不匹配")
        for slot in range(SLOT_COUNT):
            self.maps.append(
                mmap.mmap(
                    self.fd,
                    SLOT_BYTES,
                    flags=mmap.MAP_SHARED,
                    prot=mmap.PROT_READ,
                    offset=slot * SLOT_BYTES,
                )
            )

    def start(self) -> None:
        if self.running:
            return
        try:
            self.connect()
            ioctl_value(self.fd, IOC_START, PATTERNS.index(self.pattern.get()))
        except (OSError, RuntimeError, ValueError) as error:
            self.disconnect()
            self.show_error(error)
            return
        self.running = True
        self.stop_event.clear()
        self.worker = threading.Thread(target=self.receive_frames, daemon=True)
        self.worker.start()
        self.start_button.configure(state=tk.DISABLED)
        self.stop_button.configure(state=tk.NORMAL)
        self.status.set("采集运行中：等待 DMA 图像")
        self.append_log("开始图像 DMA")

    def set_pattern(self) -> None:
        if not self.running or self.fd is None:
            self.status.set(f"待应用图案：{self.pattern.get()}（开始时生效）")
            return
        try:
            ioctl_value(self.fd, IOC_SET_PATTERN, PATTERNS.index(self.pattern.get()))
            self.status.set(f"图案将在下一帧生效：{self.pattern.get()}")
        except (OSError, ValueError) as error:
            self.show_error(error)

    def stop(self) -> bool:
        if not self.running:
            return True
        self.stop_event.set()
        try:
            if self.fd is not None:
                fcntl.ioctl(self.fd, IOC_STOP)
        except OSError as error:
            self.show_error(error)
            if error.errno in (errno.EIO, errno.ENODEV):
                if self.worker and self.worker is not threading.current_thread():
                    self.worker.join(timeout=2)
                    if self.worker.is_alive():
                        self.status.set("采集异常结束：接收线程未退出，DMA 映射仍保留")
                        return False
                self.running = False
                self.disconnect()
                self.start_button.configure(state=tk.NORMAL)
                self.stop_button.configure(state=tk.DISABLED)
                self.status.set(f"采集异常结束：{error}")
                self.append_log(f"采集异常结束，驱动已隔离 DMA 缓冲区：{error}")
                return True
            return False
        if self.worker and self.worker is not threading.current_thread():
            self.worker.join(timeout=2)
            if self.worker.is_alive():
                self.status.set("停止超时：接收线程仍在运行，未释放 DMA 映射")
                return False
        self.running = False
        self.disconnect()
        self.start_button.configure(state=tk.NORMAL)
        self.stop_button.configure(state=tk.DISABLED)
        self.status.set("采集已停止")
        self.append_log("停止图像 DMA")
        return True

    def receive_frames(self) -> None:
        assert self.fd is not None
        poller = select.poll()
        poller.register(self.fd, select.POLLIN | select.POLLERR | select.POLLHUP)
        while not self.stop_event.is_set():
            events = poller.poll(200)
            if not events:
                continue
            if events[0][1] & (select.POLLERR | select.POLLHUP):
                self.events.put(("removed", "PCIe 图像设备已移除"))
                return
            try:
                frame = ioctl_struct(self.fd, IOC_DEQUEUE, ImageFrame())
                if (
                    frame.length != FRAME_BYTES
                    or frame.slot >= SLOT_COUNT
                    or frame.pattern >= len(PATTERNS)
                ):
                    self.events.put(("error", "驱动返回无效帧描述"))
                    return
                raw = self.maps[frame.slot][:FRAME_BYTES]
                image = Image.frombytes("RGB", (WIDTH, HEIGHT), raw)
                status = ioctl_struct(self.fd, IOC_GET_STATUS, ImageStatus())
                self.events.put(("frame", (image, frame, status)))
            except OSError as error:
                if error.errno == errno.EAGAIN:
                    continue
                if error.errno == errno.ENODEV:
                    self.events.put(("removed", "PCIe 图像设备已移除"))
                    return
                self.events.put(("error", f"驱动读取帧失败：{error}"))
                return
            else:
                try:
                    ioctl_value(self.fd, IOC_RELEASE_SLOT, frame.slot)
                except OSError as error:
                    self.events.put(("error", f"归还 DMA 缓冲区失败：{error}"))
                    return

    def process_events(self) -> None:
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "frame":
                    image, frame, status = payload
                    image.thumbnail((1100, 620), Image.Resampling.BILINEAR)
                    self.frame_image = ImageTk.PhotoImage(image)
                    self.canvas.configure(image=self.frame_image, text="")
                    pattern = PATTERNS[frame.pattern]
                    self.status.set(
                        f"frame={frame.sequence} pattern={pattern} "
                        f"link=Gen{status.link_speed} x{status.link_width} "
                        f"dropped={status.dropped_frames}"
                    )
                    self.append_log(
                        f"frame={frame.sequence} pattern={pattern} "
                        f"bytes={frame.length} dropped={status.dropped_frames}"
                    )
                elif kind == "removed":
                    self.stop_event.set()
                    if self.worker and self.worker is not threading.current_thread():
                        self.worker.join(timeout=2)
                    self.disconnect()
                    self.running = False
                    self.start_button.configure(state=tk.NORMAL)
                    self.stop_button.configure(state=tk.DISABLED)
                    self.status.set(str(payload))
                    self.append_log(str(payload))
                else:
                    self.status.set(str(payload))
                    self.append_log(f"错误：{payload}")
                    if self.running:
                        self.stop()
        except queue.Empty:
            pass
        self.root.after(50, self.process_events)

    def append_log(self, message: str) -> None:
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, f"{time.strftime('%H:%M:%S')} {message}\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)

    def disconnect(self) -> None:
        for mapping in self.maps:
            mapping.close()
        self.maps.clear()
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def show_error(self, error: Exception) -> None:
        self.status.set(f"操作失败：{error}")
        messagebox.showerror("PCIe 图像 DMA", str(error), parent=self.root)

    def close(self) -> None:
        if not self.stop():
            messagebox.showerror(
                "停止失败",
                "接收线程仍在运行；为避免释放仍在使用的 DMA 缓冲区，窗口保持打开。",
                parent=self.root,
            )
            return
        self.disconnect()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    ImageGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
