# AlphaPi OneS runtime audio diagnostic (zero dependency, Windows PowerShell 5.1)
#
# Usage: double-click run-audio-diag.cmd, or
#        powershell -ExecutionPolicy Bypass -File ones_audio_diag.ps1
#
# This ONLY reads the serial port. It never flashes or resets the device.
# During the capture window, reproduce the problem on the device:
#   - metronome: start it and let it run for the whole window
#   - or XiaoZhi: play music / keep a conversation going
# Result is saved as ones_audio_diag_<timestamp>.txt -- send that whole file back.

param(
    [string]$Port = "",
    [int]$Seconds = 90
)

$ErrorActionPreference = "Stop"
$lines = New-Object System.Collections.ArrayList

function Say($msg, $color) {
    if (-not $color) { $color = "Gray" }
    Write-Host $msg -ForegroundColor $color
    [void]$lines.Add($msg)
}

Say "==============================================================" "Cyan"
Say " AlphaPi OneS runtime AUDIO diagnostic (read-only)" "Cyan"
Say "==============================================================" "Cyan"

$names = [System.IO.Ports.SerialPort]::GetPortNames()
Say "" "Gray"
Say "[1/3] Available COM ports:" "White"
if (-not $names -or $names.Count -eq 0) {
    Say "  None found. Check the USB data cable." "Red"
    Read-Host "Press Enter to exit"
    exit 1
}
foreach ($n in $names) { Say "  $n" "Gray" }

if ([string]::IsNullOrWhiteSpace($Port)) {
    if ($names.Count -eq 1) {
        $Port = $names[0]
    } else {
        Say "" "Gray"
        Say "  Several ports. Unplug/replug the device to see which one appears." "Yellow"
        $Port = Read-Host "  Enter port name (e.g. COM20)"
    }
}
Say "  Using: $Port" "Green"

Say "" "Gray"
Say "[2/3] Capturing $Port @ 115200 for $Seconds seconds." "White"
Say "  NOW reproduce the problem (metronome running / XiaoZhi playing music)." "Yellow"
Say "  Keep it going for the entire capture window." "Yellow"
Say "" "Gray"

$sp = $null
$raw = New-Object System.Text.StringBuilder
$deadline = (Get-Date).AddSeconds($Seconds)
try {
    $sp = New-Object System.IO.Ports.SerialPort($Port, 115200, "None", 8, "One")
    $sp.Encoding = [System.Text.Encoding]::UTF8
    $sp.ReadTimeout = 500
    # v49：**不要**动 DTR/RTS。原来这里把两个都拉高，在带自动复位三极管的板子上
    # 等于把 EN 压在地电位，芯片一直处于复位态 —— 上一次抓 90 秒收到 0 字节就是
    # 这个原因。让串口保持完全被动的监听状态。
    $sp.DtrEnable = $false
    $sp.RtsEnable = $false
    $sp.Open()
    $sp.DiscardInBuffer()
    $got_any = $false
    $hint_shown = $false
    $start_at = Get-Date
    while ((Get-Date) -lt $deadline) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -and $chunk.Length -gt 0) {
                $got_any = $true
                [void]$raw.Append($chunk)
                Write-Host $chunk -NoNewline
            } else {
                Start-Sleep -Milliseconds 100
            }
        } catch [System.TimeoutException] {
            Start-Sleep -Milliseconds 100
        } catch {
            Start-Sleep -Milliseconds 200
        }
        if (-not $got_any -and -not $hint_shown -and ((Get-Date) - $start_at).TotalSeconds -gt 12) {
            $hint_shown = $true
            Say "" "Yellow"
            Say "  [warn] 12 秒还没有收到任何字节，按顺序检查：" "Yellow"
            Say "    1) 是不是被别的串口工具占着（PuTTY / 串口监视器 / 上一次的脚本）" "Yellow"
            Say "    2) 按一下设备复位键，开机日志会立刻出现" "Yellow"
            Say "    3) 设备空闲时本来就不打日志 —— 必须让它在放音（小智放音乐/对话）" "Yellow"
            Say "    4) 端口选错了（本脚本只读，不会刷机也不会复位）" "Yellow"
            Say "" "Yellow"
        }
    }
} catch {
    Say "  ERROR opening port: $($_.Exception.Message)" "Red"
} finally {
    if ($sp) { try { $sp.Close() } catch {} }
}

$text = $raw.ToString()
$all = @($text -split "`r?`n")

