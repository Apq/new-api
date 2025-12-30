# AI请求转发详解

## 一、概述

本系统是一个功能完善的 AI API 网关/代理，支持多种 AI 服务提供商，实现了统一的请求转发机制：

| 功能 | 说明 |
|------|------|
| 请求转发 | 将客户端请求转发到上游 AI 服务 |
| 负载均衡 | 基于优先级和权重的渠道选择 |
| 流式处理 | SSE 流式响应的实时转发 |
| 连接保活 | Ping 机制保持长连接不中断 |
| 错误重试 | 智能重试策略，支持渠道切换和等待重试 |

## 二、核心文件

| 文件路径 | 功能描述 |
|----------|----------|
| router/relay-router.go | 路由定义 |
| controller/relay.go | 主控制器 |
| middleware/distributor.go | 渠道分发中间件 |
| service/channel_select.go | 渠道选择服务 |
| model/channel_cache.go | 渠道缓存 |
| model/channel_concurrent.go | 渠道并发计数 |
| model/channel_rate_limit.go | 渠道限流状态 |
| common/channel_retry.go | 重试决策逻辑 |
| common/constants.go | 重试配置常量 |
| common/channel_error_replace.go | 渠道错误替换逻辑 |
| relay/channel/adapter.go | 适配器接口 |
| relay/channel/api_request.go | API 请求执行 |
| relay/helper/stream_scanner.go | 流式处理 |
| relay/helper/common.go | 通用辅助函数 |
| service/http_client.go | HTTP 客户端 |

---

## 三、请求入口和路由

### 3.1 路由定义

**文件位置**: router/relay-router.go

主要 API 路由端点：

