# APQ-NEW-API 服务器更新脚本
# 功能：删除旧容器和镜像，使用新镜像启动容器

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# 配置区
# ============================================================

# 远程服务器配置(群晖)
$remoteUser = "root"
$remoteHost = "ds"
$remotePort = "22"

# Docker 配置
$imageName = "registry.cn-chengdu.aliyuncs.com/apq/apq-new-api"
$containerName = "apq-new-api"

# ============================================================
# 主程序
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  APQ-NEW-API 服务器更新脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Docker 镜像标签：提示用户输入
$imageTag = Read-Host "请输入新镜像标签 (留空则使用 latest)"

if ($imageTag -ne "") {
    $fullImageName = "${imageName}:${imageTag}"
    Write-Host "镜像标签: $imageTag" -ForegroundColor Yellow
} else {
    $fullImageName = $imageName
    Write-Host "镜像标签: latest (默认)" -ForegroundColor DarkGray
}
Write-Host ""

# 支持命令行参数覆盖默认配置
if ($args.Count -ge 1) { $remoteUser = $args[0] }
if ($args.Count -ge 2) { $remoteHost = $args[1] }
if ($args.Count -ge 3) { $remotePort = $args[2] }

Write-Host "连接到: $remoteUser@$remoteHost`:$remotePort" -ForegroundColor Yellow
Write-Host ""
Write-Host "将执行以下操作:" -ForegroundColor Yellow
Write-Host "  1. 拉取新镜像: $fullImageName" -ForegroundColor White
Write-Host "  2. 停止并删除容器: $containerName" -ForegroundColor White
Write-Host "  3. 删除旧镜像: $imageName (不含新拉取的标签)" -ForegroundColor White
Write-Host "  4. 启动新容器: $fullImageName" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "确认执行? (Y/n)"
if ($confirm -eq "n" -or $confirm -eq "N") {
    Write-Host "已取消操作" -ForegroundColor Yellow
    Read-Host "按回车退出"
    exit
}

Write-Host ""

# 确定实际使用的标签（用于删除旧镜像时排除）
if ($imageTag -eq "") {
    $actualTag = "latest"
} else {
    $actualTag = $imageTag
}

# ============================================================
# 构建远程执行的 Shell 脚本
# ============================================================

# 生成远程脚本内容（写入临时文件执行，避免引号嵌套问题）
$scriptContent = @"
#!/bin/bash

# 群晖 Docker 路径
DOCKER=/usr/local/bin/docker

echo "[1/4] Pull new image..."
`$DOCKER pull $fullImageName

echo "[2/4] Stop and remove container..."
`$DOCKER stop $containerName
`$DOCKER rm $containerName

echo "[3/4] Remove old images..."
`$DOCKER images --format '{{.Repository}}:{{.Tag}}' \
    | grep '$imageName' \
    | grep -v ':$actualTag$' \
    | xargs -r `$DOCKER rmi

echo "[4/4] Start new container..."
`$DOCKER run -d \
    --restart unless-stopped \
    --name $containerName \
    --network mynet \
    --hostname $containerName \
    --log-opt max-size=2m \
    --env-file /volume2/docker/apq-new-api/.env \
    -p 49662:3000 \
    -e TZ=Asia/Shanghai \
    -v /volume2/docker/apq-new-api/data/:/data/ \
    $fullImageName

echo "[Done] Container status:"
`$DOCKER ps | grep $containerName
"@

# 将脚本内容转为 base64，避免特殊字符问题
$scriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))

# 远程命令：解码并执行脚本
$remoteCmd = "echo $scriptBase64 | base64 -d > /tmp/upgrade_apq.sh && bash /tmp/upgrade_apq.sh"

# ============================================================
# 执行远程命令
# ============================================================

& ssh -p $remotePort "$remoteUser@$remoteHost" $remoteCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  更新完成!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "更新失败，请检查错误信息" -ForegroundColor Red
}

Write-Host ""
Read-Host "按回车退出"
