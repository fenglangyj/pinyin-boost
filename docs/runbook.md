# 操作手册（RUNBOOK）

目标：把微软拼音调成"你要的样子"，并生成一份**为你定制**的 20,000 条词库。

## 0. 前置

| 需要 | 用途 | 怎么装 |
|---|---|---|
| Windows 10/11 + PowerShell 5.1 | 全部脚本 | 系统自带 |
| Python 3.8+ | `tools/` 下的词库工具 | python.org（纯标准库；可选 `pip install pypinyin` 用于注音） |
| .NET 10 运行时 | imewlconverter 的 CLI | `winget install Microsoft.DotNet.Runtime.10` |
| 代理（可选） | 直连 GitHub 不稳时 | 脚本自动探测 `127.0.0.1:7890`，也可 `-Proxy` 指定 |

## 1. 环境体检（只读）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-Environment.ps1
```
确认：`IME data dir` 有路径（没有就先打几个中文字）、`IsAdmin`、`dotnet` 是否可用。

## 2. 隐私加固 + 备份

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\A\Backup-PinyinData.ps1   # 词库 + 注册表 + SHA256 清单
powershell -ExecutionPolicy Bypass -File .\scripts\A\Set-PinyinPrivacy.ps1   # 关闭云候选，保留本地自学习
taskkill /f /im ChsIME.exe                                                   # 生效（输入法会自动重启）
```
回滚：`Set-PinyinPrivacy.ps1 -Restore`、`Restore-PinyinData.ps1 -BackupPath <备份目录>`

## 3. 生成"内置已知词"剔除表（**必做**，否则会浪费额度）

```powershell
python .\tools\extract_builtin_words.py
```
产出 `cache/builtin/builtin-domain-words.txt`（49 个专业词典 ≈17.9 万词）与 `builtin-phrase-words.txt`（内置短语 ≈4.5 万条）。
> 核心词库 `ChsPinyin.lex` 是索引编码读不出（见 `docs/format-and-limits.md`），所以**真实内置覆盖比这个数字更高** —— 这也意味着"通用词灌进去基本没用"。

## 4. 取数据源

```powershell
python .\tools\fetch_sources.py --proxy http://127.0.0.1:7890
python .\tools\fetch_sources.py --province 50,51        # 顺便提取川渝乡级地名（50=重庆 51=四川）
python .\tools\fetch_sources.py --wiki 摩托車製造商,网络流行语
```
缓存在 `cache/<源>/`（含 `manifest.json`：url/license/sha256）。已下载的会跳过。
**抓不到的词汇域不要放弃** —— 按 `skill/SKILL.md` §3.3 产出取词清单，交接给用户或其他 agent。

## 5. 采集画像 → 生成词表

画像由 skill 通过对话获取（见 `skill/SKILL.md`），存成 `skill/profile.json`（可参考 `skill/profile.example.json`）。然后：

```powershell
python .\tools\build_profile_lexicon.py --profile .\skill\profile.json --out .\data\lexicons\profile-lexicon.txt
```
脚本会：过滤（纯中文 2–15 字）→ 剔除内置已知词 → 去重 → 按类别配额打分 → 截断到 20,000，并输出同目录的 `-report.md`（含来源与 provenance）。

## 6. 转容器 + 官方导入

```powershell
# 扫描 data/lexicons/ 下的词表，转成微软拼音自学习词库容器（自动下载 imewlconverter，需 .NET 10）
powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1 -DownloadTool
```
然后在 UI 里导入（**只有这条路可靠**）：

> 设置 → 时间和语言 → 语言和区域 → 中文(简体，中国) → ⋯ → 语言选项 → 微软拼音 → 词库和自学习 → **导入**

产出文件在 `out\`（或脚本打印的路径），自检项：magic `55 AA 88 81`、`count@0x0C` 等于条数、大小 = `ceil((9228+60N)/1024)×1024`。

## 7. 复测与调参

导入前后各打一遍同一份采样清单（脚本会生成 `<name>-retest.md`），把命中率写回报告：
- 命中率低的类别 → 加配额、提高权重
- 命中率≈100% 的类别 → 减配额（额度让给别的域）

## 8. 常见故障（都是实测踩过的坑）

| 现象 | 原因与处理 |
|---|---|
| 直接替换词库文件后"变化没几天就没了" | IME 会回灌覆盖（实测 19,900 条写入后重合度掉到 6.9%）→ **必须走官方导入** |
| 导入 25,000 条只生效 20,000 | 上限由 IME 强制，无法突破 → 做取舍 |
| 词库里很多词没进去 | 含字母/数字/空格/超过 15 字会被过滤 |
| 找不到 `ChsPinyinUDL.dat` | 文件名会变（`_Setting` / `_Setting_Beta`）→ 脚本动态探测；也检查 Roaming/Local 两个位置 |
| `dotnet` 缺失 | `winget install Microsoft.DotNet.Runtime.10` |
| 上传/克隆很慢 | 走代理：`-Proxy http://127.0.0.1:7890`；大文件用 curl 不要用 Invoke-WebRequest |
| 想恢复出厂 | `Restore-PinyinData.ps1 -BackupPath <最早那份备份>` + `Set-PinyinPrivacy.ps1 -Restore` |
