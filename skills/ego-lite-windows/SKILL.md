---
name: ego-lite-windows
description: 当任务要用「用户自己那个 ego lite 浏览器」时加载：窗口标题以「- ego」结尾、里面是用户的登录态和标签页（区别于 DSH 的 ego_* 工具，那套连的是借本机 Chrome 内核启动的空 profile 运行时，一开就是登录页）。默认做法：用 taskSpace(...) 建自己的空间干活，**claim 用户的 space 仅在用户明确要求时**（官方指南 L343）；另含 ego-browser nodejs + claimTaskSpace/adopt 的接管流程、必踩的坑位清单（沙箱 bootstrap、PowerShell 引号、用户标签保护、每轮新进程、异常退出后卡住重试）、自动判题页面「运行错误」的排查法。触发词：ego lite、ego浏览器、接管我的浏览器、浏览器里已经登录、超星/学习通作业运行错误。
---

# ego lite 浏览器（Windows / DSH）操作手册

## 0. 先分清两台浏览器（走错就是白干）

| | DSH 自带 ego 运行时（`ego_*` 工具） | 用户的 ego lite（要操作的） |
|---|---|---|
| 窗口标题 | `页面 - Google Chrome` | `页面 - ego` |
| 内核/目录 | 借 `chrome.exe`；状态在 `%LOCALAPPDATA%\ego-lite-linux\`（见 `ego_doctor`） | 安装于 `C:\Program Files\Citro Labs\ego lite\Application\<ver>\` |
| 登录态 | **空 profile，没有** | 用户全部登录态、标签页 |
| CDP | 有（`ego_doctor` 能查 port） | **默认不开**，`netstat -ano` 查不到端口 |
| 谁能操作 | `ego_*` 工具 | 只能 `ego-browser nodejs` |

`ego_doctor` 里 `browser binary: ...chrome.exe` = 你在跟 DSH 的运行时说话，不是用户的 ego lite。

## 0.5 官方模型：Agent 在它自己的 Space 里干活，你的 Space 不受影响

官方文档（<https://lite.ego.app/document/zh/docs/windows/space>）原文：

> 每个 Space 存放 Agent 一项浏览器任务的标签页。Agent 可以在这个 Space 中打开页面并工作，**你则继续使用自己的标签页**。
> 任务结束后，**标签页仍保留在 Space 中**，方便你检查 Agent 的答案所依据的页面。
> 为不同的任务分配各自的 Space……Agent 继续某个任务时，会使用 `useOrCreateTaskSpace(name)` 回到对应的 Space。

WorkBuddy / DeepSeek Harness 指南（`/docs/windows/workbuddy`、`/docs/windows/deepseek-harness`）也是同一句：

> 它会**在 ego(lite) 的 Space 中**打开页面……**任务运行期间，你自己的标签页仍留在原来的 Space 中**。

所以“建自己的 space”不是我的发明，是官方模型。配套细节：

- 继续同一个任务：`taskSpace("<同一个 name>")` 回到原空间（官方文档叫 `useOrCreateTaskSpace(name)`，但当前 CLI 已把它标为 legacy，默认用 `taskSpace(name)` 更稳）。
- **页面一变就要重取 snapshot**：旧的 `@ref` 可能已经指向别处了。
- 任务结束**保留结果页**是官方建议（方便核对证据），也就是 `finish({ keep: ["p1", "p2"] })` 而不是无脑 `keep: []`。

## 0.6 文档 API 与当前 CLI 的差别（实测 0.6.2.8）

官方文档 `/docs/windows/ego-browser` 的示例是**旧的辅助函数层**：

```js
await useOrCreateTaskSpace('check a page')
await openOrReuseTab('https://example.com', { wait: true })
cliLog(await snapshotText())
```

- 这四个在 0.6.2.8 上**确实能跑**（`typeof` 都是 function，`snapshotText()` 真的打印出语义树）；
- 但 `useOrCreateTaskSpace(name)` 返回的是**空间记录**（`createdBy/id/name/ownership/recentTabTitles/…`），**没有 `.finish()` / `.goto()`**——照文档写 `(await useOrCreateTaskSpace(x)).finish()` 会 `TypeError: task.finish is not a function`；
- 它操作的是“当前活动空间”，空间切换靠 `switchTaskSpace` 之类，容易和对象式混用搞乱。

**当前 CLI 自己的指南用对象式**（推荐，本技能全篇按这个写）：

```js
const task = await taskSpace("name");   // TaskSpace handle
const page = task.page("p1");
await page.goto(url);                    // page.snapshot() / page.click() …
await task.finish({ keep: ["p1"] });
```

**`finish()` 不一定删空间**（实测两种结果）：`taskSpace()` 建的空间、页面也是自己 `goto` 开的 → `finish({keep:[]})` 后空间消失；而**里面有未托管/用户标签**（例如 legacy `openOrReuseTab` 开的页）→ 空间会保留下来并转为 **user 所有**，之后 `taskSpace(同名)` 报 “belongs to the user”，得 `claimTaskSpace(id)` 才能再进。真要连空间一起清掉：

```js
await deleteSpaces({ ids: [4] });   // 返回 {deletedSpaceIds, skippedRunningSpaceIds}；也支持 {scope:'all'|'task'}
```

## 1. 空间默认：建自己的空间；claim 用户的 space 仅在用户明确要求时

**官方指南原文**（`ego-browser skill` 输出，L76 / L77 / L343）：

- Use exactly one TaskSpace for the entire user goal. **Create it once**, print its `spaceId`, and resume that same space in later rounds.
- If the name belongs to a **user-owned space**, it fails with `EGO_TASK_SPACE_NAME_IN_USE`: ask the user whether to work in that space (then `claimTaskSpace(id)`), or **pick another name**.
- **Claim a user-owned or inactive space only when the user explicitly asks.**

**落地细节（下面这些是经验补充，不是官方原文）：**

- 用户的标签都在一个 user 空间（通常 `id 0`、`name ""`）。同一 profile 下 cookie 共享，所以**新空间里 `goto` 同一个 URL 照样是登录态**——大多数“在 ego 里帮我做 X”根本不需要碰用户的 space。
- 空间可以并存（实测：`0` 和新建空间同时出现在 `listTaskSpaces()`），但整个 ego lite 仍只有一个窗口、一套前台——“并存”指标签/所有权不打架，不是两个光标同时动。
- 自己的空间用 `finish({ keep: [...] })` 结束：**有结果页/证据页就保留**（官方建议，方便用户核对），纯跑腿任务才 `keep: []`。注意 `finish()` 只结束任务、**不删空间**（空间转为 user 所有）；要彻底清掉用 `deleteSpaces({ ids: [id] })`。

```js
const task = await taskSpace("dsh-<任务名>-<时间戳>");   // 建自己的空间，不碰 space 0
await task.page("p1").goto(url);
// …干活…
await task.finish({ keep: ["p1"] });                     // 结束任务（结果页留着给用户核对）
```

**例外：可以 claim 用户 space 的两种情况**（都建立在“用户明确提出”之上）：

1. 用户明确说「就在我现在这个页面/这个标签上操作」；
2. 页面内有**尚未保存的状态**（填了一半的表单、SPA 里的临时选择），新标签复制不了。

claim 之后：操作完立刻交还控制权，并告诉用户「已交还」。

```js
const task = await claimTaskSpace(0);   // 仅在上述例外下
// …操作用户那个标签…
await task.handOff();                    // 还控制权
```

> **`handOff()` 只是交还控制权，不结束任务。** 之后浏览器里会一直挂着那条「Agent 任务 / 你正在控制 · 交还给 Agent · 终止任务」的浮条（ownership 停在 `agentDelegatedToUser`）。**活干完了要 `finish({ keep: [...] })`**：用户标签受保护会被保留，任务条随之消失、ownership 回到 `user`。只有“临时让用户操作一下、等下还要接着干”才用 `handOff()`。

> 反例（我已犯过）：用户只说「在 ego 浏览器里帮我做这个」，就 `claimTaskSpace(0)` + `adopt` 了正在看的那页——那段时间用户自己的浏览器被占住。新空间 `goto` 同一个 URL 就能做。

## 2. 操作流程

**权限**：需要 `danger-full-access`，否则报 `Failed to connect to ego_cli bootstrap`。

**执行方式**：写 UTF-8 的 `.mjs` 文件（用文件工具写，别用 `Set-Content`/`Out-File`），然后

```bash
ego-browser nodejs -e "await import('file:///D:/path/round-01.mjs')"
```

`-e` 里只放这句 ASCII 的 import；PowerShell 5.1 会吃掉双引号、把中文读成 ANSI。Bash 里也可用 heredoc。

**骨架**：

```js
const spaces = await listTaskSpaces();          // 用户空间常为 {id:0, ownership:"user", name:""}
const task = await claimTaskSpace(0);           // 用户明确要求时才 claim（见第 1 节）
const tabs = await task.tabs();                 // [{label?, page, title, url, active, openedBy}]
const t = tabs.find(x => x.title.includes("作业"));
const page = t.label ? task.page(t.label) : await task.adopt(t.page);
console.log(await page.evaluate(() => document.title));
```

**常用 API**（ego-browser 自定义，不是 Playwright）：
`url/title/info/snapshot/screenshot/evaluate/fetch`、`click/fill/selectOption/press/hover/focus`、`keyboard.type|paste`、`mouse.click|wheel|dragAndDrop`、`waitForSelector/waitForURL/waitForFunction`、`page.cdp()`、`page.close()`、`task.finish({keep:[...]})`。

**空间所有权状态**：`user` → `agent`（claim 后）→ `agentDelegatedToUser`（`handOff()` 或本轮脚本结束自动交还；**用户真正操作一次才回到 `user`**）。
**只读看一眼用户的标签**：`adopt(page)` → 读 `title()/evaluate()` → `release(label)` 归还（不关闭标签）→ `handOff()`。
**标签数量别信 `recentTabTitles`**：`listTaskSpaces()` 里它只给最近 3 个，真实数量要用 `task.tabs()`。
**收尾**：`finish({ keep: [...] })` 结束任务（结果页按需保留，用户标签受保护）；空间本身不会消失，需要清理就 `deleteSpaces({ ids: [id] })`。

## 3. 坑位清单（4 个高频 + 1 个补充）

1. **沙箱**：`workspace-write` 下连不上 ego_cli bootstrap → 换 `danger-full-access`。
2. **PowerShell 毁脚本**：一律 `.mjs` + `-e import`；中文只放在文件里。
3. **每轮新进程**：变量不保留 → 每轮写新的 `round-NN.mjs`（别改老文件重跑，会重放旧步骤）。
4. **`task.page("p2")` 永远 truthy**：不能当存在性判断，用 `task.pages()`；`task.page(label)` 不会创建页。

另外：不要用新 TaskSpace 去「自救」卡住的页面（官方 L78）。

**补充坑**：上一次脚本异常退出（例如在 `finish()` 之后还在用 `page.*`）之后，紧接着的 `ego-browser` 调用可能长时间没有任何输出——bootstrap 没清干净。用 `timeout 45 ego-browser nodejs …` 包一层，重试一次通常就恢复；`finish()` 之后不要再碰任何 Page，改用普通 `await new Promise(r => setTimeout(r, 300))` 等待。

## 4. 读页面的效率原则

- 优先 `page.evaluate()` 批量取需要的字段（结构、文本、隐藏 input），`snapshot()` 只用来选目标，`screenshot()` 只做视觉确认；
- 大页面直接 snapshot 会爆上下文；
- 写完/改完先回读校验（长度/关键字段），再截图确认；
- 内嵌 iframe 演示站（同源）可直接 `iframe.contentDocument` 读写；按坐标点 iframe 内的元素时，坐标 = `iframe.getBoundingClientRect()` + 元素相对 iframe 的 rect（CSS 像素，`devicePixelRatio` 不影响 `innerWidth`）。

## 5. 自动判题页面：先分清「代码错」还是「基准错」

超星/学习通程序题页面结构：
- 每道题 `div.questionLi` → `.CodeMirror`（`el.CodeMirror` 拿实例）
- 答案字段 `input#answer<qid>`（hidden），语言 `input#languageSelect<qid>`（22=Python 3.12）
- 写入：`cm.setValue(code)` + `cm.refresh()` + `hidden.value=code` + 派发 `input`/`change`，然后回读长度校验。**没点「暂时保存/提交」前刷新会丢**。

