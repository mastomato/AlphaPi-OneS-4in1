# AlphaPi OneS 启动故障诊断（零依赖，Windows 自带 PowerShell 即可运行）
#
# 只读串口，不写 flash，不会让设备变得更糟。
# 用法：双击 run-boot-diag.cmd，或
#       powershell -ExecutionPolicy Bypass -File ones_boot_diag.ps1
#
# 结果保存为 ones_diag_<时间>.txt，把它整个发回来。

param(
    [string]$Port = "",
    [int]$Seconds = 20
)

$ErrorActionPreference = "Stop"
$outLines = New-Object System.Collections.ArrayList

function Say($msg, $color = "Gray") {
    Write-Host $msg -ForegroundColor $color
    [void]$outLines.Add($msg)
}

Say "==============================================================" "Cyan"
Say "  AlphaPi OneS 启动故障诊断" "Cyan"
Say "==============================================================" "Cyan"

# ---- 1. 列出串口 ----
$names = [System.IO.Ports.SerialPort]::GetPortNames()
Say ""
Say "[1/3] 电脑上的串口：" "White"
if (-not $names -or $names.Count -eq 0) {
    Say "      一个都没有。请换一根能传数据的 USB 线，重新插好再试。" "Red"
    Read-Host "按回车退出"
    exit 1
}
foreach ($n in $names) { Say "      $n" }

if ([string]::IsNullOrWhiteSpace($Port)) {
    if ($names.Count -eq 1) {
        $Port = $names[0]
    } else {
        Say ""
        Say "      有多个串口，请看你设备插上/拔下时多出来的是哪个。" "Yellow"
        $Port = Read-Host "      输入串口名（例如 COM20）"
    }
}
Say "      使用：$Port" "Green"

# ---- 2. 抓日志 ----
Say ""
Say "[2/3] 监听 $Port @ 115200，持续 $Seconds 秒。" "White"
Say "      设备会自动重启，请让它一直通着电，别按键。" "Gray"

$text = ""
$deadline = (Get-Date).AddSeconds($Seconds)
$sp = $null
try {
    $sp = New-Object System.IO.Ports.SerialPort($Port, 115200, "None", 8, "One")
    $sp.ReadTimeout = 500
    $sp.DtrEnable = $true
    $sp.RtsEnable = $true
    $sp.Open()
    $sp.DiscardInBuffer()
    $sb = New-Object System.Text.StringBuilder
    $lastData = Get-Date
    while ((Get-Date) -lt $deadline) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -and $chunk.Length -gt 0) {
                [void]$sb.Append($chunk)
                $lastData = Get-Date
            } else {
                Start-Sleep -Milliseconds 100
            }
        } catch [System.TimeoutException] {
            Start-Sleep -Milliseconds 100
        } catch {
            # 设备重启时端口可能短暂异常，继续等
            Start-Sleep -Milliseconds 200
        }
    }
    $text = $sb.ToString()
} catch {
    Say "      !! 打不开串口：$($_.Exception.Message)" "Red"
    Say "      常见原因：串口被别的软件占着（Arduino IDE、串口助手要先关掉）。" "Yellow"
} finally {
    if ($sp -and $sp.IsOpen) { $sp.Close() }
    if ($sp) { $sp.Dispose() }
}

Say "      收到 $($text.Length) 个字符" "Green"

# ---- 3. 结论提示 ----
$hints = New-Object System.Collections.ArrayList
$low = $text.ToLower()
if ($text.Trim().Length -eq 0) {
    [void]$hints.Add("20 秒内一个字都没打印：芯片很可能在 bootloader 阶段就复位了（flash 读不出 / app 镜像校验失败），或者串口没接通。")
}
if ($low -match "invalid header" -or $low -match "0xffffffff") {
    [void]$hints.Add("出现 invalid header / 0xffffffff：app 镜像没写进去，或被擦掉了。")
}
if ($low -match "failed to init external ram" -or ($low -match "psram" -and $low -match "fail")) {
    [void]$hints.Add("PSRAM 初始化失败：这颗板子的 PSRAM 可能没焊、型号不兼容或供电不对。")
}
if ($low -match "brownout") {
    [void]$hints.Add("出现过 brownout：供电不足。换线、换电源，别用电脑前置 USB 口。")
}
if ($low -match "guru meditation" -or $low -match "panic") {
    [void]$hints.Add("出现过 panic：程序崩溃，日志里第一处 Backtrace 是关键。")
}
$rstCount = ([regex]::Matches($low, "rst:0x")).Count
if ($rstCount -ge 3) {
    [void]$hints.Add("日志里出现 $rstCount 次启动头，确认是在反复重启。")
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ones_diag_$stamp.txt"
$body = @()
$body += "AlphaPi OneS boot diagnosis"
$body += "time : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$body += "port : $Port"
$body += "seconds : $Seconds"
$body += ""
$body += "===== serial ====="
$body += $text
$body += ""
$body += "===== hints ====="
foreach ($h in $hints) { $body += "- $h" }

try {
    [System.IO.File]::WriteAllLines($outFile, $body, (New-Object System.Text.UTF8Encoding($false)))
    Say ""
    Say "--------------------------------------------------------------" "Cyan"
    Say "结果已保存： $outFile" "Green"
    Say "把这个文件整个发回来。" "White"
} catch {
    Say "写文件失败：$($_.Exception.Message)" "Red"
}

Say ""
if ($hints.Count -gt 0) {
    Say "初步提示：" "Yellow"
    foreach ($h in $hints) { Say "  - $h" "Yellow" }
} else {
    Say "没有命中已知故障特征，但日志本身仍然有用，请一并发回。" "Gray"
}
Say ""
Read-Host "按回车关闭窗口"
