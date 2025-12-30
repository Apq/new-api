# Docker 镜像构建指南（国内网络）

本文档介绍如何在国内 Linux 环境中使用 `Dockerfile.cn` 构建和推送 Docker 镜像。

## 前提条件

- Linux 服务器（推荐 Ubuntu 20.04+）
- Docker 已安装（版本 20.10+）
- 已登录目标镜像仓库

## 〇、SSH 远程构建准备（重要）

如果你通过 SSH 远程连接 Linux 服务器进行构建，**强烈建议使用 tmux 或 screen 会话**，防止因网络波动、SSH 超时等原因导致构建中断。

### 安装 tmux

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y tmux

# CentOS/RHEL
sudo yum install -y tmux

# Alpine
apk add tmux
```

### 使用 tmux 进行构建

```bash
# 1. 创建新会话（命名为 dbx）
tmux new -s dbx

# 2. 在 tmux 会话中执行构建命令
cd /path/to/apq-new-api
docker build -f Dockerfile.cn -t new-api:latest .

# 3. 如需临时离开（会话保持运行）
# 按 Ctrl+B，然后按 D 键分离会话

# 4. 重新连接会话（SSH 断开后重连）
tmux attach -t dbx

# 5. 构建完成后关闭会话
exit
```

### tmux 常用快捷键

| 操作 | 快捷键 |
|-----|-------|
| 分离会话（后台运行） | `Ctrl+B` 然后 `D` |
| 列出所有会话 | `tmux ls` |
| 连接指定会话 | `tmux attach -t 会话名` |
| 关闭当前会话 | `exit` 或 `Ctrl+D` |
| 滚动查看历史输出 | `Ctrl+B` 然后 `[`，用方向键滚动，按 `Q` 退出 |

### 为什么需要 tmux？

Docker 镜像构建通常需要 **10-30 分钟**（取决于网络和服务器性能），期间如果：
- SSH 连接超时断开
- 本地网络波动
- 不小心关闭终端窗口

都会导致构建进程被终止，前功尽弃。使用 tmux 可以让构建在服务器后台持续运行，即使 SSH 断开也不受影响。

## 一、构建镜像

### 基本构建

```bash
# 进入项目根目录
cd apq-new-api

# 使用国内优化版 Dockerfile 构建
docker build -f Dockerfile.cn -t new-api:latest .
```

### 指定版本标签

```bash
# 使用 VERSION 文件中的版本号
docker build -f Dockerfile.cn -t new-api:$(cat VERSION) .

# 或手动指定版本
docker build -f Dockerfile.cn -t new-api:v1.0.0 .
```

### 多架构构建

如需构建多架构镜像（如同时支持 amd64 和 arm64），需要先启用 buildx：

```bash
# 创建并使用 buildx 构建器
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap

# 构建多架构镜像并推送
docker buildx build -f Dockerfile.cn \
  --platform linux/amd64,linux/arm64 \
  -t registry.cn-chengdu.aliyuncs.com/apq/apq-new-api \
  --cache-from type=local,src=$HOME/.buildx-cache \
  --cache-to type=local,dest=$HOME/.buildx-cache,mode=max \
  --push .
```

## 二、推送镜像要先登录docker hub或其它用于存放镜像的站点

### 推送到 Docker Hub

```bash
# 登录 Docker Hub
docker login

# 打标签
docker tag new-api:latest your-username/new-api:latest

# 推送
docker push your-username/new-api:latest
```

### 推送到阿里云容器镜像服务

```bash
# 登录阿里云镜像仓库
docker login --username=your-username registry.cn-hangzhou.aliyuncs.com

# 打标签
docker tag new-api:latest registry.cn-hangzhou.aliyuncs.com/your-namespace/new-api:latest

# 推送
docker push registry.cn-hangzhou.aliyuncs.com/your-namespace/new-api:latest
```

### 推送到华为云容器镜像服务

```bash
# 登录华为云镜像仓库
docker login -u your-username swr.cn-north-4.myhuaweicloud.com

# 打标签
docker tag new-api:latest swr.cn-north-4.myhuaweicloud.com/your-org/new-api:latest

# 推送
docker push swr.cn-north-4.myhuaweicloud.com/your-org/new-api:latest
```

### 推送到腾讯云容器镜像服务

```bash
# 登录腾讯云镜像仓库
docker login ccr.ccs.tencentyun.com --username=your-username

# 打标签
docker tag new-api:latest ccr.ccs.tencentyun.com/your-namespace/new-api:latest

# 推送
docker push ccr.ccs.tencentyun.com/your-namespace/new-api:latest
```

## 三、一键构建并推送脚本

创建 `build-and-push.sh` 脚本：

```bash
#!/bin/bash

# 配置
REGISTRY="registry.cn-hangzhou.aliyuncs.com"  # 修改为你的镜像仓库
NAMESPACE="your-namespace"                      # 修改为你的命名空间
IMAGE_NAME="new-api"
VERSION=$(cat VERSION)

# 完整镜像名
FULL_IMAGE="${REGISTRY}/${NAMESPACE}/${IMAGE_NAME}"

echo "构建镜像: ${FULL_IMAGE}:${VERSION}"

# 构建
docker build -f Dockerfile.cn -t ${FULL_IMAGE}:${VERSION} -t ${FULL_IMAGE}:latest .

if [ $? -eq 0 ]; then
    echo "构建成功，开始推送..."

    # 推送
    docker push ${FULL_IMAGE}:${VERSION}
    docker push ${FULL_IMAGE}:latest

    echo "推送完成！"
    echo "镜像地址: ${FULL_IMAGE}:${VERSION}"
else
    echo "构建失败！"
    exit 1
fi
```

使用方法：

```bash
chmod +x build-and-push.sh
./build-and-push.sh
```

## 四、常见问题

### 1. 构建时下载依赖慢

`Dockerfile.cn` 已配置国内镜像源：

- npm: `registry.npmmirror.com`
- Go: `goproxy.cn`
- 基础镜像: 华为云镜像

如仍然较慢，检查服务器网络或尝试更换镜像源。

### 2. 构建内存不足

前端构建需要较多内存，如遇到 OOM：

```bash
# 增加 Docker 构建内存限制
docker build -f Dockerfile.cn --memory=4g -t new-api:latest .
```

或修改服务器 swap：

```bash
# 添加 4G swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 3. 多架构构建失败

确保已正确配置 buildx 和 QEMU：

```bash
# 安装 QEMU 模拟器
docker run --privileged --rm tonistiigi/binfmt --install all

# 重新创建 buildx 构建器
docker buildx rm mybuilder
docker buildx create --name mybuilder --use
```

### 4. 推送权限被拒绝

```bash
# 确认已登录
docker login your-registry

# 检查镜像标签是否正确
docker images | grep new-api
```

## 五、Dockerfile.cn 说明

`Dockerfile.cn` 采用多阶段构建：

| 阶段       | 基础镜像               | 作用   |
| -------- | ------------------ | ---- |
| builder  | node:20-alpine     | 构建前端 |
| builder2 | golang:1.25-alpine | 构建后端 |
| 最终镜像     | alpine:3.19        | 运行环境 |

特点：

- 使用国内镜像源加速下载
- 多阶段构建减小最终镜像体积
- 支持多架构构建（amd64/arm64）
- 最终镜像仅包含编译后的二进制文件
