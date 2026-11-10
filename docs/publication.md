# 发布前脱敏

发布范围只包括版本控制中的源码、演示素材，以及显式构建的 `.app`。本机数据、密钥、聊天与构建过程的临时文件不得打包。

```sh
python3 scripts/check-public-data.py
python3 scripts/check-public-data.py --history
python3 scripts/check-public-data.py --archive PATH_TO_RELEASE.zip
python3 Tests/PublicationChecksTests.py
```

检查器只读扫描，不打印命中的值，只报告类别、文件、行号或对象标识。`--history` 检查可达提交和标签，避免只删除最新文件却让旧副本留在公开历史。可使用 `--known-secret-stdin` 从标准输入传入已知测试凭据，检查原文及 Base64/Hex 形式；不要将凭据写进命令参数或输出。

- 使用虚构会话 ID、演示文本与隔离的数据目录，不复用真实聊天 ID、标题或对话摘录作为公开测试夹具。
- 截图与 GIF 由原生演示视图导出，不读取钥匙串，不展示真实设备名称或用户偏好。
- 保留图片的 C2PA 素材来源标识与 AI 生成说明；公开的素材溯源 URN 不作为聊天会话 ID 处理。
- TTS 凭据只进入用户自己的钥匙串。`.env`、认证文件、会话缓存、记忆、日志、用户导入的 GIF 不得进入安装包。
- 对外提交使用 GitHub noreply 邮箱；示例路径使用占位符。

这套检查覆盖常见凭据格式、本机路径、字面会话标识、作者邮箱和安装包私有文件，不替代人工素材检查，也不能证明所有未知凭据或个人信息都已识别。GitHub 的历史缓存、已有克隆和分叉不能靠删除最新文件自动清除；已公开凭据仍需撤销或轮换。