判题接口 `POST /mooc-ans/exam/test/procedural-run`
（`type=work & language=22 & code & quesid & workLibraryId & classId`）
返回 `{status, results:[{result,access,exit_code}], errorDetails:[{index,total,isPassed,message}]}`。

- `access: Wrong Answer`（status 2）= 输出比对不过；`RunTime Error`（status 3）才是程序报错；
- 返回里**没有 expected 标准输出**；
- 探针法：提交 `pass`（零输出）和 `print('hello')` 各跑一次。若都判 Wrong Answer，说明服务器挂了固定标准输出、逐字比对且学生端不可见——此时改代码没用，别乱改，直接告诉用户「不是代码问题，需要老师的标准输出」。

## 6. 作答类页面（测评/问卷）的节奏

用户说「像人一样」时，指的不是慢，而是**别一次粘贴、别连点**：

- 每题操作前 1.5~4.5 s 停顿（推理题更久），鼠标先移到目标附近停一下再点；
- 输入框**逐字符** type（110~260 ms/字符），不要 `fill()` 一次性塞；
- 交卷前回读全部答案做一次校验，再停顿几秒点提交；
- 页面有「仅首次提交计分」时，**提交前必须确认全部题目已填**，失败就 throw，不要带缺项交卷。

## 7. 任务边界与结果交付（官方 Quick start / Skills 的要求）

