# NewApiLogger - API 请求日志服务

一个独立的 WebAPI 服务，用于接收和处理 API 请求日志。

## 项目结构

```
NewApiLogger/
├── src/
│   └── NewApiLogger/          # 主服务代码
│       ├── Controllers/       # API 控制器
│       ├── Models/            # 数据模型
│       ├── Services/          # 业务逻辑
│       ├── Middleware/        # 请求拦截中间件
│       ├── Program.cs         # 入口点
│       └── Dockerfile         # Docker 构建文件
└── traefik-config/            # Traefik 配置示例
    ├── traefik.yml            # Traefik 静态配置
    ├── docker-compose.yml     # Docker Compose 配置
    └── dynamic/               # 动态配置
        ├── routers.yml        # 路由和服务配置
        ├── middlewares.yml    # 中间件配置
        └── tls.yml            # TLS 配置
```

## 架构

支持两种日志输入方式：

```
方式一: Traefik 镜像 (自动拦截)
                    ┌─────────────→ New API (主服务)
                    │                 响应返回给用户
用户请求 → Traefik ─┤
                    │ (mirroring 100%)
                    └─────────────→ NewApiLogger
                                     RequestLoggingMiddleware 自动解析
                                     Source: "traefik-mirror"

方式二: Web API 提交 (手动提交)
外部系统 ──POST /api/logs──→ NewApiLogger
                              LogsController 处理
                              Source: "web-api" (或自定义)
```

**工作原理**:

- **Traefik 镜像**: 请求被镜像到 NewApiLogger，`RequestLoggingMiddleware` 自动拦截并解析，提取 Token、Model、EndpointType 等信息
- **Web API 提交**: 外部系统通过 `POST /api/logs` 提交结构化日志数据
- 两种方式的日志统一存储，可通过 `source` 字段区分来源

## 功能特性

- **双入口支持**: 同时支持 Traefik 镜像自动拦截和 Web API 手动提交
- **自动请求拦截**: 中间件自动拦截 Traefik 镜像的所有请求
- **智能解析**: 自动识别端点类型、提取 Token 和 Model 信息
- **多认证支持**: 支持 OpenAI/Claude/Gemini/Midjourney 等多种认证方式
- **统计分析**: 实时统计 Token 使用、端点调用、来源分布
- **多维查询**: 按 Token、端点类型、来源等条件查询日志
- **API 文档**: 内置 Swagger UI 和 ReDoc 交互式文档
- **API Key 认证**: 可选的 API Key 保护

## 快速开始

### 1. 构建和运行

```bash
cd NewApiLogger/src/NewApiLogger
dotnet restore
dotnet run
```

服务默认监听 `http://localhost:5100`

### 2. 配置

编辑 `src/NewApiLogger/appsettings.json`:

```json
{
  "Urls": "http://localhost:5100",
  "ApiKey": "your-secret-key"
}
```

### 3. 访问 API 文档

- **Swagger UI**: http://localhost:5100/swagger
- **ReDoc**: http://localhost:5100/redoc
- **OpenAPI JSON**: http://localhost:5100/swagger/v1/swagger.json

### 4. Docker 部署

```bash
cd src/NewApiLogger
docker build -t new-api-logger .
docker run -p 5100:5100 -e ApiKey=your-secret-key new-api-logger
```

### 5. 配置 Traefik Mirroring (可选)

在 Traefik 动态配置中添加镜像服务 (`traefik-config/dynamic/routers.yml`):

```yaml
http:
  routers:
    # 默认路由 - 所有请求镜像到 NewApiLogger
    default:
      rule: "PathPrefix(`/`)"
      entryPoints:
        - websecure
      service: new-api-with-mirror
      tls: {}
      priority: 1

  services:
    # 主服务
    new-api:
      loadBalancer:
        servers:
          - url: "http://new-api:3000"

    # 日志服务
    apq-api-logger:
      loadBalancer:
        servers:
          - url: "http://apq-api-logger:5100"

    # 镜像服务配置 - 100% 镜像所有请求
    new-api-with-mirror:
      mirroring:
        service: new-api
        mirrors:
          - name: apq-api-logger
            percent: 100
```

