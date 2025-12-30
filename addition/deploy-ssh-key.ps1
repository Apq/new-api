# SSH 公钥部署工具 - 将公钥部署到远程 Linux 服务器

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SSH 公钥部署工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$keyDir = "$env:USERPROFILE\.ssh"

# 列出可用的公钥
$pubKeys = Get-ChildItem -Path $keyDir -Filter "*.pub" -ErrorAction SilentlyContinue
if (-not $pubKeys) {
    Write-Host "错误: 未找到公钥文件!" -ForegroundColor Red
    Write-Host "请先运行 generate-ssh-key.bat 生成密钥"
    Write-Host ""
    Read-Host "按回车退出"
    exit
}

Write-Host "可用的公钥:"
$i = 1
foreach ($key in $pubKeys) {
    Write-Host "  $i. $($key.Name)"
    $i++
}
Write-Host ""

$keyChoice = Read-Host "选择公钥 (默认 1)"
if (-not $keyChoice) { $keyChoice = "1" }
$selectedKey = $pubKeys[[int]$keyChoice - 1]
$keyPath = $selectedKey.FullName

Write-Host ""
Write-Host "已选择: $keyPath" -ForegroundColor Green
Write-Host ""

# 输入服务器信息
$remoteHost = Read-Host "输入服务器地址 (如 192.168.1.100)"
if (-not $remoteHost) {
    Write-Host "错误: 服务器地址不能为空!" -ForegroundColor Red
    Read-Host "按回车退出"
    exit
}

$remoteUser = Read-Host "输入用户名 (默认 root)"
if (-not $remoteUser) { $remoteUser = "root" }

$remotePort = Read-Host "输入 SSH 端口 (默认 22)"
if (-not $remotePort) { $remotePort = "22" }

Write-Host ""
Write-Host "目标: $remoteUser@$remoteHost`:$remotePort" -ForegroundColor Yellow
Write-Host ""

# 读取公钥内容
$pubKeyContent = Get-Content $keyPath -Raw

# 构建远程命令
$remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'OK'"

Write-Host "正在部署公钥..." -ForegroundColor Yellow
Write-Host "(首次连接需要输入密码)"
Write-Host ""

# 执行部署
$result = & ssh -p $remotePort -o StrictHostKeyChecking=accept-new "$remoteUser@$remoteHost" $remoteCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  公钥部署成功!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "现在可以免密登录:"
    Write-Host "  ssh -p $remotePort $remoteUser@$remoteHost" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "部署失败!" -ForegroundColor Red
    Write-Host "请检查服务器地址、用户名和密码是否正确"
}

Write-Host ""
Read-Host "按回车退出"
