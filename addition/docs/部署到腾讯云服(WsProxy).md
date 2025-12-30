## 准备

本地构建Docker镜像并推送到镜像仓库。

## 部署

```bash
docker run -d --restart unless-stopped --name new-api \
    --network mynet --hostname new-api \
    --log-opt max-size=2m \
    --env-file /root/sync/docker/new-api/.env \
    -p 49662:3000 \
    -e TZ=Asia/Shanghai \
    -v /root/sync/docker/new-api/data/:/data/ \
registry.cn-chengdu.aliyuncs.com/apq/apq-new-api
# 端口:49662:3000
```

## 更新

```bash
# 删除当前容器和使用的镜像(仅本地)
docker stop new-api && docker rm new-api
docker rmi registry.cn-chengdu.aliyuncs.com/apq/apq-new-api

# 重新使用上面的部署语句启动容器就会自动拉取最新的镜像
```
