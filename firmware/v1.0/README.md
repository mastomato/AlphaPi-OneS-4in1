# v1.0 固件文件说明

AlphaPi OneS 4合1 · v1.0（2026-11-15）

## 文件清单

| 文件 | 大小 (B) | md5 | 用途 |
|---|---|---|---|
| `AlphaPi-OneS-Desktop-Dark.bin` | 2,692,944 | `b16688411c68e57becaab9ef89d975e6` | 应用固件，写 **0x20000** |
| `bootloader.bin` | 16,080 | `6bbe215da33a337498bf277493618a88` | 二级引导，写 **0x1000** |
| `partition-table.bin` | 3,072 | `6010f63a2f1b62a0a7229304d80cd03c` | 分区表，写 **0x8000** |
| `ota_data_initial.bin` | 8,192 | `84d04c9d6cc8ef35bf825d51a5277699` | OTA 标记，写 **0xD000** |
| `assets.bin` | 1,865,367 | `c23298d3f2ec5a67022336ba07be9a80` | 字库 + 表情资源，写 **0x500000**（首次必带） |
| `AlphaPi-OneS-4in1-v1.0-full-8MB.bin` | 7,108,247 | `df58579d076342ee857233e6b6f27575` | 五段合并完整固件，写 **0x0** |
| `alphapi-one-s-web-flasher.html` | 260,567 | `8120a3c8f1d4cc4b5e60c8c8152963ae` | 网页刷机器（Chrome / Edge） |

## 三种刷法

**① 网页刷机（推荐）**：双击 `start-web-flasher.cmd`，或用 Chrome/Edge 直接打开 `alphapi-one-s-web-flasher.html`，连串口后按页面提示刷写。

**② 脚本刷五段**：双击 `flash.cmd` 并输入串口（如 `COM17`），等价于按 `flash_args.txt` 的参数调用 esptool。

**③ 一步刷完整固件**：

```bash
esptool.py --chip esp32s2 --port COM17 write_flash 0x0 AlphaPi-OneS-4in1-v1.0-full-8MB.bin
```

## 手动五段

```bash
esptool.py --chip esp32s2 --port COM17 --baud 921600 write_flash \
  --flash_mode dio --flash_freq 80m --flash_size 8MB \
  0x1000 bootloader.bin \
  0x8000 partition-table.bin \
  0xd000 ota_data_initial.bin \
  0x20000 AlphaPi-OneS-Desktop-Dark.bin \
  0x500000 assets.bin
```

## 提醒

- 进刷机模式：关机状态下按住 **BOOT** 上电，2 秒后松开。
- `assets.bin` 必须写，否则中文与表情显示为方块。
- 不写 `0x9000`（NVS），升级一般保留配网与小智绑定；要彻底重来用 `esptool erase_flash`。
- 刷完关机 3–5 秒再开机（板载电池，只拔 USB 可能不重启）。
