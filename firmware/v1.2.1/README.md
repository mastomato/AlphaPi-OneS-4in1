# v1.2.1 收音机诊断与优先级回退

- 发布时间：2026-11-16 14:21
- app：2708720 B / md5 `4980219016264dc455cf6fc322cfda34`
- 刷机：五段（含 assets 资源包），见 flash.cmd / start-web-flasher.cmd
- assets.bin 写 0x500000（2MB 分区，普惠体字库 + 21 个表情），首次刷必带
- 源码快照：source-snapshot/

## 本版改动

**这一版先说清楚一件事：源码对比下来，收音机自己的代码从 v46 到现在一行都没变过。**

拿 v46（收音机正常）与 v51 的快照逐文件对比：

| 文件 | 差异 | 能否解释断流 |
| --- | --- | --- |
| `radio_player.cc` / `radio_config.h` | **零差异** | — |
| `n32_audio.cc` | ACK 200→120ms、8bit 四舍五入、间隙计数（自愈已撤） | 都不能 |
| `audio_service.cc` | `audio_output` 5→6 | **唯一动过的音频侧参数** |
| `st7789.cc` / `desktop_board.cc` | 脏行推送、渲染节流 | 收音机页两版都是每 800ms 推一次，相同 |

所以本版做两件事：**把 v47 唯一动过的那个参数退回 v46 的值**，**并让收音机自己把断流原因报出来**。

### 一、`audio_output` 6 → 5（退回 v46）

v47 把它提到 6，想让小智的输出严格高于 UI(5)。但它同时也高于收音机的 `radio_net(5)`，而收音机播放时 AudioService 的三个任务（`audio_input=8` / `output` / `opus_codec=4`）依然存在，output 任务即使空闲也要周期性醒来拿 `audio_queue_mutex_`。既然收音机代码本身没有任何改动，这个"v47 唯一改过的音频侧参数"就必须先退回做排除。

### 二、收音机自带诊断（关键）

之前一直查不动，根因是**收音机不走 AudioService**——`/api/status` 里那组 `play_*` 是小智的 Opus 播放链路，收音机断流在它里面根本不会出现。现在给 `RadioPlayer` 加了 8 个计数器并接到 HTTP：

| 字段 | 含义 | 怎么读 |
| --- | --- | --- |
| `radio_rebuffers` | 进入 BUFFERING/REBUFFERING 的次数（边沿计数，不是轮数） | 就是用户听到的「断一下」 |
| `radio_recv_timeout` | PlaybackTask 取 PCM 拿到 0 字节 | PCM 缓冲被彻底打空 |
| `radio_write_fail` | Write 到 N32 的字节数不足 | **UART/N32 侧问题** |
| `radio_net_err` | HTTP 读返回 ≤0 或非 2xx | **网络/电台侧问题** |
| `radio_dec_err` | MP3 解码失败 | **解码侧问题** |
| `radio_pcm_now` / `radio_pcm_min` | 当前 / 历史最低 PCM 水位（满 144000 B ≈ 3 秒） | 最低值贴着 0 = 喂不上 |
| `radio_starve_ms` | 等 PCM 的累计毫秒 | 值大 = 供给不足 |

`run-net-diag.cmd` 已同步更新：采样时只要有收音机活动就多打一行 `RADIO rebuf= recvto= wfail= neterr= decerr= pcm= min= starve+`，末尾还会直接给出「是网络、解码、还是写 N32」的结论。

### 三、顺手修掉的两处

- `ones_net_diag.ps1` 不再请求 `/api/log`（该端点在 v50 已撤掉，之前只是被 catch 吞掉）。
- `io_gaps` 的判读文字更正：v51 起它只统计「超过 500ms 的写流间隙」，**不再据此重开会话**，所以它本身不会造成断音。
- `PlaybackTask` 里那句「让出 1 tick（10ms）」的注释更正为 1ms（`CONFIG_FREERTOS_HZ=1000`）。

## 校验值

| 文件 | 地址 | md5 |
| --- | --- | --- |
| `bootloader.bin` | `0x1000` | `760d65facec685876f397990d1529e62` |
| `partition-table.bin` | `0x8000` | `6010f63a2f1b62a0a7229304d80cd03c` |
| `ota_data_initial.bin` | `0xd000` | `84d04c9d6cc8ef35bf825d51a5277699` |
| `AlphaPi-OneS-Desktop-Dark.bin` | `0x20000` | `4980219016264dc455cf6fc322cfda34` |
| `assets.bin` | `0x500000` | `2a944aea9985a12d806479e94b094622` |
| 完整固件 8MB | `0x0` | `a99d4af202587a3ae402849b11f1bc8e` |

- app **2,708,720 B**，app 分区余 47%
- **assets 自 v44 未变 → 只刷 app 即可**

## 刷机（本板两个坑）

1. **RTS 接不到 EN**：`Hard resetting via RTS pin` 是空动作，**刷完芯片停在 ROM 下载模式，必须手动拨 OFF→ON**。
2. esptool 5.6 在这块板 stub 阶段必失败，用 4.8.1 或 5.6 `--no-stub`。

## 刷完请这样测（重要）

1. 进收音机，**连续播 3~5 分钟**，期间故意切一次台
2. 跑本目录的 `run-net-diag.cmd`（会覆盖同名的旧脚本）
3. 把生成的 `ones_net_diag_*.txt` 发回

日志末尾的「收音机」段会直接写出：断缓冲几次、PCM 最低水位多少、以及**是网络、解码还是写 N32 的问题**。下一版就能对着数据修，不用再改一版猜一次。

