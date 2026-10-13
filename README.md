# 络笺 Relakeep 私密备份模板

给自己的加密记忆库留一份 GitHub 备份。这个公开模板不包含任何用户数据。

## 第一次使用

1. 点击 **Use this template → Create a new repository**，名称例如 `my-relakeep-vault`，可见性选择 **Private**。请创建新的私密仓库，不要 fork 这个公开模板。
2. 安装 [Git](https://git-scm.com/downloads/win) 和 [GitHub CLI](https://cli.github.com/)，在终端执行 `gh auth login`。
3. Clone **自己的私密仓库**，打开该文件夹中的终端。
4. 在络笺桌面版的「设置 → 记忆与备份」点击「导出加密备份」。
5. 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup.ps1 -Backup "C:\Users\你的用户名\Downloads\atlas-encrypted-backup.json"
```

脚本校验加密备份结构，通过 GitHub API 确认仓库为 Private，然后只提交 `vault/latest.atlas-backup.json`。公开仓库、明文清单、SQLite 和格式错误会被拒绝。

以后导出新备份后，重复同一命令。需要先配置 Git 提交身份时执行 `git config user.name "你的名字"` 和 `git config user.email "你的 Git 邮箱"`。

## 换电脑或恢复

Clone 自己的私密仓库后执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore.ps1
```

脚本拉取最新备份并复制到桌面。打开络笺「设置 → 恢复加密备份」，选择文件，输入原来的主密码。恢复会覆盖当前库，请先导出当前库的备份。

也可直接在 GitHub 下载 `vault/latest.atlas-backup.json` 后恢复。旧备份保留在 Git 历史中。

## 保存哪些数据

仅保存络笺导出的加密备份。主密码、Windows 自动解锁凭据、裸 SQLite、脱敏或明文 JSON、API Key 不要另行提交。备份中已有的数据继续受原库的加密保护。

这是一份手动备份，不会自动合并两台电脑的改动。GitHub 登录与备份脚本的 Git 授权分别完成；官网 OAuth 不索取仓库读写权限。

官网与教程：[atlas.sayori.org](https://atlas.sayori.org/guide)。