**说明**: NewApiLogger 的 `RequestLoggingMiddleware` 会自动识别和解析所有镜像过来的请求，无需在 Traefik 中配置特定路径。

## API 端点

| 端点 | 方法 | 描述 |
|------|------|------|
| `/api/logs` | POST | 提交单条日志 |
| `/api/logs/batch` | POST | 批量提交日志 |
| `/api/logs` | GET | 获取最近的日志 |
| `/api/logs/by-token/{hash}` | GET | 按 Token 哈希查询日志 |
| `/api/logs/by-source/{source}` | GET | 按来源查询日志 |
| `/api/logs/stats` | GET | 获取统计信息 |
| `/api/logs` | DELETE | 清空所有日志 |
| `/health` | GET | 健康检查 |
| `/swagger` | GET | Swagger UI 文档 |
| `/redoc` | GET | ReDoc 文档 |

### GET `/api/logs` 查询参数

| 参数 | 类型 | 描述 |
|------|------|------|
| `count` | int | 返回的日志数量 (默认: 100, 最大: 10000) |
| `endpoint` | string | 按端点类型过滤 (如: chat, embeddings) |

### GET `/api/logs/by-source/{source}` 示例

```bash
# 获取 Traefik 镜像的日志
GET /api/logs/by-source/traefik-mirror?count=50

# 获取 Web API 提交的日志
GET /api/logs/by-source/web-api?count=50
```

### 认证方式

在请求头中包含 API Key:

```
X-Api-Key: your-secret-key
```

或者

```
Authorization: Bearer your-secret-key
```

## 日志格式

