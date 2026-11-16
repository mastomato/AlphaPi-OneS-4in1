#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AlphaPi OneS 启动故障诊断（刷完不停重启 / 开不了机时用这个）

它做三件事，全程只读取、不写 flash：
  1. 列出电脑上所有串口，让你确认选哪个
  2. 抓 20 秒串口输出（设备自己重启时会不断打印，正好能抓到启动日志）
  3. 用 esptool 读芯片型号、Flash 型号/容量、PSRAM 情况

把生成的 ones_diag_*.txt 整个发回来即可。

用法：
    python ones_boot_diag.py                  # 自动找串口
    python ones_boot_diag.py --port COM20     # 指定串口
    python ones_boot_diag.py --seconds 30     # 抓更久
    python ones_boot_diag.py --skip-flash-id  # 只抓日志，不碰 flash（最保守）

依赖：pyserial + esptool（ESP-IDF 的 python 环境里都有）。
"""

import argparse
import glob
import os
import sys
import time

BAUD = 115200


def log(msg):
    print(msg, flush=True)


def find_ports():
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    out = []
    for p in list_ports.comports():
        out.append((p.device, p.description or ""))
    return sorted(out)


def autodetect():
    ports = find_ports()
    if not ports:
        return None
    # 优先常见的 USB 串口
    for dev, desc in ports:
        d = (dev or "").upper()
        t = (desc or "").lower()
        if "COM" in d and ("usb" in t or "ch34" in t or "cp210" in t or "silicon" in t
                           or "uart" in t or "serial" in t):
            return dev
    return ports[0][0]


def capture(port, seconds):
    """抓串口输出，返回 (字节数, 文本片段)。设备一直重启时会有多段启动日志。"""
    import serial
    log(f"\n[2/3] 正在监听 {port} @ {BAUD}，持续 {seconds} 秒……")
    log("       （设备会自动重启，请保持通电，不要按键）")
    buf = bytearray()
    started = time.time()
    try:
        with serial.Serial(port, BAUD, timeout=0.3) as ser:
            ser.reset_input_buffer()
            last_report = 0
            while time.time() - started < seconds:
                chunk = ser.read(4096)
                if chunk:
                    buf.extend(chunk)
                    last_report = time.time()
                elif time.time() - last_report > 5 and len(buf) == 0:
                    pass
    except Exception as e:  # 串口被占用 / 拔掉
        log(f"      !! 串口读取失败：{e}")
        return bytes(buf)
    text = buf.decode("utf-8", errors="replace")
    log(f"      收到 {len(buf)} 字节")
    return text


def flash_info(port):
    """读芯片与 flash 型号。只发读命令，不写任何东西。"""
    log(f"\n[3/3] 读取芯片 / Flash 信息（{port}）……")
    try:
        import esptool
    except ImportError:
        log("      !! 没有 esptool，跳过这一步。可在 ESP-IDF 环境里运行。")
        return ""
    import io
    from contextlib import redirect_stdout, redirect_stderr
    buf = io.StringIO()
    old_argv = sys.argv
    try:
        sys.argv = ["esptool", "--chip", "esp32s2", "--port", port,
                    "--before", "default-reset", "--after", "hard-reset",
                    "flash-id"]
        with redirect_stdout(buf), redirect_stderr(buf):
            try:
                esptool.main(sys.argv[1:])
            except SystemExit:
                pass
            except Exception as e:
                buf.write(f"\nesptool error: {e}\n")
    finally:
        sys.argv = old_argv
    out = buf.getvalue()
    log("      完成")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--seconds", type=int, default=20)
    ap.add_argument("--skip-flash-id", action="store_true")
    args = ap.parse_args()

    log("=" * 62)
    log(" AlphaPi OneS 启动故障诊断")
    log("=" * 62)

    ports = find_ports()
    log("\n[1/3] 检测到的串口：")
    if not ports:
        log("      （一个都没有）请检查 USB 线：必须是能传数据的线，不是只能充电的线。")
    for dev, desc in ports:
        log(f"      {dev:<8} {desc}")

    port = args.port or autodetect()
    if not port:
        log("\n没有可用串口，退出。插好 USB 后重试。")
        return 2
    log(f"      使用：{port}")

    text = capture(port, args.seconds)

    info = "" if args.skip_flash_id else flash_info(port)

    # ---- 结论提示 ----
    hints = []
    low = text.lower()
    if not text.strip():
        hints.append("串口 20 秒内一个字都没打印：芯片很可能在 bootloader 阶段就复位了"
                     "（flash 读不出 / app 镜像校验失败），或者串口没接通。")
    if "invalid header" in low or "0xffffffff" in low:
        hints.append("出现 invalid header / 0xffffffff：app 镜像没写进去或者被擦掉了。")
    if "failed to init external ram" in low or "psram" in low and "fail" in low:
        hints.append("PSRAM 初始化失败：这颗板子的 PSRAM 可能没焊、型号不兼容或供电不对。")
    if "brownout" in low:
        hints.append("出现过 brownout：供电不足（换线/换电源，别用电脑前置 USB 或劣质线）。")
    if "panic" in low or "guru meditation" in low:
        hints.append("出现过 panic：程序崩了，看日志里第一处 Backtrace 的地址。")
    if "rst:" in low and low.count("rst:") >= 3:
        hints.append(f"日志里出现 {low.count('rst:')} 次启动头：确认是在反复重启。")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    out_name = f"ones_diag_{stamp}.txt"
    try:
        with open(out_name, "w", encoding="utf-8") as f:
            f.write("AlphaPi OneS boot diagnosis\n")
            f.write(f"time   : {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"port   : {port}\n")
            f.write(f"seconds: {args.seconds}\n")
            f.write("\n===== serial =====")
            f.write("\n" + text)
            f.write("\n\n===== chip / flash =====\n")
            f.write(info)
            f.write("\n\n===== hints =====\n")
            for h in hints:
                f.write("- " + h + "\n")
        log("\n" + "-" * 62)
        log(f"结果已保存：{os.path.abspath(out_name)}")
        log("把这个文件整个发回来。")
        if hints:
            log("\n初步提示：")
            for h in hints:
                log("  · " + h)
        else:
            log("\n没有命中已知故障特征，日志本身仍然有用，请一并发回。")
    except Exception as e:
        log(f"写文件失败：{e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