官方文档反复强调的几条，直接当行为准则用（<https://lite.ego.app/document/zh/docs/windows/quick-start>、`/docs/windows/skills`）：

- **看不到就标“未显示”，不要猜**：页面上没有的数据（浏览量之类）标注缺失，不要编造。
- **结论要可核对**：返回结果时附**来源链接/页面标题**，并说明是在哪个 Space 里看的。
- **停手点由人定**：登录、验证码、付款、最终提交（含发帖/点赞/申请）一律交给人处理，不要在提示词没要求时自己点。
- **写任务时把人话讲清楚**：目标 + 在哪一步停下来等（这也是用户该给你的信息；缺了就先问一句）。
- 各 harness 的 Skill 入口不一样（Codex `/ego`、OpenCode `@ego-browser`、OpenClaw `/skill ego-browser`、DSH `/ego-browser` + 空格 + 任务）；如果 Skill 列表里没有 `ego-browser`，先完成 ego lite 初始设置再重启 Agent。权限统一是 **Full access**。

## 8. 速查

```bash
ego-browser --help          # 命令清单：help / skill / upgrade / import / nodejs
ego-browser skill           # 当前版本的完整使用指南（值得整读一遍）
ego-browser nodejs -e "await import('file:///D:/x/round-01.mjs')"
ego-browser import list     # 可导入的浏览器 profile
# 多个浏览器实例时：ego-browser --ego-server-name=<name> nodejs -e '...'
```
