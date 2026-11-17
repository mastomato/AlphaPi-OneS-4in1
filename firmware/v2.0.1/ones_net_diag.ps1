param(
    [string]$Ip = "192.168.1.6",
    [int]$Seconds = 120,
    [int]$IntervalMs = 1500
)

# AlphaPi OneS 网络诊断
#
# 为什么不用串口：这块板子的 console（UART0 / GPIO43）没有引到 USB 口，
# 插上电脑只看得到一颗原生 USB 复合设备（AlphaPi_ONES），串口一个字节都没有。
# v50 起固件把播放链路的计数挂到了 /api/status，日志挂到了 /api/log。
#
# 用法：  .\run-net-diag.cmd            （默认 192.168.1.6，120 秒）
#        .\run-net-diag.cmd 192.168.1.20 180

$ErrorActionPreference = "Stop"
$base = "http://$Ip"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outFile = Join-Path $PSScriptRoot "ones_net_diag_$stamp.txt"
$logFile = Join-Path $PSScriptRoot "ones_net_log_$stamp.txt"

function Say($text, $color = "Gray") {
    Write-Host $text -ForegroundColor $color
    Add-Content -Path $outFile -Value $text -Encoding UTF8
}

function Get-Status {
    (Invoke-WebRequest -Uri "$base/api/status" -TimeoutSec 6 -UseBasicParsing).Content | ConvertFrom-Json
}

function Has($obj, $name) {
    return ($null -ne $obj.PSObject.Properties[$name])
}

Say "=== AlphaPi OneS 网络诊断 ===" "Cyan"
Say "设备 $base"
Say "开始 $stamp"

# --- 预检 ---
try {
    $probe = Get-Status
} catch {
    Say ""
    Say "连不上设备：$($_.Exception.Message)" "Red"
    Say "请确认：1) 设备已连同一个 Wi-Fi  2) IP 正确  3) 能在浏览器打开 $base/ping" "Yellow"
    exit 1
}

if (-not (Has $probe "play_frames")) {
    Say ""
    Say "设备在线，但固件是老版本：/api/status 里没有 play_* 字段。" "Yellow"
    Say "这种版本的心跳只往串口打，而这台机器的串口读不到，所以抓不到任何东西。" "Yellow"
    Say "请先刷 v50 或更新的固件。" "Yellow"
    exit 2
}

Say "IP $($probe.ip)　页面 $($probe.page)　状态码 $($probe.state)　内部堆 $($probe.heap_internal) B"
Say ""
Say "现在去让小智播音乐 / 连续对话，本脚本会持续采样 $Seconds 秒。"
if ($probe.state -ne 6) {
    Say "提示：当前设备状态码是 $($probe.state)，不是 6（播放中），请先让它开口。" "Yellow"
}
Say ""

