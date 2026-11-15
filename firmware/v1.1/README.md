# AlphaPi OneS 4合1 v1.1 固件文件

本目录是 **v1.1（启动容错与刷机自检）** 的刷机文件。如果你的 v1.0 刷完开不了机、一直重启，
请直接用这里的 v1.1 重刷。

## 文件清单

| 文件 | 写入地址 | 大小 | md5 | 说明 |
|---|---|---|---|---|
| `bootloader.bin` | `0x1000` | 16,080 | `6bbe215da33a337498bf277493618a88` | 二级引导 |
| `partition-table.bin` | `0x8000` | 3,072 | `6010f63a2f1b62a0a7229304d80cd03c` | 分区表 |
| `ota_data_initial.bin` | `0xd000` | 8,192 | `84d04c9d6cc8ef35bf825d51a5277699` | OTA 选择数据（空，指向 ota_0） |
| `AlphaPi-OneS-Desktop-Dark.bin` | `0x20000` | 2,694,912 | `88afcb4be90682f28b0ae10ed1f5d30e` | 应用固件 |
| `assets.bin` | `0x500000` | 1,865,367 | `c23298d3f2ec5a67022336ba07be9a80` | 资源包（中文字库 + 21 个表情） |
| `AlphaPi-OneS-4in1-v1.1-full-8MB.bin` | `0x0` | 7,108,247 | `1b0a072a3d4848ef06c7211f1fa4c609` | 上面五段合并成一个镜像 |

> `assets.bin` **首次刷机必带**。缺了它固件仍能启动，但中文会显示成方块、表情不显示。

## 三种刷法

### 1. 网页刷机（推荐，不需要装任何工具）

双击 `start-web-flasher.cmd`，会启动本地服务并打开浏览器（Chrome / Edge）。
页面上：

1. **勾选「擦除整个 Flash」**（v1.1 起强烈建议，排除旧分区数据干扰）
2. 五段全部选中
3. 连接串口 → 刷入

### 2. 一个文件刷完

只想要最简单的方式，就刷这一条：

```bat
esptool --chip esp32s2 -p COM20 -b 460800 --before default-reset --after hard-reset ^
  write-flash 0x0 AlphaPi-OneS-4in1-v1.1-full-8MB.bin
```

### 3. 命令行五段

```bat
esptool --chip esp32s2 -p COM20 -b 460800 --before default-reset --after hard-reset ^
  write-flash 0x1000 bootloader.bin ^
  0x8000 partition-table.bin ^
  0xd000 ota_data_initial.bin ^
  0x20000 AlphaPi-OneS-Desktop-Dark.bin ^
  0x500000 assets.bin
```

也可以直接运行 `flash.cmd`（Windows 批处理，地址已写死）。

## 开不了机怎么办

看同目录下的 **`BOOT-TROUBLESHOOTING.md`**，按里面的顺序排查。
如果排查完还没解决，双击 **`run-boot-diag.cmd`** 抓一份日志发回来——它只读串口，不写 flash。