Say "" "Gray"
Say "[3/3] Summary" "White"
$metro = @($all | Where-Object { $_ -match "metro stop|metro t=" })
$n32   = @($all | Where-Object { $_ -match "N32Audio|ackfail|PCM|pcm write|wav header" })
$stall = @($all | Where-Object { $_ -match "stall|stalled|timeout|超时|背压" })
$reset = @($all | Where-Object { $_ -match "重置|通信失败|重建|rejected|failed|failed=" })
# v46: XiaoZhi playback summary. starve_ms high = decode/network starvation,
# slow frames high = UART write too slow for a 60ms frame.
# v49: PLAY f=.. 是播放中的 5 秒心跳（累计值），长音乐流不会 drain，只有它有输出。
$play  = @($all | Where-Object { $_ -match "playback done" })
$hb    = @($all | Where-Object { $_ -match "PLAY f=" })
Say ("  total serial lines   : {0}" -f $all.Count) "Gray"
Say ("  N32Audio lines       : {0}" -f $n32.Count) "Gray"
Say ("  metro report lines   : {0}" -f $metro.Count) "Gray"
Say ("  playback summary     : {0}" -f $play.Count) "Gray"
Say ("  play heartbeat lines : {0}" -f $hb.Count) "Gray"
Say ("  stall / timeout lines: {0}" -f $stall.Count) "Gray"
Say ("  reset / fail lines   : {0}" -f $reset.Count) "Gray"
foreach ($m in $metro) { Say ("  METRO> " + $m.Trim()) "Cyan" }
foreach ($p in $play)  { Say ("  PLAY>  " + $p.Trim()) "Cyan" }
if ($hb.Count -ge 2) {
    # 心跳是累计值，首尾两条相减就是整个抓包窗口的真实增量。
    function FieldN($line, $key) {
        if ($line -match ("(?:^|\s)" + [regex]::Escape($key) + "=(\d+)")) { return [int]$Matches[1] }
        return -1
    }
    $h0 = $hb[0]; $h1 = $hb[$hb.Count - 1]
    $df  = (FieldN $h1 "f")      - (FieldN $h0 "f")
    $dsl = (FieldN $h1 "slow")   - (FieldN $h0 "slow")
    $dst = (FieldN $h1 "starve") - (FieldN $h0 "starve")
    $ddp = (FieldN $h1 "drop")   - (FieldN $h0 "drop")
    $dgap = (FieldN $h1 "gap")   - (FieldN $h0 "gap")
    $dack = (FieldN $h1 "ack")   - (FieldN $h0 "ack")
    $ddec = (FieldN $h1 "dmax")
    Say ("  HB> frames={0} (≈{1:N1}s 音频) slow={2} starve={3}ms drop={4} gap={5} ack={6} dec_max={7}ms" -f `
        $df, ($df * 0.06), $dsl, $dst, $ddp, $dgap, $dack, $ddec) "Green"
    Say "  HB> 判读：slow 多 = UART 写流慢；starve 大 = 解码/网络供不上；drop>0 = 解码队列溢出丢包；gap>0 = 断流重开" "Gray"
}
if ($hb.Count -gt 0) { foreach ($h in @($hb | Select-Object -Last 6)) { Say ("  HB>    " + $h.Trim()) "DarkCyan" } }
if ($play.Count -gt 0) {
    Say "  legend: slow/max_ms high  = UART 单帧写流慢（写不完 60ms）" "Gray"
    Say "          starve_ms high    = 解码/网络供不上（PC 端看包）" "Gray"
    Say "          ackfail/gaps/resets > 0 = 写流自己丢应答或重开了会话（v48 新增）" "Gray"
    Say "          stalls high      = N32 接收缓冲常满（背压，通常无害）" "Gray"
}
if ($reset.Count -gt 0) {
    foreach ($r in @($reset | Select-Object -First 10)) {
        Say ("  FAIL> " + $r.Trim()) "Yellow"
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path (Get-Location).Path ("ones_audio_diag_" + $stamp + ".txt")
$content = New-Object System.Text.StringBuilder
foreach ($l in $lines) { [void]$content.AppendLine($l) }
[void]$content.AppendLine("")
[void]$content.AppendLine("===== RAW SERIAL LOG =====")
[void]$content.AppendLine($text)
[System.IO.File]::WriteAllText($out, $content.ToString(), [System.Text.Encoding]::UTF8)
Say "" "Gray"
Say "Saved: $out" "Green"
Say "Send this file back." "Green"
Read-Host "Press Enter to exit"