$header = "{0,-8} {1,-3} {2,5} {3,4} {4,6} {5,4} {6,7} {7,7} {8,3} {9,3} {10,5} {11,5} {12,5}" -f `
    "时间", "状", "帧+", "慢帧", "饥饿ms", "丢包", "队列dq", "队列pq", "ack", "gap", "rst", "stall", "maxms"
Say $header "White"
Say ("-" * 92)

$prev = $probe
$prevAt = Get-Date
$end = (Get-Date).AddSeconds($Seconds)
$sumFrames = 0; $sumSlow = 0; $sumStarve = 0; $sumDrops = 0
$sumAck = 0; $sumGap = 0; $sumRst = 0; $sumStall = 0
# v52：收音机自己的计数（收音机不走 AudioService，play_* 那组看不到它）
$sumReb = 0; $sumRecvTo = 0; $sumWf = 0; $sumNetErr = 0; $sumDecErr = 0
$samples = 0
$errors = 0
$lastLogFetch = Get-Date
$allLog = New-Object System.Text.StringBuilder

while ((Get-Date) -lt $end) {
    Start-Sleep -Milliseconds $IntervalMs
    try {
        $cur = Get-Status
    } catch {
        $errors++
        Say ("{0,-8} 读取失败：{1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message) "Red"
        continue
    }

    $dFrames = [int]$cur.play_frames - [int]$prev.play_frames
    $dSlow = [int]$cur.play_slow - [int]$prev.play_slow
    $dStarve = [int]$cur.play_starve_ms - [int]$prev.play_starve_ms
    $dDrops = [int]$cur.play_drops - [int]$prev.play_drops
    $dAck = [int]$cur.io_ackfail - [int]$prev.io_ackfail
    $dGap = [int]$cur.io_gaps - [int]$prev.io_gaps
    $dRst = [int]$cur.io_resets - [int]$prev.io_resets
    $dStall = [int]$cur.io_stalls - [int]$prev.io_stalls

    $sumFrames += $dFrames; $sumSlow += $dSlow; $sumStarve += $dStarve; $sumDrops += $dDrops
    $sumAck += $dAck; $sumGap += $dGap; $sumRst += $dRst; $sumStall += $dStall
    $samples++

    # v52：收音机的断流证据。收音机有自己的三段流水线（net -> decode -> playback）
    # 且不走 AudioService，所以上面那组 play_* 完全看不到它。老固件没有这些字段。
    $hasRadio = Has $cur "radio_rebuffers"
    $dReb = 0; $dRecvTo = 0; $dWf = 0; $dNetErr = 0; $dDecErr = 0
    if ($hasRadio) {
        $dReb    = [int]$cur.radio_rebuffers    - [int]$prev.radio_rebuffers
        $dRecvTo = [int]$cur.radio_recv_timeout - [int]$prev.radio_recv_timeout
        $dWf     = [int]$cur.radio_write_fail   - [int]$prev.radio_write_fail
        $dNetErr = [int]$cur.radio_net_err      - [int]$prev.radio_net_err
        $dDecErr = [int]$cur.radio_dec_err      - [int]$prev.radio_dec_err
        $sumReb += $dReb; $sumRecvTo += $dRecvTo; $sumWf += $dWf
        $sumNetErr += $dNetErr; $sumDecErr += $dDecErr
    }

    $color = "Gray"
    if ($dSlow -gt 0 -or $dDrops -gt 0 -or $dGap -gt 0) { $color = "Yellow" }
    if ($dDrops -gt 0 -or $dGap -gt 0 -or $dRst -gt 0) { $color = "Red" }

    Say ("{0,-8} {1,-3} {2,5} {3,4} {4,6} {5,4} {6,3}/{7,-3} {8,3}/{9,-3} {10,3} {11,3} {12,5} {13,5} {14,5}" -f `
        (Get-Date -Format "HH:mm:ss"), $cur.state, $dFrames, $dSlow, $dStarve, $dDrops,
        $cur.decode_queue, 20, $cur.playback_queue, 5,
        $dAck, $dGap, $dRst, $dStall, $cur.play_max_ms) $color

    # 有收音机活动才多打一行，避免刷屏
    if ($hasRadio -and ($dReb -gt 0 -or $dRecvTo -gt 0 -or $dWf -gt 0 -or $dNetErr -gt 0 -or $dDecErr -gt 0)) {
        Say ("         RADIO  rebuf={0} recvto={1} wfail={2} neterr={3} decerr={4}  pcm={5}B min={6}B starve+{7}ms" -f `
            $dReb, $dRecvTo, $dWf, $dNetErr, $dDecErr,
            $cur.radio_pcm_now, $cur.radio_pcm_min,
            ([int]$cur.radio_starve_ms - [int]$prev.radio_starve_ms)) "Magenta"
    }

    $prev = $cur
    $prevAt = Get-Date

    # 每 15 秒把设备端日志取回来（取完清空，避免重复）
    if (((Get-Date) - $lastLogFetch).TotalSeconds -ge 15) {
        $lastLogFetch = Get-Date
        try {
            $txt = (Invoke-WebRequest -Uri "$base/api/log?clear=1" -TimeoutSec 8 -UseBasicParsing).Content
            if ($txt -and $txt.Length -gt 0 -and $txt -notmatch "log sink unavailable|\(log empty\)") {
                [void]$allLog.Append($txt)
            }
        } catch { }
    }
}

Say ("-" * 92)
Say ""
Say "=== 汇总 ===" "Cyan"
$elapsed = ((Get-Date) - $prevAt).TotalSeconds
Say ("采样 {0} 次，读取失败 {1} 次" -f $samples, $errors)
Say ("播放帧 {0} 帧（每帧约 60ms，合计约 {1:N1} 秒音频）" -f $sumFrames, ($sumFrames * 0.06))
Say ("慢帧   {0} 次   ← 单帧写流超过 60ms，值大说明 UART 写不进实时" -f $sumSlow)
Say ("饥饿   {0} ms   ← 等播放队列的累计时间，值大说明解码/网络供不上" -f $sumStarve)
Say ("丢包   {0} 次   ← 解码队列满被丢掉的 Opus 包" -f $sumDrops)
Say ("UART   ack失败 {0} / 流间隙 {1} / 链路复位 {2} / N32背压 {3}" -f $sumAck, $sumGap, $sumRst, $sumStall)
Say ""
Say "=== 收音机（v52 起）===" "Cyan"
if (-not (Has $probe "radio_rebuffers")) {
    Say "这台设备是 v52 之前的固件，没有 radio_* 字段。" "Yellow"
} else {
    Say ("断缓冲 {0} 次   ← 用户听到的「断一下」，进入 BUFFERING/REBUFFERING 的次数" -f $sumReb)
    Say ("取吐超时 {0} 次 ← PlaybackTask 取 PCM 拿走 0 字节，PCM 缓冲被彻底打空" -f $sumRecvTo)
    Say ("写失败 {0} 次    ← Write 到 N32 的字节数不足（UART/N32 侧）" -f $sumWf)
    Say ("网络错误 {0} 次  ← HTTP 读返回 <=0 或非 2xx（网络/电台侧）" -f $sumNetErr)
    Say ("解码错误 {0} 次  ← MP3 解码失败" -f $sumDecErr)
    # 固件里 kPcmBufferBytes = 24000 * 2 * 3 = 144000 B（约 3 秒）
    Say ("PCM 水位 当前 {0} B / 历史最低 {1} B（满 144000 B ≈ 3 秒，最低值贴着 0 就是喂不上）" -f `
        $cur.radio_pcm_now, $cur.radio_pcm_min)
}
Say ""

