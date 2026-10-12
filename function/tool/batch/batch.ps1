<#
.SYNOPSIS
  把当前目录下的 .gd/.tscn/.tres/.gdshader/.godot/.json 文件分批发送给 DeepSeek API，或导出为 txt。
  顺序：代码/场景文件在前，JSON 数据表在后。
.NOTES
  Windows 10/11 自带 PowerShell 5.1 即可运行，无需安装任何东西。
  ⚠ 本文件必须保存为 UTF-8 with BOM，否则 PS 5.1 会把中文读成乱码。
#>

[CmdletBinding()]
param(
    [int]$BatchSize = 49,
    [int]$MaxChars = 60000,
    [string]$Model = "deepseek-chat",
    [string]$ApiKey = "",
    [string]$OutDir = "_batches",
    [string]$SystemPrompt = "你是 Godot 项目代码审查助手，请逐文件分析代码结构、潜在 bug 和可改进点。",
    [switch]$Separate,
    [switch]$Export
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$API_URL = "https://api.deepseek.com/chat/completions"
$EXCLUDE_DIRS = @(".git", ".godot", ".import", "node_modules", "__pycache__", ".vscode", "_batches")
$EXTS = @(".gd", ".tscn", ".tres", ".gdshader", ".godot", ".json")


# ============================================================
#  工具函数
# ============================================================
function Read-TextFile([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { return "" }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes)
    } catch {
        $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
        return [System.Text.Encoding]::GetEncoding($cp).GetString($bytes)
    }
}

function Find-TargetFiles([string]$root) {
    $found = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($sub in [System.IO.Directory]::GetDirectories($dir)) {
                $name = [System.IO.Path]::GetFileName($sub)
                if ($EXCLUDE_DIRS -notcontains $name) { $stack.Push($sub) }
            }
            foreach ($f in [System.IO.Directory]::GetFiles($dir)) {
                $ext = [System.IO.Path]::GetExtension($f).ToLower()
                if ($EXTS -contains $ext) { [void]$found.Add($f) }
            }
        } catch {}
    }

    $arr = $found.ToArray()
    [Array]::Sort($arr)

    # ★ 代码文件在前，JSON 数据表在后（各段内部保持路径顺序）
    $code = New-Object System.Collections.ArrayList
    $data = New-Object System.Collections.ArrayList
    foreach ($f in $arr) {
        if ([System.IO.Path]::GetExtension($f).ToLower() -eq ".json") {
            [void]$data.Add($f)
        } else {
            [void]$code.Add($f)
        }
    }

    $combined = New-Object System.Collections.ArrayList
    foreach ($f in $code) { [void]$combined.Add($f) }
    foreach ($f in $data) { [void]$combined.Add($f) }
    return $combined.ToArray()
}

function New-Batches($files, [int]$maxCount, [int]$maxChars) {
    $batches = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList
    $curChars = 0
    foreach ($f in $files) {
        $size = (New-Object System.IO.FileInfo($f)).Length
        if ($current.Count -gt 0 -and ($current.Count -ge $maxCount -or ($curChars + $size) -gt $maxChars)) {
            [void]$batches.Add($current.ToArray())
            $current.Clear()
            $curChars = 0
        }
        [void]$current.Add($f)
        $curChars += $size
    }
    if ($current.Count -gt 0) { [void]$batches.Add($current.ToArray()) }
    return $batches
}

function Build-Prompt($batch, [string]$root) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($path in $batch) {
        $rel = $path.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        [void]$sb.AppendLine("[file name]: $rel")
        [void]$sb.AppendLine("[file content begin]")
        [void]$sb.AppendLine((Read-TextFile $path))
        [void]$sb.AppendLine("[file content end]")
        [void]$sb.AppendLine("")
    }
    return $sb.ToString()
}

