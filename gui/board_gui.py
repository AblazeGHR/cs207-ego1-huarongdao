#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EGO1 数字华容道 PC 监视 GUI。

读取板载 CP2102 的串口（9600 8N1），解析 FPGA 发来的 3x3 ASCII 棋盘并绘图。
默认自动连接 CP210x；也可以用 --port COM4 指定串口。
"""

import argparse
import queue
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


class BoardParser:
    """把串口行组装成 3x3 棋盘。"""

    def __init__(self):
        self.rows = []

    def feed(self, line: str):
        line = line.strip()
        if not line:
            if len(self.rows) == 3:
                board = [row[:] for row in self.rows]
                self.rows = []
                return board
            self.rows = []
            return None

        parts = line.split()
        if len(parts) == 3 and all(p in "-0123456789" for p in parts):
            self.rows.append(parts)
            if len(self.rows) > 3:
                self.rows = self.rows[-3:]
        else:
            self.rows = []
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

        self.port_var = tk.StringVar()
        self.status_var = tk.StringVar(value="未连接")
        self.last_var = tk.StringVar(value="等待数据")

        self.build_ui()
        self.refresh_ports()

        if demo:
            self.apply_board([
                ["1", "2", "3"],
                ["4", "5", "6"],
                ["7", "0", "8"],
            ])
            self.status_var.set("示例模式（未连接串口）")
            self.last_var.set("示例棋盘 123456708")
        else:
            self.root.after(500, self.try_autoconnect)

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(50, self.poll_queue)

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        self.root.title("EGO1 数字华容道")
        self.root.geometry("600x780")
        self.root.minsize(540, 700)
        self.root.configure(bg=BG)

        header = tk.Frame(self.root, bg=HEADER, padx=24, pady=18)
        header.pack(fill="x")
        tk.Label(header, text="数字华容道", bg=HEADER, fg="#ffffff",
                 font=("Microsoft YaHei UI", 22, "bold")).pack(anchor="w")
        tk.Label(header, text="EGO1 · UART 9600 8N1 · 3x3 实时棋盘",
                 bg=HEADER, fg="#cfe3dc",
                 font=("Microsoft YaHei UI", 10)).pack(anchor="w", pady=(4, 0))

        toolbar = tk.Frame(self.root, bg=BG, padx=24, pady=14)
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
                        highlightbackground="#ddd5c6", highlightthickness=1)
        card.pack(fill="both", expand=True, padx=24, pady=(0, 12))

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
                               highlightbackground="#d4ccbd",
                               highlightthickness=1)
                lbl.grid(row=r, column=c, padx=6, pady=6, sticky="nsew")
                self.tiles.append(lbl)

        legend = tk.Frame(self.root, bg=BG, padx=24)
        legend.pack(fill="x")

        self.add_legend(legend, "1-8 棋子", TILE, TILE_FG)
        self.add_legend(legend, "0 空位", EMPTY, EMPTY_FG)
        self.add_legend(legend, "- 未初始化", MUTED, MUTED_FG)

        tk.Label(legend, text="步数/提示看开发板 LED",
                 bg=BG, fg="#7a7264",
                 font=("Microsoft YaHei UI", 9)).pack(side="right")

        # 状态与日志
        status = tk.Frame(self.root, bg=BG, padx=24, pady=8)
        status.pack(fill="x")
        tk.Label(status, textvariable=self.status_var, bg=BG, fg="#3c3a34",
                 font=("Microsoft YaHei UI", 10)).pack(side="left")
        tk.Label(status, textvariable=self.last_var, bg=BG, fg="#7a7264",
                 font=("Microsoft YaHei UI", 9)).pack(side="right")

        log_frame = tk.Frame(self.root, bg=BG, padx=24, pady=0)
        log_frame.pack(fill="x", pady=(0, 16))
        self.log_text = tk.Text(log_frame, height=5, bg="#1f2933", fg="#d9e2ec",
                                insertbackground="#d9e2ec", bd=0,
                                font=("Consolas", 9), padx=10, pady=8,
                                state="disabled")
        self.log_text.pack(fill="x")

    def add_legend(self, parent, text, color, fg):
        sw = tk.Label(parent, bg=color, width=2, height=1,
                      highlightbackground="#c9c1b2", highlightthickness=1)
        sw.pack(side="left", padx=(0, 4))
        tk.Label(parent, text=text, bg=BG, fg=fg,
                 font=("Microsoft YaHei UI", 9)).pack(side="left", padx=(0, 14))

    # -------------------------------------------------------------- serial
    def refresh_ports(self):
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
        board = self.parser.feed(line)
        if board:
            self.apply_board(board)

    # --------------------------------------------------------------- board
    def apply_board(self, rows):
        flat = [v for row in rows for v in row]
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

        self.frames += 1
        self.last_var.set("最后更新 " + time.strftime("%H:%M:%S"))
        if not self.demo:
            self.status_var.set(f"已连接 {self.port} @ {BAUD} 8N1 · 帧 {self.frames}")
        self.log("棋盘 " + " / ".join(" ".join(r) for r in rows))

    def log(self, text):
        ts = time.strftime("%H:%M:%S")
        line = text if text else "<空行>"
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"{ts}  {line}\n")
        # 只保留最近 200 行
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