$verdict = @()
if ($sumDrops -gt 0) { $verdict += "解码队列溢出丢包 $sumDrops 个 —— 解码跟不上，考虑降队列压力或提高解码优先级" }
if ($sumGap -gt 0) { $verdict += "检测到 $sumGap 次超过 500ms 的写流间隙（v52 起只统计、不再重开会话，所以它本身不会造成断音，只是'某一路流停了'的记录）" }
if ($sumAck -gt 0) { $verdict += "UART ACK 失败 $sumAck 次 —— 写事务时序有问题" }
if ($sumSlow -gt [math]::Max(2, $samples / 20)) { $verdict += "慢帧比例偏高（$sumSlow / $sumFrames）—— UART 写流是瓶颈" }
if ($sumStarve -gt ($samples * 150)) { $verdict += "饥饿累计 $sumStarve ms —— 解码/网络是瓶颈" }

# 收音机判读：三选一定位「是谁把 PCM 打空」
if ($hasRadio -and $sumReb -gt 0) {
    if ($sumNetErr -gt 0 -and $sumDecErr -eq 0) {
        $verdict += "收音机断缓冲来自网络侧（net_err $sumNetErr 次，解码错误 0）—— 电台拉流断了或服务器限速，不是固件问题"
    } elseif ($sumDecErr -gt 0 -and $sumNetErr -eq 0) {
        $verdict += "收音机断缓冲来自**解码侧**（dec_err $sumDecErr 次，网络 0）—— MP3 解码出错或码率不支持"
    } elseif ($sumWf -gt 0) {
        $verdict += "收音机断缓冲来自**写 N32 侧**（wfail $sumWf 次）—— UART 写流失败，属固件问题"
    } elseif ($sumRecvTo -gt 0) {
        $verdict += "收音机 PCM 被打空 $sumRecvTo 次，但网络/解码/写流都没报错 —— 供给速率不够（解码比播放慢）；最低水位 $($cur.radio_pcm_min) B，贴着 0 就是喂不上"
    } else {
        $verdict += "收音机进入过缓冲态 $sumReb 次但没有取吐超时/写失败 —— 多为切台或暂停后的正常预缓冲"
    }
}
if ($verdict.Count -eq 0) {
    $verdict += "这条链路看起来正常：没有丢包、没有断流、没有 ACK 失败。若实机仍卡，问题在 N32 侧（DAC/缓冲）或音箱/供电，不在 ESP32 的写流。"
}
Say "判读：" "Cyan"
foreach ($v in $verdict) { Say ("  · " + $v) }

if ($allLog.Length -gt 0) {
    [System.IO.File]::WriteAllText($logFile, $allLog.ToString(), [System.Text.Encoding]::UTF8)
    Say ""
    Say "设备端日志已存：$logFile" "Green"
}

Say ""
Say "报告：$outFile" "Green"
