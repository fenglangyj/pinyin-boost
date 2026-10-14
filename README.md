# pinyin-boost

**一个把微软拼音（Microsoft Pinyin / 微软输入法）调成"你要的样子"的开源工具箱**：
关掉云候选保隐私 · 备份/还原词库 · **按你的画像生成一份最优的 20,000 条个性化词库**。

> 核心不是"词多"，而是"词对"。本仓库的知识来自对微软拼音词库格式的完整逆向与实测，见 [`docs/format-and-limits.md`](docs/format-and-limits.md)。

---

## 一、先说四条实测硬约束（决定了整个设计）

| 约束 | 实测结论 |
|---|---|
| **上限 20,000 条** | 由 IME 强制。构造合法的 25,000 条容器导入后仍被截回 20,000 —— 任务是取舍，不是堆量 |
| **官方导入才可靠** | 直接替换词库文件会被 IME 回灌覆盖（实测写入 19,900 条后重合度掉到 6.9%）；走设置里的"导入"则 100% 稳定 |
| **只收纯中文 2–15 字** | 含字母/数字/空格会被 IME 过滤。`BMW`、`K8s` 收不了，要收它们的中文名与中文绰号（水鸟/金翼） |
| **通用词基本无效** | 内置核心词库覆盖面极广（27 词分层采样 26 命中，含低频词、县区地名、人名、4 字词）。价值在长尾专名 + 行业术语 + 圈层黑话 + 新词 + 私有词 |

## 二、它能做什么

### 1. 个性化词库（skill：`pinyin-lexicon-profiler`）
对话拿到你的画像 → 推理出你会输入哪些词 → 从开放数据/互联网取词并校验 → 去重剔重 → 生成 20,000 条最优词库 → 引导官方导入 → 复测调参。

见 [`skill/SKILL.md`](skill/SKILL.md)。**抓不到的词源不会放弃**：会产出"取词清单"交接给用户或其他 agent 去取（见 SKILL.md §3.3）。

### 2. 隐私与备份（PowerShell 脚本）
- 关闭云候选（输入内容不再上云），可用一条命令回滚
- 词库 + 注册表备份（含 SHA-256 清单）、按需还原

## 三、快速开始

```powershell
# 0) 环境体检（只读）
powershell -ExecutionPolicy Bypass -File .\scripts\Test-Environment.ps1

# 1) 备份 + 关闭云候选
powershell -ExecutionPolicy Bypass -File .\scripts\A\Backup-PinyinData.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\A\Set-PinyinPrivacy.ps1

# 2) 生成"内置已有词"剔除表（后续所有选词都靠它避免浪费额度）
python .\tools\extract_builtin_words.py

# 3) 取数据源（jieba / THUOCL / 新华词库 / 行政区划；支持代理与本地缓存）
python .\tools\fetch_sources.py --proxy http://127.0.0.1:7890

# 4) 按画像生成词表（放进 data/lexicons，转换脚本会自动扫描该目录）
python .\tools\build_profile_lexicon.py --profile .\skill\profile.example.json --out .\data\lexicons\profile-lexicon.txt
powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1 -DownloadTool

# 5) 设置里导入：时间和语言 → 语言和区域 → 中文 → 语言选项 → 微软拼音 → 词库和自学习 → 导入
```

## 四、目录结构

```
pinyin-boost/
├─ skill/
│  ├─ SKILL.md            个性化词库生成器（核心方法论）
│  ├─ sources.psd1        词源注册表（已验证源 / 检索式 / 校验清单 / 配额）
│  ├─ wordlists/          附带的 agent 整理清单（机车/游戏/黑话，需用户确认）
│  └─ profile.example.json
├─ scripts/
│  ├─ Test-Environment.ps1
│  ├─ A/  Backup-PinyinData · Set-PinyinPrivacy · Import-Lexicon · Write-LexiconFile · Restore-PinyinData
│  └─ lib/PinyinBoost.Common.psm1
├─ tools/
│  ├─ extract_builtin_words.py   从本机内置词典提取"已知词"（剔除用）
│  ├─ fetch_sources.py           下载开放数据源（缓存 + 代理）
│  ├─ build_profile_lexicon.py   画像 → 20,000 条词表（打分/配额/截断）
│  └─ merge_wordlists.py         多源合并 + 上限截断（自建词表用）
├─ docs/
│  ├─ format-and-limits.md       词库格式逆向报告 + 上限实测（本项目的核心知识）
│  ├─ runbook.md                 操作手册
│  └─ privacy.md                 数据流与隐私说明
├─ config/ · data/               配置模板 / 自备词表落位
└─ cache/ · out/                 运行产物（已 gitignore）
```

## 五、依赖

- Windows 10/11 + PowerShell 5.1
- Python 3.8+（仅 `tools/` 需要；纯标准库，除可选 `pypinyin` 用于注音）
- [imewlconverter](https://github.com/studyzy/imewlconverter)（把词表转成微软拼音原生容器；`Import-Lexicon.ps1` 会自动下载，需要 .NET 10 运行时）

## 六、许可与致谢

本项目 MIT。数据源各自许可如下（详见 `skill/sources.psd1`）：

| 来源 | 许可 |
|---|---|
| [fxsjy/jieba](https://github.com/fxsjy/jieba) | MIT |
| [thunlp/THUOCL](https://github.com/thunlp/THUOCL) | MIT |
| [pwxcoo/chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua) | MIT |
| [modood/Administrative-divisions-of-China](https://github.com/modood/Administrative-divisions-of-China) | WTFPL |
| [studyzy/imewlconverter](https://github.com/studyzy/imewlconverter) | MIT |

> 仓库内**不包含**任何词库数据或系统文件，只包含脚本、词源清单与本项目整理的小型词表；生成物一律落在 `cache/`、`out/`（已 gitignore）。