function Invoke-DeepSeek($messages, [string]$key, [string]$model, [int]$retries = 3) {
    $payload = @{
        model    = $model
        messages = @($messages)
        stream   = $false
    }
    $json = $payload | ConvertTo-Json -Depth 100 -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($json)

    $headers = @{
        "Authorization" = "Bearer $key"
        "Content-Type"  = "application/json; charset=utf-8"
    }

    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri $API_URL -Method Post -Headers $headers `
                                      -Body $body -TimeoutSec 600
            return $resp.choices[0].message.content
        } catch {
            Write-Host "  请求失败：$($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -lt ($retries - 1)) { Start-Sleep -Seconds (5 * ($i + 1)) }
        }
    }
    throw "API 调用失败（已重试 $retries 次）"
}

function Show-Menu {
    Write-Host ""
    Write-Host "==== DeepSeek 分批发送工具 ====" -ForegroundColor Cyan
    Write-Host "  1. 导出为 txt（不发 API，最安全）"
    Write-Host "  2. 发送到 DeepSeek API（每批独立对话，省 token）"
    Write-Host "  3. 发送到 DeepSeek API（累加历史，更有上下文但更贵）"
    Write-Host "  0. 退出"
    Write-Host ""
    $choice = Read-Host "选择"
    switch ($choice) {
        "1" { return "export" }
        "2" { return "api-separate" }
        "3" { return "api-full" }
        default { return "quit" }
    }
}


# ============================================================
#  主流程
# ============================================================
$root = (Get-Location).Path
Write-Host "工作目录：$root" -ForegroundColor DarkGray

$files = Find-TargetFiles $root
if ($files.Count -eq 0) {
    Write-Host "未找到目标文件" -ForegroundColor Red
    return
}
Write-Host "找到 $($files.Count) 个目标文件" -ForegroundColor Green

$batches = New-Batches $files $BatchSize $MaxChars
Write-Host "分成 $($batches.Count) 批（每批 ≤ $BatchSize 个文件，≤ $MaxChars 字节）" -ForegroundColor Green
Write-Host ""

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$mode = ""
if ($PSBoundParameters.Count -eq 0) {
    $mode = Show-Menu
    if ($mode -eq "quit") { return }
} elseif ($Export) {
    $mode = "export"
} elseif ($Separate) {
    $mode = "api-separate"
} else {
    $mode = "api-full"
}

# ---- 导出模式 ----
if ($mode -eq "export") {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    for ($i = 0; $i -lt $batches.Count; $i++) {
        $b = $batches[$i]
        $txt = Build-Prompt $b $root
        $fp = Join-Path $OutDir ("batch_{0:D2}.txt" -f ($i + 1))
        [System.IO.File]::WriteAllText($fp, $txt, $utf8NoBom)
        Write-Host ("  写出 {0}  （{1} 文件，{2} 字符）" -f $fp, $b.Count, $txt.Length)
    }
    Write-Host ""
    Write-Host "完成。把 $OutDir\batch_*.txt 依次贴到 DeepSeek 网页对话即可。" -ForegroundColor Green
    return
}

# ---- API 模式 ----
if (-not $ApiKey) { $ApiKey = $env:DEEPSEEK_API_KEY }
if (-not $ApiKey) {
    Write-Host "未提供 API Key。" -ForegroundColor Yellow
    $sec = Read-Host "请输入 DeepSeek API Key（输入时不显示）" -AsSecureString
    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
if (-not $ApiKey) {
    Write-Host "API Key 为空，退出。" -ForegroundColor Red
    return
}

$messages = @()
$messages += @{ role = "system"; content = $SystemPrompt }

for ($i = 0; $i -lt $batches.Count; $i++) {
    $b = $batches[$i]
    $prompt = Build-Prompt $b $root
    Write-Host ("=== 第 {0}/{1} 批  （{2} 文件，{3} 字符）===" -f ($i + 1), $batches.Count, $b.Count, $prompt.Length) -ForegroundColor Cyan

    $sendMessages = if ($mode -eq "api-separate") {
        @($messages[0]) + @(@{ role = "user"; content = $prompt })
    } else {
        @($messages) + @(@{ role = "user"; content = $prompt })
    }

    try {
        $reply = Invoke-DeepSeek $sendMessages $ApiKey $Model
    } catch {
        Write-Host "  ✗ $_" -ForegroundColor Red
        Write-Host "  已完成的批次保存在 $OutDir，可手动续跑。" -ForegroundColor Yellow
        break
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $rp = Join-Path $OutDir ("reply_{0:D2}.md" -f ($i + 1))
    $header = "# 第 $($i+1) 批（$($b.Count) 文件）`r`n`r`n"
    foreach ($x in $b) {
        $rel = $x.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        $header += "- $rel`r`n"
    }
    $header += "`r`n---`r`n`r`n"
    [System.IO.File]::WriteAllText($rp, $header + $reply, $utf8NoBom)
    Write-Host "  → $rp" -ForegroundColor Green
    Write-Host ""

    if ($mode -eq "api-full") {
        $messages += @{ role = "user"; content = $prompt }
        $messages += @{ role = "assistant"; content = $reply }
    }

    Start-Sleep -Milliseconds 800
}

Write-Host "全部完成。回复文件在：$OutDir" -ForegroundColor Green