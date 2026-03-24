<!-- memory-vault-managed -->
## Memory Vault 跨工具记忆系统

本机已部署 memory-vault 跨工具记忆同步系统。

### 你应该知道的:
- 你的记忆文件 (`~/.claude/memory/`) 每30分钟自动同步到 memory-vault
- 其他工具 (Gemini/Antigravity/OpenClaw/Codex) 的蒸馏知识会自动出现在
  `~/.claude/memory/cross_tool_context.md` 中
- 按项目的跨工具知识会出现在对应项目的 memory 目录中

### 最佳实践:
- 重要决策请写入 memory (type: feedback 或 project), 它们会被跨工具同步
- 不需要手动管理跨工具同步, 系统自动处理
- `cross_tool_context.md` 是自动生成的, 不要手动编辑
<!-- memory-vault-managed -->
