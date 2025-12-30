# Claude Code `/compact` 命令原理

## 概述

`/compact` 是 Claude Code 的上下文压缩命令，用于在对话过长时压缩历史记录，释放上下文空间。

## 核心原理

**没有复杂算法，本质是让 LLM 自己生成结构化摘要。**

## 工作流程

```
┌─────────────────────────────────┐
│     完整对话历史 (80k tokens)    │
└─────────────────┬───────────────┘
                  ↓
┌─────────────────────────────────┐
│   发送 Prompt: "请按以下结构总结..." │
└─────────────────┬───────────────┘
                  ↓
┌─────────────────────────────────┐
│   LLM 生成结构化摘要 (5k tokens)  │
└─────────────────┬───────────────┘
                  ↓
┌─────────────────────────────────┐
│   用摘要替换原对话，开始新会话     │
└─────────────────────────────────┘
```

## Prompt 设计

Claude Code 使用精心设计的 Prompt 指导 LLM 生成摘要。

### 英文原版（源码提取）

```
Your task is to create a detailed summary of the conversation so far,
paying close attention to the user's explicit requests and your previous actions.

This summary should be thorough in capturing technical details, code patterns,
and architectural decisions that would be essential for continuing development
work without losing context.

Before providing your final summary, wrap your analysis in <analysis> tags
to organize your thoughts and ensure you've covered all necessary points.
In your analysis process:

1. Chronologically analyze each message and section of the conversation.
   For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like:
     - file names
     - full code snippets
     - function signatures
     - file edits
   - Errors that you ran into and how you fixed them
   - Pay special attention to specific user feedback that you received,
     especially if the user told you to do something differently.

2. Double-check for technical accuracy and completeness,
   addressing each required element thoroughly.

Your summary should include the following sections:

1. Primary Request and Intent:
   Capture all of the user's explicit requests and intents in detail

2. Key Technical Concepts:
   List all important technical concepts, technologies, and frameworks discussed.

3. Files and Code Sections:
   Enumerate specific files and code sections examined, modified, or created.
   Pay special attention to the most recent messages and include full code
   snippets where applicable and include a summary of why this file read
   or edit is important.

4. Errors and fixes:
   List all errors that you ran into, and how you fixed them.
   Pay special attention to specific user feedback that you received,
   especially if the user told you to do something differently.

5. Problem Solving:
   Document problems solved and any ongoing troubleshooting efforts.

6. All user messages:
   List ALL user messages that are not tool results.
   These are critical for understanding the users' feedback and changing intent.

7. Pending Tasks:
   Outline any pending tasks that you have explicitly been asked to work on.

8. Current Work:
   Describe in detail precisely what was being worked on immediately before
   this summary request, paying special attention to the most recent messages
   from both user and assistant. Include file names and code snippets where applicable.

9. Optional Next Step:
   If there is a next step, include direct quotes from the most recent
   conversation showing exactly what task you were working on and where you left off.
   This should be verbatim to ensure there's no drift in task interpretation.
```

### 中文翻译版

```
你的任务是为目前的对话创建一份详细的摘要，
密切关注用户的明确请求和你之前的操作。

这份摘要应该全面捕捉技术细节、代码模式和架构决策，
这些对于在不丢失上下文的情况下继续开发工作至关重要。

在提供最终摘要之前，请将你的分析包裹在 <analysis> 标签中，
以整理思路并确保涵盖所有必要的要点。在分析过程中：

1. 按时间顺序分析对话中的每条消息和每个部分。
   对于每个部分，彻底识别：
   - 用户的明确请求和意图
   - 你处理用户请求的方法
   - 关键决策、技术概念和代码模式
   - 具体细节，如：
     - 文件名
     - 完整代码片段
     - 函数签名
     - 文件编辑
   - 你遇到的错误以及如何修复它们
   - 特别注意你收到的用户反馈，
     尤其是用户要求你以不同方式做某事的情况。

2. 仔细检查技术准确性和完整性，
   彻底处理每个必需的元素。

你的摘要应包含以下部分：

1. 主要请求和意图：详细捕捉用户所有的明确请求和意图
2. 关键技术概念：列出讨论过的所有重要技术概念、技术和框架
3. 文件和代码部分：列举检查、修改或创建的具体文件和代码部分，
   特别关注最近的消息，包含完整代码片段，并总结其重要性
4. 错误和修复：列出遇到的所有错误及修复方法，注意用户反馈
5. 问题解决：记录已解决的问题和正在进行的故障排除工作
6. 所有用户消息：列出所有非工具结果的用户消息，理解用户反馈和意图变化
7. 待处理任务：概述被明确要求处理的待处理任务
8. 当前工作：详细描述摘要请求前正在进行的工作，包含文件名和代码片段
9. 可选的下一步：直接引用最近对话原文，说明任务进度，确保理解不偏差
```

