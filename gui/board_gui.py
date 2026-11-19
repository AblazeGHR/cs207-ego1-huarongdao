#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EGO1 数字华容道 PC 监视 GUI。

读取板载 CP2102 的串口（9600 8N1），解析 FPGA 发来的：
  3x3 ASCII 棋盘 + 状态行
  V00 I01 W0 M1 S0 D0 L00A5
并实时显示棋盘、步数、模式、提示、16 个 LED 和最近操作（含撤销）。
"""

import argparse
import queue
import re
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

import serial
from serial.tools import list_ports

BAUD = 9600

BG = "#f4efe4"
PANEL = "#fffdf8"
HEADER = "#264653"
TILE = "#e9b872"
TILE_FG = "#2f2418"
EMPTY = "#fbf7ef"
EMPTY_FG = "#9a917f"
MUTED = "#d8d1c2"
MUTED_FG = "#8b8272"
ACCENT = "#2a9d8f"
DANGER = "#c8553d"
GOOD = "#2a9d8f"
WARN = "#d9822b"
GRID = "#d4ccbd"

STATUS_RE = re.compile(
    r"^V(\d{2})\s+I(\d{2})\s+W(\d)\s+M(\d)\s+S(\d)\s+D(\d)\s+L([0-9A-Fa-f]{4})$"
)


class BoardParser:
    """把串口行组装成 (board_rows, status_dict)。"""

    def __init__(self):
        self.rows = []
        self.status = None

    def feed(self, line: str):
        line = line.strip()

        if not line:
            if len(self.rows) == 3:
                result = ([row[:] for row in self.rows], self.status)
                self.rows = []
                self.status = None
                return result
            self.rows = []
            self.status = None
            return None

        m = STATUS_RE.match(line)
        if m:
            v, i, w, mode, page, demo, led = m.groups()
            self.status = {
                "v": int(v),
                "i": int(i),
                "w": int(w),
                "m": int(mode),
                "s": int(page),
                "d": int(demo),
                "led": int(led, 16),
            }
            return None

        parts = line.split()
        if len(parts) == 3 and all(p in "-0123456789" for p in parts):
            self.rows.append(parts)
            if len(self.rows) > 3:
                self.rows = self.rows[-3:]
        else:
            self.rows = []
            self.status = None
        return None


class BoardGUI:
    def __init__(self, root: tk.Tk, port=None, autoconnect=True, demo=False):
        self.root = root
        self.port = port
        self.autoconnect = autoconnect
        self.demo = demo

        self.ser = None
        self.reader = None
        self.stop_event = threading.Event()
        self.queue = queue.Queue()
        self.parser = BoardParser()
        self.frames = 0
        self.tiles = []
        self.led_labels = []
        self.prev_status = None

        self.port_var = tk.StringVar()
        self.status_var = tk.StringVar(value="未连接")
        self.last_var = tk.StringVar(value="等待数据")
        self.valid_var = tk.StringVar(value="—")
        self.invalid_var = tk.StringVar(value="—")
        self.mode_var = tk.StringVar(value="—")
        self.state_var = tk.StringVar(value="—")
        self.demo_var = tk.StringVar(value="—")
        self.page_var = tk.StringVar(value="—")
        self.hint_var = tk.StringVar(value="—")
        self.action_var = tk.StringVar(value="—")

        self.build_ui()
        self.refresh_ports()

        if demo:
            self.apply_frame(
                [["1", "2", "3"], ["4", "5", "6"], ["7", "0", "8"]],
                {"v": 0, "i": 0, "w": 0, "m": 1, "s": 0, "d": 0, "led": 0x0B0C},
            )
            self.status_var.set("示例模式（未连接串口）")
            self.last_var.set("示例棋盘 123456708")
        else:
            self.root.after(500, self.try_autoconnect)

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(50, self.poll_queue)

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        self.root.title("EGO1 数字华容道")
        self.root.geometry("660x930")
        self.root.minsize(600, 840)
        self.root.configure(bg=BG)

        header = tk.Frame(self.root, bg=HEADER, padx=24, pady=16)
        header.pack(fill="x")
        tk.Label(header, text="数字华容道", bg=HEADER, fg="#ffffff",
                 font=("Microsoft YaHei UI", 22, "bold")).pack(anchor="w")
        tk.Label(header, text="EGO1 · UART 9600 8N1 · 3x3 实时棋盘与状态",
                 bg=HEADER, fg="#cfe3dc",
                 font=("Microsoft YaHei UI", 10)).pack(anchor="w", pady=(4, 0))

        toolbar = tk.Frame(self.root, bg=BG, padx=24, pady=12)
        toolbar.pack(fill="x")

        tk.Label(toolbar, text="串口", bg=BG, fg="#3c3a34",
                 font=("Microsoft YaHei UI", 10)).pack(side="left")

        self.port_box = ttk.Combobox(toolbar, textvariable=self.port_var,
                                     width=10, state="readonly",
                                     font=("Consolas", 10))
        self.port_box.pack(side="left", padx=(8, 6))

        self.refresh_btn = tk.Button(toolbar, text="刷新", command=self.refresh_ports,
                                     bg="#e6dfd1", fg="#2f2c26", bd=0,
                                     padx=12, pady=6, cursor="hand2",
                                     font=("Microsoft YaHei UI", 10))
        self.refresh_btn.pack(side="left", padx=(0, 6))

        self.connect_btn = tk.Button(toolbar, text="连接", command=self.toggle_connection,
                                     bg=ACCENT, fg="#ffffff", bd=0,
                                     padx=18, pady=6, cursor="hand2",
                                     font=("Microsoft YaHei UI", 10, "bold"))
        self.connect_btn.pack(side="left")

        # 棋盘卡片
        card = tk.Frame(self.root, bg=PANEL, padx=22, pady=22,
                        highlightbackground=GRID, highlightthickness=1)
        card.pack(fill="both", expand=True, padx=24, pady=(0, 10))

        board = tk.Frame(card, bg=PANEL)
        board.pack(fill="both", expand=True)

        for r in range(3):
            board.grid_rowconfigure(r, weight=1)
            for c in range(3):
                board.grid_columnconfigure(c, weight=1)
                lbl = tk.Label(board, text="—", width=4, height=2,
                               bg=MUTED, fg=MUTED_FG,
                               font=("Microsoft YaHei UI", 34, "bold"),
                               bd=0, relief="flat",
                               highlightbackground=GRID,
                               highlightthickness=1)
                lbl.grid(row=r, column=c, padx=6, pady=6, sticky="nsew")
                self.tiles.append(lbl)

        # 状态信息卡片
        info = tk.Frame(self.root, bg=PANEL, padx=18, pady=14,
                        highlightbackground=GRID, highlightthickness=1)
        info.pack(fill="x", padx=24, pady=(0, 10))
        for c in range(4):
            info.grid_columnconfigure(c, weight=1)

        self.add_metric(info, 0, 0, "有效步数", self.valid_var, GOOD)
        self.add_metric(info, 0, 1, "无效步数", self.invalid_var, WARN)
        self.add_metric(info, 0, 2, "模式", self.mode_var, "#3c3a34")
        self.add_metric(info, 0, 3, "状态", self.state_var, "#3c3a34")
        self.add_metric(info, 1, 0, "演示步", self.demo_var, "#3c3a34")
        self.add_metric(info, 1, 1, "LED 页", self.page_var, "#3c3a34")
        self.add_wide_metric(info, 1, 2, "可移动棋子", self.hint_var)
        self.add_wide_metric(info, 1, 3, "最近操作", self.action_var, span=1)

        # 16 个 LED
        led_card = tk.Frame(self.root, bg=PANEL, padx=18, pady=12,
                            highlightbackground=GRID, highlightthickness=1)
        led_card.pack(fill="x", padx=24, pady=(0, 10))
        tk.Label(led_card, text="板载 LED（D0 → D15）", bg=PANEL, fg="#7a7264",
                 font=("Microsoft YaHei UI", 9)).pack(anchor="w", pady=(0, 6))
        led_row = tk.Frame(led_card, bg=PANEL)
        led_row.pack(anchor="w")

        for i in range(16):
            lbl = tk.Label(led_row, text=f"D{i}", width=2, height=1,
                           bg="#e5ded0", fg="#9a917f",
                           font=("Consolas", 7), bd=0)
            padx = (0, 8) if i in (7, 11) else (0, 2)
            lbl.pack(side="left", padx=padx)
            self.led_labels.append(lbl)

        # 状态栏
        status = tk.Frame(self.root, bg=BG, padx=24, pady=6)
        status.pack(fill="x")
        tk.Label(status, textvariable=self.status_var, bg=BG, fg="#3c3a34",
                 font=("Microsoft YaHei UI", 10)).pack(side="left")
        tk.Label(status, textvariable=self.last_var, bg=BG, fg="#7a7264",
                 font=("Microsoft YaHei UI", 9)).pack(side="right")

        log_frame = tk.Frame(self.root, bg=BG, padx=24, pady=0)
        log_frame.pack(fill="x", pady=(0, 14))
        self.log_text = tk.Text(log_frame, height=5, bg="#1f2933", fg="#d9e2ec",
                                insertbackground="#d9e2ec", bd=0,
                                font=("Consolas", 9), padx=10, pady=8,
                                state="disabled")
        self.log_text.pack(fill="x")

    def add_metric(self, parent, row, col, label, var, color="#3c3a34"):
        frame = tk.Frame(parent, bg=PANEL, padx=6, pady=4)
        frame.grid(row=row, column=col, sticky="nsew")
        tk.Label(frame, text=label, bg=PANEL, fg="#8a8173",
                 font=("Microsoft YaHei UI", 9)).pack(anchor="w")
        tk.Label(frame, textvariable=var, bg=PANEL, fg=color,
                 font=("Microsoft YaHei UI", 15, "bold")).pack(anchor="w")

    def add_wide_metric(self, parent, row, col, label, var, span=1):
        frame = tk.Frame(parent, bg=PANEL, padx=6, pady=4)
        frame.grid(row=row, column=col, columnspan=span, sticky="nsew")
        tk.Label(frame, text=label, bg=PANEL, fg="#8a8173",
                 font=("Microsoft YaHei UI", 9)).pack(anchor="w")
        tk.Label(frame, textvariable=var, bg=PANEL, fg="#3c3a34",
                 font=("Microsoft YaHei UI", 11, "bold")).pack(anchor="w")

    # -------------------------------------------------------------- serial
    def refresh_ports(self):
        if self.ser:
            return
        ports = list(list_ports.comports())
        ports.sort(key=lambda p: (0 if "CP210" in (p.description or "").upper() else 1,
                                  p.device))
        devices = [p.device for p in ports]
        self.port_box["values"] = devices

        if not devices:
            self.port_var.set("")
            self.status_var.set("未找到串口，请检查 USB-UART 线")
            return

        selected = self.port
        if selected not in devices:
            selected = next((p.device for p in ports
                             if "CP210" in (p.description or "").upper()), devices[0])
            self.port = selected
        self.port_var.set(selected)

    def try_autoconnect(self):
        if self.autoconnect and self.port_var.get():
            self.connect()

    def toggle_connection(self):
        if self.ser:
            self.disconnect()
        else:
            self.connect()

    def connect(self):
        if self.ser:
            return
        port = self.port_var.get().strip()
        if not port:
            messagebox.showwarning("没有串口", "请先选择串口。")
            return
        try:
            self.ser = serial.Serial(port, BAUD, bytesize=8,
                                     parity="N", stopbits=1, timeout=0.5)
        except Exception as exc:
            self.ser = None
            messagebox.showerror("串口打开失败", f"{port}\n\n{exc}")
            self.status_var.set(f"无法打开 {port}")
            return

        self.port = port
        self.parser = BoardParser()
        self.frames = 0
        self.prev_status = None
        self.stop_event.clear()
        self.reader = threading.Thread(target=self.read_loop, args=(self.ser,),
                                       daemon=True)
        self.reader.start()

        self.connect_btn.config(text="断开", bg=DANGER)
        self.status_var.set(f"已连接 {port} @ {BAUD} 8N1")
        self.log(f"connected {port} @ {BAUD} 8N1")

    def disconnect(self):
        self.stop_event.set()
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None
        self.connect_btn.config(text="连接", bg=ACCENT)
        self.status_var.set("已断开")
        self.log("disconnected")

    def read_loop(self, ser):
        try:
            while not self.stop_event.is_set():
                raw = ser.readline()
                if not raw:
                    continue
                try:
                    line = raw.decode("ascii", "replace").strip("\r\n")
                except Exception:
                    continue
                self.queue.put(("line", line))
        except Exception as exc:
            self.queue.put(("error", str(exc)))

    def poll_queue(self):
        try:
            while True:
                kind, payload = self.queue.get_nowait()
                if kind == "line":
                    self.on_line(payload)
                elif kind == "error":
                    self.log(f"serial error: {payload}")
                    self.disconnect()
        except queue.Empty:
            pass
        self.root.after(50, self.poll_queue)

    def on_line(self, line):
        result = self.parser.feed(line)
        if result:
            rows, status = result
            self.apply_frame(rows, status)

    # --------------------------------------------------------------- board
    def apply_frame(self, rows, status):
        flat = [v for row in rows for v in row]
        self.update_tiles(flat)
        self.hint_var.set(self.format_hints(flat))

        if status:
            self.update_status(status)
            action = self.infer_action(flat, status)
        else:
            self.valid_var.set("—")
            self.invalid_var.set("—")
            self.mode_var.set("—")
            self.state_var.set("—")
            self.demo_var.set("—")
            self.page_var.set("—")
            action = "棋盘更新"

        self.action_var.set(action)
        self.frames += 1
        self.last_var.set("最后更新 " + time.strftime("%H:%M:%S"))

        if not self.demo:
            self.status_var.set(f"已连接 {self.port} @ {BAUD} 8N1 · 帧 {self.frames}")

        if action != "同步" or self.prev_status is None:
            if status:
                self.log(f"{action} | V{status['v']} I{status['i']} "
                         f"W{status['w']} M{status['m']} D{status['d']}")
            else:
                self.log(action)

        if status:
            self.prev_status = {
                "board": flat,
                "v": status["v"],
                "i": status["i"],
                "w": status["w"],
                "m": status["m"],
                "s": status["s"],
                "d": status["d"],
            }

    def update_tiles(self, flat):
        for lbl, val in zip(self.tiles, flat):
            if val == "0":
                lbl.config(text="空", bg=EMPTY, fg=EMPTY_FG,
                           font=("Microsoft YaHei UI", 12))
            elif val == "-":
                lbl.config(text="—", bg=MUTED, fg=MUTED_FG,
                           font=("Microsoft YaHei UI", 26, "bold"))
            else:
                lbl.config(text=val, bg=TILE, fg=TILE_FG,
                           font=("Microsoft YaHei UI", 34, "bold"))

    def update_status(self, st):
        self.valid_var.set(str(st["v"]))
        self.invalid_var.set(str(st["i"]))
        self.page_var.set("统计页" if st["s"] else "提示页")

        mode_names = {0: "初始化", 1: "游戏", 2: "演示"}
        self.mode_var.set(mode_names.get(st["m"], "?"))

        if st["w"]:
            self.state_var.set("已通关")
        elif st["m"] == 0:
            self.state_var.set("等待初始化")
        elif st["m"] == 2:
            self.state_var.set(f"演示第 {st['d']} 步")
        else:
            self.state_var.set("进行中")

        self.demo_var.set(f"第 {st['d']} 步" if st["m"] == 2 else "—")

        for i, lbl in enumerate(self.led_labels):
            on = (st["led"] >> (15 - i)) & 1
            if on:
                lbl.config(bg="#f2b134", fg="#2f2418")
            else:
                lbl.config(bg="#e5ded0", fg="#9a917f")

    def format_hints(self, flat):
        hints = self.compute_hints(flat)
        if not hints:
            return "无"
        return " ".join(str(x) for x in hints)

    @staticmethod
    def compute_hints(flat):
        try:
            zero = flat.index("0")
        except ValueError:
            return []

        zr, zc = divmod(zero, 3)
        hints = []
        for idx, val in enumerate(flat):
            if val not in "12345678":
                continue
            r, c = divmod(idx, 3)
            if abs(r - zr) + abs(c - zc) == 1:
                hints.append(int(val))
        return sorted(hints)

    def infer_action(self, flat, st):
        prev = self.prev_status
        if prev is None:
            return "首帧"

        if st["m"] == 0 and all(v == "-" for v in flat) and flat != prev["board"]:
            return "复位"

        if st["v"] < prev["v"] or st["i"] < prev["i"]:
            return "撤销"

        if prev["m"] == 0 and st["m"] == 1:
            return "初始化完成，进入游戏"

        if st["m"] != prev["m"]:
            return "模式切换"

        if st["m"] == 2 and st["d"] != prev["d"]:
            return f"演示第 {st['d']} 步"

        if st["w"] != prev["w"]:
            return "通关" if st["w"] else "返回未通关"

        if st["v"] > prev["v"]:
            return "有效移动"

        if st["i"] > prev["i"]:
            return "无效移动"

        if flat != prev["board"]:
            if st["m"] == 0:
                return "初始化输入"
            return "棋盘更新"

        if st["s"] != prev["s"]:
            return "切换 LED 页"

        return "同步"

    def log(self, text):
        ts = time.strftime("%H:%M:%S")
        line = text if text else "<空行>"
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"{ts}  {line}\n")
        try:
            line_count = int(self.log_text.index("end-1c").split(".")[0])
            if line_count > 200:
                self.log_text.delete("1.0", f"{line_count-200}.0")
        except Exception:
            pass
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def on_close(self):
        self.stop_event.set()
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
        self.root.destroy()


def main():
    ap = argparse.ArgumentParser(description="EGO1 数字华容道 UART 监视 GUI")
    ap.add_argument("--port", help="串口名，例如 COM4")
    ap.add_argument("--no-autoconnect", action="store_true",
                    help="启动时不自动连接")
    ap.add_argument("--demo", action="store_true",
                    help="不连接串口，显示示例棋盘")
    args = ap.parse_args()

    root = tk.Tk()
    BoardGUI(root, port=args.port,
             autoconnect=not args.no_autoconnect,
             demo=args.demo)
    root.mainloop()


if __name__ == "__main__":
    main()