| 端点 | 说明 |
|------|------|
| /v1/chat/completions | OpenAI 格式聊天补全 |
| /v1/messages | Claude 格式消息 |
| /v1/completions | 文本补全 |
| /v1/responses | OpenAI Responses API |
| /v1/embeddings | 向量嵌入 |
| /v1/images/generations | 图像生成 |
| /v1/images/edits | 图像编辑 |
| /v1/audio/speech | 语音合成 |
| /v1/audio/transcriptions | 语音转文字 |
| /v1/audio/translations | 语音翻译 |
| /v1/rerank | 重排序 API |
| /v1/moderations | 内容审核 |
| /v1/realtime | WebSocket 实时 API |
| /v1beta/models/* | Gemini API |
| /v1/models/* | Gemini API（兼容路径） |
| /mj/* | Midjourney API |
| /suno/* | Suno 音乐生成 API |
| /v1/videos | 视频生成 API |
| /pg/chat/completions | Playground 聊天 |

### 3.2 中间件链

请求经过以下中间件链处理：

请求 -> CORS -> Decompress -> Stats -> TokenAuth -> RateLimit -> Distribute -> Controller

| 中间件 | 功能 |
|--------|------|
| CORS() | 跨域处理 |
| DecompressRequestMiddleware() | 请求解压 |
| StatsMiddleware() | 统计中间件 |
| TokenAuth() | Token 认证 |
| ModelRequestRateLimit() | 模型请求速率限制 |
| Distribute() | 渠道分发 |

---

## 四、渠道分发中间件

### 4.1 功能说明

**文件位置**: middleware/distributor.go

渠道分发中间件负责为请求选择合适的上游渠道。

### 4.2 分发流程

1. 检查是否指定特定渠道 -> 是则使用指定渠道
2. 检查令牌模型限制
3. 获取用户分组
4. 调用 CacheGetRandomSatisfiedChannel 选择渠道
5. 设置渠道上下文
6. 继续处理请求

### 4.3 模型请求解析

系统根据请求路径和内容自动解析模型名称：

| 请求类型 | 模型获取方式 |
|----------|--------------|
| 聊天补全 | 从请求体 model 字段获取 |
| 图像生成 | 默认 dall-e，可指定 |
| 语音合成 | 默认 tts-1，可指定 |
| 语音转文字 | 默认 whisper-1，可指定 |
| Gemini API | 从 URL 路径提取 |
| WebSocket | 从 Query 参数获取 |

---

## 五、渠道选择与负载均衡

### 5.1 渠道选择算法

**文件位置**: model/channel_cache.go, service/channel_select.go

系统采用**优先级 + 权重**的负载均衡算法：

1. 获取该分组下支持该模型的所有渠道
2. 按优先级分组（数值越大优先级越高）
3. 根据 retry 次数选择对应优先级
4. 在同优先级渠道中按权重随机选择

### 5.2 权重选择算法

计算总权重 -> 生成随机值 -> 按权重选择渠道

### 5.3 自动分组模式

当 TokenGroup 为 auto 时，系统会遍历所有可用分组寻找可用渠道。

### 5.4 跨分组重试

启用跨分组重试时，每个分组会用完所有优先级后才切换到下一个分组：

| 重试次数 | 分组 | 优先级 |
|----------|------|--------|
| Retry=0 | GroupA | priority0 |
| Retry=1 | GroupA | priority1 |
| Retry=2 | GroupB | priority0 |
| Retry=3 | GroupB | priority1 |

### 5.5 渠道缓存机制

系统使用内存缓存提高渠道选择效率：

| 缓存结构 | 说明 |
|---------|------|
| group2model2channels | 分组 -> 模型 -> 渠道列表映射 |
| channelsIDM | 渠道 ID -> 渠道对象映射 |
| channelSyncLock | 渠道同步读写锁 |
| channelConcurrentMap | 渠道 ID -> 并发计数映射 |

### 5.6 渠道排除机制

**文件位置**: service/channel_select.go, model/channel_cache.go

为避免在重试过程中重复选择同一渠道，系统实现了渠道排除机制：

**核心数据结构**：

```go
type RetryParam struct {
    // ... 其他字段
    ExcludeChannelIds []int // 排除的渠道ID列表（已尝试过的渠道）
}
```

**工作流程**：

1. 每次选择渠道后，将该渠道 ID 添加到排除列表
2. 下次选择渠道时，跳过排除列表中的渠道
3. 当进入等待重试模式时，清空排除列表（允许重新尝试之前的渠道）

**排除过滤逻辑**：

在 `GetRandomSatisfiedChannel` 函数中，渠道选择时会跳过：
- 已在排除列表中的渠道
- 处于限流状态的渠道
- 并发连接数已满的渠道

**示例**：

假设有 3 个可用渠道（ID: 1, 2, 3）：

| 重试次数 | 排除列表 | 可选渠道 | 选中渠道 |
|----------|----------|----------|----------|
| 0 | [] | [1, 2, 3] | 1 |
| 1 | [1] | [2, 3] | 2 |
| 2 | [1, 2] | [3] | 3 |
| 3 | [1, 2, 3] | [] | 无可用渠道，进入等待重试 |
| 4（等待后） | [] | [1, 2, 3] | 1（重新开始） |

### 5.7 渠道并发限制

**文件位置**: model/channel_concurrent.go, controller/relay.go

系统实现了渠道级别的并发连接数限制，防止单个渠道被过多请求压垮。

**核心功能**：

| 函数 | 说明 |
|------|------|
| IncrChannelConcurrent(channelId) | 请求开始时增加并发计数 |
| DecrChannelConcurrent(channelId) | 请求结束时减少并发计数 |
| IsChannelConcurrentFull(channelId) | 检查渠道并发是否已满 |
| GetChannelConcurrent(channelId) | 获取当前并发数 |
| GetChannelMaxConcurrent(channelId) | 获取最大并发限制 |

**并发限制优先级**：

渠道配置 `MaxConnsPerHost` > 全局配置 `RelayMaxConnsPerHost` > 0（不限制）

**工作流程**：

```
请求到达
    ↓
选择渠道 ──→ 检查并发是否已满 ──→ 是 ──→ 跳过，选下一个渠道
    ↓                              ↓
    否                          无可用渠道
    ↓                              ↓
增加并发计数                    返回错误/等待重试
    ↓
执行请求
    ↓
减少并发计数（请求完成后）
```

**配置参数**：

| 参数 | 说明 | 默认值 | 配置位置 |
|------|------|--------|----------|
| RelayMaxConnsPerHost | 全局每渠道最大并发连接数 | 0（不限制） | 管理后台 - 运营设置 |
| MaxConnsPerHost（渠道级） | 单个渠道最大并发连接数 | 0（使用全局配置） | 渠道编辑 - 渠道额外设置 |

**与渠道切换的配合**：

当渠道并发已满时：
1. 渠道选择时自动跳过该渠道
2. 可用渠道计数会排除并发已满的渠道
3. 如果所有渠道都并发已满，会触发等待重试（如果启用）

---

## 六、请求转发流程

### 6.1 主控制器

**文件位置**: controller/relay.go

Relay 函数是请求转发的核心入口：

1. 获取并验证请求
2. 生成 RelayInfo
3. 敏感词检测（可选）
4. Token 估算和价格计算
5. 预扣费
6. 重试循环执行转发
7. 后处理（返还差额、记录日志）

### 6.2 请求格式与处理器映射

| 请求格式 | 处理器 | 说明 |
|----------|--------|------|
| RelayFormatOpenAI | relayHandler() | OpenAI 标准格式 |
| RelayFormatClaude | relay.ClaudeHelper() | Anthropic Claude 格式 |
| RelayFormatGemini | geminiRelayHandler() | Google Gemini 格式 |
| RelayFormatOpenAIRealtime | relay.WssHelper() | WebSocket 实时 API |
| RelayFormatOpenAIImage | relayHandler() | 图像生成/编辑 |
| RelayFormatOpenAIAudio | relayHandler() | 音频处理（TTS/STT） |
| RelayFormatEmbedding | relayHandler() | 向量嵌入 |
| RelayFormatRerank | relayHandler() | 重排序 |
| RelayFormatOpenAIResponses | relayHandler() | OpenAI Responses API |
| RelayFormatMjProxy | RelayMidjourney() | Midjourney 代理 |
| RelayFormatTask | RelayTask() | 任务类 API（Suno 等） |

### 6.3 适配器模式

**文件位置**: relay/channel/adapter.go

系统使用适配器模式支持多种 AI 服务：

| 适配器 | 支持的服务 |
|--------|-----------|
| OpenAI | OpenAI API |
| Claude | Anthropic Claude |
| Gemini | Google Gemini |
| Ali | 阿里云通义 |
| Azure | Azure OpenAI |
| Baidu | 百度文心 |
| Zhipu | 智谱 AI |

---

## 七、渠道错误替换

### 7.1 功能说明

当上游渠道返回错误且最终需要将错误发送给 AI 客户端时，系统会将特定状态码（401、402、403、429）的原始错误信息替换为统一的错误码和错误信息，避免 AI 客户端看到敏感的上游错误详情。

### 7.2 设计目的

| 目的 | 说明 |
|------|------|
| 隐藏敏感信息 | 避免暴露上游 API 密钥无效、账户余额不足等敏感错误详情 |
| 统一错误格式 | 为客户端提供一致的错误响应格式 |
| 安全合规 | 防止通过错误信息推断上游服务商信息 |

### 7.3 替换规则

| 原始状态码 | 原始含义 | 替换后状态码 | 替换后错误码 | 替换后错误信息 |
|------------|----------|--------------|--------------|----------------|
| 401 | 认证失败 | 500 | upstream_auth_error | 上游服务认证失败，请联系管理员 |
| 402 | 余额不足 | 500 | upstream_quota_error | 上游服务配额不足，请联系管理员 |
| 403 | 禁止访问 | 500 | upstream_forbidden | 上游服务拒绝访问，请联系管理员 |
| 429 | 速率限制 | 429 | upstream_rate_limit | 请求过于频繁，请稍后重试 |

**状态码替换说明**：
- 401/402/403 替换为 500：避免客户端误认为是自身认证问题，实际是上游服务问题
- 429 保持不变：让客户端知道需要降低请求频率

### 7.4 触发条件

错误替换仅在以下条件同时满足时触发：

1. 上游返回 401、402、403 或 429 状态码
2. 所有重试机制已用尽（渠道切换和等待重试都已失败或未启用）
3. 错误即将返回给 AI 客户端

### 7.5 不替换的情况

| 情况 | 说明 |
|------|------|
| 400 Bad Request | 客户端请求格式错误，应如实返回帮助调试 |
| 5xx 服务器错误 | 通用服务器错误，不包含敏感信息 |
| 成功重试 | 重试成功后不会返回错误 |
| 调试模式 | 管理员启用调试模式时可查看原始错误 |

### 7.6 配置参数

| 参数 | 说明 | 默认值 | 配置位置 |
|------|------|--------|----------|
| ChannelErrorReplaceEnabled | 启用渠道错误替换 | false | 管理后台 - 运营设置 |

**配置说明**：
- 开启后，系统会自动替换 401/402/403/429 状态码的错误信息
- 关闭后，将原样返回上游错误信息（可能包含敏感信息）
- 建议生产环境保持开启状态

### 7.7 示例

**原始上游错误响应**：
```json
{
  "error": {
    "message": "Incorrect API key provided: sk-xxxx****xxxx. You can find your API key at https://platform.openai.com/account/api-keys.",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

**替换后返回给客户端**：
```json
{
  "error": {
    "message": "上游服务认证失败，请联系管理员",
    "type": "upstream_error",
    "code": "upstream_auth_error"
  }
}
```

---

## 八、多渠道自动切换

**文件位置**: common/constants.go, common/channel_retry.go, controller/relay.go

### 8.1 功能说明

当启用「启用渠道自动切换」后，如果当前渠道返回错误，系统会自动切换到其他可用渠道重试请求。

此功能适用于配置了多个渠道的场景，希望在某个渠道故障时自动切换到其他渠道。

### 8.2 配置参数

| 参数 | 说明 | 默认值 | 配置位置 |
|------|------|--------|----------|
| ChannelSwitchEnabled | 启用渠道自动切换 | false | 管理后台 |
| ChannelRetryTimeout | 最大重试时长（秒），与渠道的请求超时时长和重试等待时长一起，间接决定了最大重试次数 | 300 | 管理后台 |

### 8.3 触发切换的错误码

系统根据状态码采用不同的重试策略：

| 状态码 | 说明 | 重试策略 |
|--------|------|----------|
| 400 | 请求格式错误 | 仅切换渠道（switch_only） |
| 401 | 认证失败 | 仅切换渠道（switch_only） |
| 402 | 余额不足 | 仅切换渠道（switch_only） |
| 403 | 禁止访问 | 仅切换渠道（switch_only） |
| 408 | 请求超时 | 仅切换渠道（switch_only） |
| 429 | 速率限制 | 切换或等待（switch_or_wait） |
| 500 | 服务器错误 | 切换或等待（switch_or_wait） |
| 502 | 网关错误 | 切换或等待（switch_or_wait） |
| 503 | 服务不可用 | 切换或等待（switch_or_wait） |
| 504 | 网关超时 | 仅切换渠道（switch_only） |
| 524 | 超时 | 仅切换渠道（switch_only） |
| 5xx | 其他5xx错误 | 切换或等待（switch_or_wait） |

**重试策略说明**：
- **switch_only**: 仅支持切换到其他渠道，不支持等待后重试同一渠道
- **switch_or_wait**: 优先切换渠道，无渠道可切换时支持等待后重试

### 8.4 不切换的情况

| 情况 | 说明 |
|------|------|
| 2xx 响应 | 成功响应 |
| 指定特定渠道 | 用户明确指定了渠道ID |
| 无其他可用渠道 | 所有渠道都已尝试过 |
| 渠道错误标记跳过 | 错误被标记为 SkipRetry |

### 8.5 切换日志

切换完成后，系统会记录完整的渠道切换路径，例如：

```
重试：1->2->3
```

表示请求依次经过了渠道 1、2、3，有助于排查问题。

---

## 九、单渠道自动重试

**文件位置**: common/constants.go, common/channel_retry.go, controller/relay.go

### 9.1 功能说明

当启用「启用渠道自动重试(无渠道可切换时)」后，在以下场景会等待一段时间后重试同一渠道：

- 只有单个渠道可用
- 多渠道都已尝试失败，回到最初的渠道

此功能主要用于处理 429 限流等临时性错误，适用于单渠道场景或作为多渠道切换的补充。

### 9.2 配置参数

| 参数 | 说明 | 默认值 | 配置位置 |
|------|------|--------|----------|
| ChannelRetryEnabled | 启用渠道自动重试(无渠道可切换时) | false | 管理后台 |
| ChannelRetryTimeout | 最大重试时长（秒），与渠道的请求超时时长和重试等待时长一起，间接决定了最大重试次数 | 300 | 管理后台 |

### 9.3 支持等待重试的错误码

只有以下错误码支持等待重试（其他错误码即使启用也不会等待重试）：

| 状态码 | 说明 |
|--------|------|
| 429 | 速率限制 |
| 500 | 服务器错误 |
| 502 | 网关错误 |
| 503 | 服务不可用 |
| 5xx | 其他5xx错误 |

### 9.4 等待时间策略

等待时间的确定按以下优先级：

**1. 上游 Retry-After 头**（最高优先级）

如果上游返回了 `Retry-After` 响应头（常见于 429 限流响应），系统会优先使用该值：

- 等待时间 = Retry-After 值 + 500ms 缓冲

支持两种标准格式：

| 格式 | 示例 |
|------|------|
| 秒数 | `Retry-After: 120` |
| HTTP 日期 | `Retry-After: Wed, 21 Oct 2015 07:28:00 GMT` |

**2. 渠道配置的重试等待时间**

如果上游未返回 `Retry-After` 头，则使用渠道配置的 `retry_wait_seconds` 值。

在渠道编辑页面的「渠道额外设置」中可以配置「重试等待时间（秒）」：

- **默认值：60 秒**（新建渠道时的默认值）
- 设置为 0：不等待重试，直接返回错误
- 设置为 N（N > 0）：等待 N 秒后重试

**3. 超时保护**

无论使用哪种等待时间，系统都会确保等待时间不超过最大重试时长（默认 300 秒）。如果等待后会超时，则不进行重试。

---

## 十、渠道切换与重试配置建议

### 10.1 配置建议

| 场景 | 推荐配置 |
|------|----------|
| 多渠道负载均衡 | 仅启用「启用渠道自动切换」 |
| 单渠道 + 需要处理限流 | 仅启用「启用渠道自动重试」 |
| 多渠道 + 需要处理限流 | 两者都启用 |
| 追求快速失败 | 两者都不启用 |

### 10.2 重试循环流程

1. 记录请求开始时间 startTime，初始化渠道排除列表 ExcludeChannelIds = []
2. 获取当前分组下该模型的可用渠道数量 availableChannels（排除限流和并发已满的渠道）
3. 进入循环（由超时控制退出）
4. 选择渠道（排除已尝试过的、限流中的、并发已满的渠道）
5. **增加渠道并发计数**
6. 将当前渠道添加到排除列表并执行转发
7. **请求完成后减少渠道并发计数**
8. 成功则直接返回
9. 失败则判断：
   - 如果启用了渠道切换且还有未尝试的渠道 → 立即切换渠道（不清空排除列表）
   - 如果启用了自动重试且错误码支持等待重试（429、5xx） → 清空排除列表，等待后重试
   - 否则返回错误
10. 超时时退出循环

**关键点**：
- 渠道排除列表确保每个渠道在一轮切换中只被尝试一次
- 当所有渠道都尝试过后，如果启用了自动重试，会清空排除列表并等待后重新开始
- 这实现了多渠道切换到单渠道等待重试的自动降级
- **并发计数确保每个渠道的活跃请求数不超过配置的上限**

---

## 十一、流式响应处理

### 11.1 流式扫描器

**文件位置**: relay/helper/stream_scanner.go

StreamScannerHandler 处理流式响应的核心流程：

1. 设置扫描器缓冲区
2. 设置 SSE 响应头
3. 启动 Ping 保活 goroutine
4. 启动扫描器 goroutine 读取上游响应
5. 实时转发数据到客户端
6. 处理 [DONE] 标记
7. 等待完成或超时

### 11.2 SSE 响应头设置

**文件位置**: relay/helper/common.go

| Header | 值 | 说明 |
|--------|-----|------|
| Content-Type | text/event-stream | SSE 内容类型 |
| Cache-Control | no-cache | 禁用缓存 |
| Connection | keep-alive | 保持连接 |
| Transfer-Encoding | chunked | 分块传输 |
| X-Accel-Buffering | no | 禁用 Nginx 缓冲 |

### 11.3 扫描器配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| InitialScannerBufferSize | 64KB | 初始缓冲区大小 |
| DefaultMaxScannerBufferSize | 64MB | 最大缓冲区大小 |
| StreamingTimeout | 可配置 | 流式响应超时时间 |

---

## 十二、连接保活机制

### 12.1 Ping 保活原理

系统通过定期发送 Ping 消息保持 SSE 连接不中断。

**Ping 数据格式**: : PING

- 以冒号开头的行是 SSE 注释
- 客户端会忽略注释行
- 但连接保持活跃状态
- 防止代理/网关超时断开

### 12.2 Ping 启动时机

| 位置 | 文件 | 说明 |
|------|------|------|
| API 请求层 | api_request.go | 流式请求发送前启动 |
| 流式扫描层 | stream_scanner.go | 处理流式响应时启动 |

### 12.3 Ping 配置参数

| 参数 | 说明 | 配置位置 |
|------|------|---------|
| PingIntervalEnabled | 是否启用 Ping | operation_setting |
| PingIntervalSeconds | Ping 间隔秒数 | operation_setting |
| maxPingDuration (api_request) | 最大 Ping 持续时间 | 120 分钟（硬编码） |
| maxPingDuration (stream_scanner) | 最大 Ping 持续时间 | 30 分钟（硬编码） |

### 12.4 Ping goroutine 退出条件

| 退出条件 | 触发场景 |
|----------|----------|
| pingerCtx.Done() | 请求正常完成，主动停止 Ping |
| c.Request.Context().Done() | 客户端主动断开连接 |
| pingTimeout.C | 超时保护，防止 goroutine 泄漏 |
| Ping 发送失败 | 网络错误或连接已断开 |

---

## 十三、渠道自动禁用

### 13.1 自动禁用触发条件

**文件位置**: service/channel.go

当渠道出现以下错误时，系统会自动禁用该渠道：

| 错误码/类型 | 说明 |
|------------|------|
| invalid_api_key | API 密钥无效 |
| account_deactivated | 账户已停用 |
| billing_not_active | 计费未激活 |
| insufficient_quota | 配额不足 |
| authentication_error | 认证错误 |

配置开关：AutomaticDisableChannelEnabled

---

## 十四、关键配置参数

### 14.1 HTTP 客户端配置

| 参数 | 说明 | 默认值 | 配置位置 |
|------|------|--------|----------|
| RelayTimeout | HTTP 请求超时时间 | 30 | common.RelayTimeout |
| RelayMaxIdleConns | 最大空闲连接数 | 20 | common.RelayMaxIdleConns |
| RelayMaxIdleConnsPerHost | 每主机最大空闲连接 | 2 | common.RelayMaxIdleConnsPerHost |
| RelayMaxConnsPerHost | 每渠道最大并发连接数 | 0（不限制） | common.RelayMaxConnsPerHost |

### 14.2 流式处理配置

| 参数 | 说明 | 配置位置 |
|------|------|----------|
| StreamingTimeout | 流式响应超时 | constant.StreamingTimeout |
| PingIntervalSeconds | Ping 间隔秒数 | operation_setting |
| StreamScannerMaxBufferMB | 扫描器最大缓冲区 | constant |

### 14.3 渠道切换与重试配置

| 参数 | 说明 | 配置位置 |
|------|------|----------|
| ChannelSwitchEnabled | 启用渠道自动切换 | common/管理后台 |
| ChannelRetryEnabled | 启用渠道自动重试(无渠道可切换时) | common/管理后台 |
| ChannelRetryTimeout | 最大重试时长（秒） | common/管理后台 |
| AutomaticDisableChannelEnabled | 自动禁用渠道 | common |
| AutomaticEnableChannelEnabled | 自动启用渠道 | common |

---

## 十五、总结

本系统的 AI 请求转发机制具有以下特点：

1. **多层中间件**: 请求经过认证、限流、分发等多层中间件处理
2. **智能渠道选择**: 基于优先级和权重的负载均衡，支持自动分组
3. **适配器模式**: 统一接口支持多种 AI 服务提供商
4. **流式处理**: 完善的 SSE 流式响应处理机制
5. **连接保活**: Ping 机制和 Keep-Alive 配置保持长连接不中断
6. **智能重试**: 基于状态码的差异化重试策略，支持渠道切换和等待重试
7. **渠道排除**: 通过排除列表避免重复选择同一渠道，支持自动降级
8. **并发限制**: 渠道级别的并发连接数限制，防止单渠道过载
9. **超时控制**: 统一的超时机制，从第一次请求开始计算
10. **自动运维**: 渠道自动禁用/启用，减少人工干预
11. **错误隐藏**: 敏感的上游错误信息自动替换为统一格式

### 关键设计要点

| 设计点 | 实现方式 |
|--------|----------|
| 高可用 | 多渠道负载均衡 + 智能重试 + 并发限制 |
| 高性能 | 连接池复用 + HTTP/2 支持 |
| 可扩展 | 适配器模式 + 插件化渠道 |
| 可观测 | 统计中间件 + 日志记录 |
| 安全性 | Token 认证 + 敏感词检测 |