### 中文精简版

```
为当前对话创建详细摘要，关注用户请求和你的操作。
摘要需捕捉技术细节、代码模式和架构决策，确保后续开发不丢失上下文。

先在 <analysis> 标签中整理思路，按时间顺序分析每条消息，识别：
- 用户请求和意图
- 你的处理方法
- 关键决策和技术概念
- 具体细节：文件名、代码片段、函数签名、文件编辑
- 遇到的错误及修复方法
- 用户反馈（尤其是要求你改变做法的情况）

摘要包含以下部分：

1. 主要请求和意图：用户的明确请求
2. 关键技术概念：涉及的技术、框架
3. 文件和代码：检查/修改/创建的文件，附代码片段
4. 错误和修复：遇到的错误及解决方法
5. 问题解决：已解决和正在排查的问题
6. 用户消息：所有非工具结果的用户消息
7. 待处理任务：明确要求的待办事项
8. 当前工作：摘要请求前正在进行的工作
9. 下一步（可选）：直接引用原文，说明任务进度
```

### Prompt 设计要点

1. **先分析后总结** - 要求在 `<analysis>` 标签中先整理思路
2. **按时间顺序** - 按对话顺序逐条分析
3. **保留细节** - 强调保留文件名、代码片段、函数签名等具体信息
4. **关注错误** - 特别记录错误和修复方法，避免重复犯错
5. **用户反馈优先** - 强调用户的反馈和意图变化
6. **原文引用** - 下一步计划要求直接引用原文，防止理解偏差

## 摘要结构

生成的摘要包含以下部分：

| 序号 | 部分 | 说明 |
|------|------|------|
| 1 | Primary Request and Intent | 用户的明确请求和意图 |
| 2 | Key Technical Concepts | 重要的技术概念、框架 |
| 3 | Files and Code Sections | 检查/修改/创建的文件及代码片段 |
| 4 | Errors and fixes | 遇到的错误及修复方法 |
| 5 | Problem Solving | 已解决的问题和正在排查的问题 |
| 6 | All user messages | 所有用户消息（非工具结果） |
| 7 | Pending Tasks | 待完成的任务 |
| 8 | Current Work | 当前正在进行的工作 |
| 9 | Optional Next Step | 下一步计划 |

## 使用场景

- 上下文使用率较高时（如 80%+）
- 完成一个大任务后，准备开始新任务
- 对话时间较长，需要继续工作

## 优缺点

| 优点 | 缺点 |
|------|------|
| 释放大量上下文空间 | 丢失部分细节 |
| 可以继续更长对话 | 无法回溯原始对话内容 |
| 保留关键决策信息 | 某些边缘信息可能被遗漏 |
| 结构化摘要便于继续工作 | 依赖 LLM 总结质量 |

## 自定义压缩指令

用户可以在 `CLAUDE.md` 文件中添加自定义指令来控制压缩重点：

```markdown
## Compact Instructions
When summarizing the conversation focus on typescript code changes
and also remember the mistakes you made and how you fixed them.
```

或：

```markdown
# Summary instructions
When you are using compact - please focus on test output and code changes.
Include file reads verbatim.
```

## 技术实现要点

1. **无特殊算法** - 纯粹依赖 LLM 的理解和总结能力
2. **结构化 Prompt** - 通过详细的指令确保摘要包含关键信息
3. **有损压缩** - 牺牲细节换取空间，本质是信息的有损压缩
4. **上下文替换** - 用生成的摘要完全替换原始对话历史
