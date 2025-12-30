```bash
docker run -d --restart unless-stopped --name traefik \
    --network mynet --hostname traefik \
    --log-opt max-size=2m \
    -p 80:80 -p 443:443 -p 443:443/udp \
    -v /root/sync/cert/:/cert/ \
    -v /root/sync/docker/traefik/config/traefik.yml:/etc/traefik/traefik.yml \
    -v /root/sync/docker/traefik/config/dynamic/:/etc/traefik/dynamic/ \
    -v /root/traefik/log/:/var/log/traefik/ \
    -v /var/run/docker.sock:/var/run/docker.sock \
traefik
```

## traefik日志轮转

```bash
# 每5分钟检测一次(10M 大小、保留 100 份)
docker run -d --restart unless-stopped --name traefik-logrotate \
    --network mynet --hostname traefik-logrotate \
    --log-opt max-size=2m \
    -v /root/traefik/log/:/logs/traefik/ \
    -e LOGROTATE_COPIES=100 \
    -e LOGROTATE_SIZE="10M" \
    -e LOGROTATE_CRONSCHEDULE="*/5 * * * *" \
    -e LOGS_DIRECTORIES="/logs/traefik" \
blacklabelops/logrotate
```