### 请求体 (POST /api/logs)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2024-12-12T10:30:00Z",
  "source": "web-api",
  "request": {
    "method": "POST",
    "path": "/v1/chat/completions",
    "endpointType": "chat",
    "clientIp": "192.168.1.100",
    "userAgent": "Mozilla/5.0...",
    "model": "gpt-4",
    "queryString": "?stream=true",
    "headers": {}
  },
  "auth": {
    "tokenPrefix": "sk-abc1...xyz9",
    "tokenHash": "a1b2c3d4e5f6g7h8"
  },
  "response": {
    "statusCode": 200,
    "durationMs": 2345,
    "sizeBytes": 1234
  }
}
```

### 日志来源 (Source)

| 值 | 说明 |
|------|------|
| `traefik-mirror` | Traefik 镜像自动拦截的请求 |
| `web-api` | 通过 Web API 手动提交的日志 (默认值) |
| 自定义 | 可在提交时指定任意来源标识 |

### 批量请求体 (POST /api/logs/batch)

```json
{
  "logs": [
    { /* ApiRequestLog */ },
    { /* ApiRequestLog */ }
  ]
}
```

### 统计响应 (GET /api/logs/stats)

```json
{
  "totalRequests": 10000,
  "logsInQueue": 5000,
  "tokenStats": [
    {
      "tokenHash": "a1b2c3d4e5f6g7h8",
      "tokenPrefix": "sk-abc1...xyz9",
      "requestCount": 500,
      "lastUsed": "2024-12-12T10:30:00Z"
    }
  ],
  "endpointStats": [
    { "endpoint": "chat", "count": 6000 },
    { "endpoint": "embeddings", "count": 2000 }
  ],
  "sourceStats": [
    { "source": "traefik-mirror", "count": 8000 },
    { "source": "web-api", "count": 2000 }
  ]
}
```

## 支持的端点类型

| 类型 | 描述 |
|------|------|
| `chat` | OpenAI Chat API (/v1/chat/completions) |
| `completions` | OpenAI Completions API (/v1/completions) |
| `embeddings` | Embeddings API (/v1/embeddings) |
| `moderation` | Moderations API (/v1/moderations) |
| `image_generation` | 图像生成 (/v1/images/generations) |
| `image_edit` | 图像编辑 (/v1/images/edits) |
| `tts` | 文字转语音 (/v1/audio/speech) |
| `stt` | 语音转文字 (/v1/audio/transcriptions) |
| `claude_messages` | Claude/Anthropic API (/v1/messages) |
| `responses` | OpenAI Responses API (/v1/responses) |
| `realtime` | OpenAI Realtime WebSocket (/v1/realtime) |
| `rerank` | Rerank API (/v1/rerank) |
| `models` | 模型列表 (/v1/models) |
| `files` | 文件管理 (/v1/files) |
| `assistants` | OpenAI Assistants API (/v1/assistants) |
| `threads` | OpenAI Threads API (/v1/threads) |
| `vector_stores` | 向量存储 (/v1/vector_stores) |
| `batches` | 批量处理 (/v1/batches) |
| `midjourney` | Midjourney API (/mj) |
| `suno` | Suno 音乐 API (/suno) |
| `kling` | 可灵视频 (/kling) |
| `vidu` | Vidu 视频 (/vidu) |
| `jimeng` | 即梦图像 (/jimeng) |
| `sora` | OpenAI Sora (/sora) |
| `other` | 其他非 API 请求 |

## Token 提取

服务会从以下位置提取 API Token:

1. `Authorization: Bearer xxx` 请求头
2. `x-api-key` 请求头 (Anthropic/Claude 风格)
3. `x-goog-api-key` 请求头 (Google/Gemini 风格)
4. `mj-api-secret` 请求头 (Midjourney 风格)
5. URL 查询参数 `?key=xxx`

Token 会被处理为:

- **TokenPrefix**: 脱敏显示 (如 `sk-abc1...xyz9`)
- **TokenHash**: SHA256 哈希值前16位 (用于查询和统计)

## 数据库配置

NewApiLogger 支持多种数据库存储方式，与 new-api 项目保持一致：

### 支持的数据库

| 数据库 | DbType | 说明 |
|--------|--------|------|
| SQLite | `sqlite` | 默认选项，无需额外配置 |
| MySQL | `mysql` | 需要 MySQL >= 5.7.8 |
| PostgreSQL | `postgres` | 需要 PostgreSQL >= 9.6 |
| Redis | - | 可选缓存层 |

### 配置示例

编辑 `appsettings.json`:

#### SQLite (默认)
```json
{
  "Database": {
    "Enabled": true,
    "DbType": "sqlite",
    "ConnectionString": "DataSource=newapi-logger.db"
  }
}
```

#### MySQL
```json
{
  "Database": {
    "Enabled": true,
    "DbType": "mysql",
    "ConnectionString": "Server=localhost;Port=3306;Database=newapi_logger;Uid=root;Pwd=your_password;CharSet=utf8mb4;"
  }
}
```

#### PostgreSQL
```json
{
  "Database": {
    "Enabled": true,
    "DbType": "postgres",
    "ConnectionString": "Host=localhost;Port=5432;Database=newapi_logger;Username=postgres;Password=your_password;"
  }
}
```

#### Redis 缓存 (可选)
```json
{
  "Redis": {
    "Enabled": true,
    "ConnectionString": "localhost:6379,password=your_password",
    "KeyPrefix": "newapi-logger:"
  }
}
```

### 环境变量配置

也可以通过环境变量配置：

```bash
# 数据库
Database__Enabled=true
Database__DbType=mysql
Database__ConnectionString="Server=localhost;Database=newapi_logger;..."

# Redis
Redis__Enabled=true
Redis__ConnectionString="localhost:6379"
```

### Docker 部署示例

```bash
docker run -p 5100:5100 \
  -e Database__Enabled=true \
  -e Database__DbType=sqlite \
  -e Database__ConnectionString="DataSource=/data/newapi-logger.db" \
  -v ./data:/data \
  new-api-logger
```

## 存储限制

### 内存存储模式 (Database.Enabled=false)
- 日志队列最大容量: 10,000 条
- 当队列满时，最旧的日志会被自动移除
- Token 统计最多显示前 50 个
- 数据存储在内存中，重启后清空

### 数据库存储模式 (Database.Enabled=true)
- 无日志数量限制
- 数据持久化存储，重启后保留
- 支持大规模数据查询和统计

## 技术栈

- .NET 8.0
- ASP.NET Core WebAPI
- NSwag (OpenAPI/Swagger)
- SqlSugar (ORM - 支持 SQLite/MySQL/PostgreSQL)
- StackExchange.Redis (Redis 客户端)

## 许可证

MIT License
