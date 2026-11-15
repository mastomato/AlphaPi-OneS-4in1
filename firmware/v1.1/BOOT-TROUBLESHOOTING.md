# 刷完开不了机 / 不停重启怎么办

先说明一点：**这类现象绝大多数不是"刷坏了硬件"，而是完全可以通过重刷恢复的。**
设备不会因为刷固件而永久损坏——ESP32-S2 的下载模式在 ROM 里，只要芯片还能被电脑识别，就一定能救回来。

下面按"从最可能到最不可能"排，前两步能解决九成以上的情况。

---

## 第 1 步：确认不是线/口的问题（2 分钟）

"不停重启"里最常见的原因其实是**供电不足**，而不是固件：

- 换一根**能传数据**的 USB 线（很多线只能充电，或者只有两根电源线）
- 直接插**主板后置 USB 口**或**独立 5V 电源**，不要用键盘上的 USB 口、不要用延长线、不要用廉价集线器
- 换一台电脑试

供电不稳的典型特征：屏幕亮一下、暗一下、反复如此，串口日志里会出现 `brownout`。

---

## 第 2 步：擦干净重刷（5 分钟）

刷机时如果**残留了旧固件的分区数据**，会出现"新固件刷进去了但起不来"。

用发布包里的网页刷机工具：

1. 打开 `alphapi-one-s-web-flasher.html`（Chrome / Edge，需要 WebSerial 支持）
2. **勾上「擦除整个 Flash」**（重要）
3. 五段全部勾选：`bootloader.bin`、`partition-table.bin`、`ota_data_initial.bin`、应用固件、`assets.bin`
4. 点「连接」→ 选择串口 → 点「刷入」

或者用命令行一步到位（把 `COM20` 换成你的串口）：

```bat
esptool --chip esp32s2 -p COM20 -b 460800 --before default-reset --after hard-reset ^
  erase-flash
esptool --chip esp32s2 -p COM20 -b 460800 --before default-reset --after hard-reset ^
  write-flash 0x0 AlphaPi-OneS-4in1-v1.0-full-8MB.bin
```

> `erase-flash` 会清掉所有分区数据和配网信息，刷完需要重新配网。这是**刻意**的：就是要排除旧数据的干扰。

---

## 第 3 步：还是不行，就把日志抓回来

这一步最有价值。不要只描述"它一直重启"，日志会直接指出卡在哪一环。

### 方法 A：双击 `run-boot-diag.cmd`（推荐，零依赖）

发布包里带了 `run-boot-diag.cmd` + `ones_boot_diag.ps1`：

1. 设备插好 USB、通电
2. 双击 `run-boot-diag.cmd`
3. 按提示选串口（不确定就挨个试，插上/拔下设备看多出来的是哪个）
4. 等 20 秒，它会在同目录生成 `ones_diag_<时间>.txt`
5. **把这个 txt 整份发回来**

它只读串口，不写 flash，不会让设备变得更糟。

### 方法 B：任意串口工具

波特率 **115200**，8N1，抓 20 秒即可。Arduino IDE 的串口监视器、PuTTY、SSCOM 都行。

重点看这几行：

| 日志里出现 | 含义 | 怎么办 |
|---|---|---|
| `rst:0x3 (SW_RESET)` 反复出现 | 确实在循环重启 | 把整段发回来 |
| `rst:0x8 (TG1WDT_SYS_RST)` | 看门狗超时，某个任务卡死 | 同上 |
| `rst:0xc (RTC_SW_CPU_RST)` + `Guru Meditation` | 程序崩溃 | 看第一处 Backtrace |
| `invalid header: 0xffffffff` | 应用镜像没写进去 / 被擦掉了 | 重刷 |
| `Failed to init external RAM` | PSRAM 初始化失败 | 见下方"硬件差异" |
| `brownout` | 供电不足 | 回到第 1 步 |
| 一个字都没有 | 卡在 bootloader 之前 | 见下方"硬件差异" |

---

## 万一是硬件批次差异

同一版型（丝印 `v1.7`）在不同批次上可能焊了**不同型号的 PSRAM 或 Flash**。这颗 ESP32-S2 的内部 RAM 只有 320 KB，
固件把 LVGL 和显示缓冲都放在外挂 PSRAM 上，所以 PSRAM 缺失、型号不兼容、或者跑不上 80 MHz 时，
表现就是"别人刷完能开机，我这台一直重启"。

判断方法：日志里出现 `psram : NOT AVAILABLE`，或者反复停在
`Failed to init external RAM`。

从 **v1.1 起固件已经做了容错**：PSRAM 拿不到不再直接 abort 重启，而是降级运行并把原因打到串口。
如果你刷的是 v1.0 且正好是这类板子，请升级到 v1.1 或更新版本。

---

## 实在救不回来

按住板子上的 **BOOT** 键（GPIO0）不放，再插 USB，然后松开——这样芯片会强制进入下载模式，
无论 flash 里是什么内容都能重新刷写。网页刷机工具在这个状态下也能连上。

如果连下载模式都进不去（电脑完全不认串口），那是 USB 线或接口的问题，不是固件问题。
