# Windows SSH 密钥生成工具

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows SSH 密钥生成工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$keyDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $keyDir)) {
    New-Item -ItemType Directory -Path $keyDir | Out-Null
    Write-Host "已创建 .ssh 目录" -ForegroundColor Green
}

Write-Host "密钥保存位置: $keyDir"
Write-Host ""
Write-Host "选择密钥类型:"
Write-Host "  1. ed25519 [推荐]"
Write-Host "  2. rsa [兼容旧系统]"
Write-Host ""

$choice = Read-Host "输入 1 或 2 (默认 1)"
if ($choice -eq "2") {
    $keyType = "rsa"
    $keyName = "id_rsa"
    $bits = 4096
} else {
    $keyType = "ed25519"
    $keyName = "id_ed25519"
    $bits = 0
}

$customName = Read-Host "自定义文件名 (回车使用默认)"
if ($customName) { $keyName = $customName }

$keyPath = Join-Path $keyDir $keyName

Write-Host ""
Write-Host "将生成 $keyType 密钥"
Write-Host "路径: $keyPath"

if (Test-Path $keyPath) {
    Write-Host "警告: 密钥已存在!" -ForegroundColor Yellow
    $ow = Read-Host "覆盖? (y/N)"
    if ($ow -ne "y") {
        Write-Host "已取消" -ForegroundColor Red
        Read-Host "按回车退出"
        exit
    }
}

$comment = Read-Host "输入邮箱或注释 (可选)"

Write-Host ""
Write-Host "正在生成..." -ForegroundColor Yellow

$sshArgs = @("-t", $keyType, "-f", $keyPath)
if ($bits -gt 0) { $sshArgs += @("-b", $bits) }
if ($comment) { $sshArgs += @("-C", $comment) }

& ssh-keygen @sshArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  密钥生成成功!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "私钥: $keyPath"
    Write-Host "公钥: $keyPath.pub"
    Write-Host ""
    Write-Host "--- 公钥内容 ---" -ForegroundColor Cyan
    Get-Content "$keyPath.pub"
    Write-Host "----------------" -ForegroundColor Cyan
    Write-Host ""

    # 询问是否部署到远程服务器
    $deploy = Read-Host "是否部署到远程服务器? (y/N)"
    if ($deploy -eq "y" -or $deploy -eq "Y") {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        & "$scriptDir\deploy-ssh-key.ps1"
    } else {
        Write-Host ""
        Write-Host "稍后可运行 deploy-ssh-key.bat 部署公钥到远程服务器" -ForegroundColor Yellow
    }
} else {
    Write-Host "生成失败!" -ForegroundColor Red
}

Write-Host ""
Read-Host "按回车退出"
