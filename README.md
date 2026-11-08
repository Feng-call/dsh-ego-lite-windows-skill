# dsh-ego-lite-windows-skill

给 DeepSeek Harness（DSH）用的 **ego lite（Windows）浏览器技能**。把 `ego-lite-windows` 这个技能作为原生 dsh bundle 打包，装好即出现在每个会话的技能目录里，不用手动往 `~/.dsh/skills` 复制。

## 这个技能解决什么

- **分清两台“浏览器”**：DSH 自带 ego 运行时（借 Chrome 内核、空 profile、窗口标题 `- Google Chrome`）vs 用户真正的 ego lite（窗口标题 `- ego`、带登录态、无 CDP）。
- **空间规矩**：默认 `taskSpace(...)` 建自己的 Agent Space 干活；`claimTaskSpace` 用户的 space 仅在用户明确要求时；`finish` 与 `deleteSpaces` 的区别。
- **正确调用方式**：`ego-browser nodejs -e "await import('file:///...mjs')"`，以及为什么需要 Full access（否则 `Failed to connect to ego_cli bootstrap`）。
- **坑位**：PowerShell 5.1 毁参数、每轮新进程、`task.page()` 永远 truthy、异常退出后卡住、`finish` 不保证删空间。
- **自动判题页面**：Wrong Answer（status 2）vs Runtime Error（status 3），以及“零输出也判错”的探针法。

内容与官方文档 `https://lite.ego.app/document/zh/docs/windows/*`（Space / Snapshot / ego-browser / Quick start / Skills）对齐，并标注了哪些是经验补充。

## 安装

### 方式 A：作为 DSH 插件（推荐，能被插件管理器管理）

```bash
# 在 profile 目录（Windows 默认 C:\Users\<你>\.dsh\profiles\desktop）
pnpm add <本包路径或 npm 包名>
```

装完后 `package.json` 的 `dsh.profile.bundles` 里会出现 `dsh-ego-lite-windows-skill`，重启 DSH 生效。

### 方式 B：只要技能，不装插件（最省事）

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

```bash
# Git Bash / macOS / Linux
bash ./install.sh
```

它只做一件事：把 `skills/ego-lite-windows/SKILL.md` 复制到 `~/.dsh/skills/ego-lite-windows/SKILL.md`。技能目录是热加载的，复制完立刻出现在目录里（无需重启）。

## 发布到插件市场

市场（dshmarket）索引的是 **npm 上的 dsh 插件包**，所以顺序是：

1. `npm login`（需要你自己的 npm 账号；本仓库不含任何凭据）
2. `npm publish --access public`
3. 到 dshmarket / awesome-dsh-plugin 的收录渠道提交仓库或包名

发布前建议先本地验证：

```bash
npm pack --dry-run     # 看 files 列表是否只含 lib/skills/cordis.patch.yml
node --check lib/index.js
```

## 文件结构

```
package.json          # dsh.category=skill, dsh.bundle.patch
cordis.patch.yml      # 一行 insert：把技能注册进 profile 根
lib/index.js          # ctx.skills.registerProvider + FileSystemSkillProvider
skills/ego-lite-windows/SKILL.md
install.ps1 / install.sh
```

## 许可

MIT。
