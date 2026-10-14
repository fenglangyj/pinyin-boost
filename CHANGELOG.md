# Changelog

## [0.3.0] - 2026-10-15

端到端复跑一遍完整管线（15 个数据源全部可用 → 20,000 条词表 → 原生容器自检通过），并补齐发布前的工程质量。

### Added
- `tools/utf8_console.py`：四个 Python 工具统一 UTF-8 输出（Windows 管道/agent 捕获时中文不再乱码；交互模式走 WriteConsoleW 不受影响）
- `tests/test_selfcheck.py`：40 项仓库自检 —— 结构完整性、`.gitignore` 是否覆盖个人数据、词表纯中文 2–15 字、词源全 https + 许可记录、`.mspinyin.dat` 的 magic/计数/尺寸不变量、额度上限与去重
- `build_profile_lexicon.py` 纳入 `xinhua-idiom`（成语源，726 条）后共 15 个源参与选词；去重后可选池 548,205 条

### Fixed
- `fetch_sources.py`：同一缓存目录下多个源互相覆盖 `manifest.json`，导致 provenance 丢失 —— 改为按源 id 合并，并对已有缓存回补（标记 `cached-local`）
- `fetch_sources.py`：大文件下载无重试且 120s 超时（`idiom.json` 10MB 实测超时失败）—— 超时提到 300s、失败重试 2 次

### Verified
- `data/lexicons/profile-lexicon.txt` 20,000 条 → `profile-lexicon.mspinyin.dat` 19,996 条（转换期去重 4 条）
- 容器自检：magic `55 AA 88 81`、计数 `0x0C` = 19996、尺寸 1,209,344 = `ceil((9228+60N)/1024)*1024`

## [0.2.0] - 2026-10-14

聚焦成"个性化词库生成器"，并补齐开源结构。

### Added
- `skill/SKILL.md`：画像驱动词库生成器（能力自适应：抓不到就产出取词清单交接；provenance 标注；复测闭环）
- `skill/wordlists/`：附带的 agent 整理清单（机车/游戏/黑话，标注需用户确认）
- `skill/profile.example.json`：画像示例
- `tools/extract_builtin_words.py`：从本机内置词典提取"已知词"，用于选词时剔除（避免浪费 2 万额度）
- `tools/fetch_sources.py`：下载开放数据源（本地缓存 + 代理 + 许可记录）
- `docs/format-and-limits.md`：词库格式逆向 + 上限实测报告

### Changed
- `tools/build_profile_lexicon.py`：升级为多源 + 类别配额 + 长度加权，改成读 `cache/` 与 `skill/wordlists/`
- README 重写为开源项目首页；`.gitignore` 排除所有生成物与本机数据

### Removed
- Rime（小狼毫）相关脚本与文档（实测体验不如微软拼音，已弃用）
- 一次性研究脚本与全部运行产物

## [0.1.0] - 2026-10-14

### Added
- Route A 脚本：备份/还原词库与注册表、关闭云候选、词库导入与写入
- 编排器 `Invoke-PinyinBoost.ps1`、环境体检 `Test-Environment.ps1`、公共库 `PinyinBoost.Common.psm1`

### Findings（实测记录）
- 自学习词库容器：magic `55 AA 88 81`、计数 `0x0C`、60 字节定长记录、头部 9228 字节无索引无校验和、大小 `ceil((9228+60N)/1024)*1024`
- 每字 u16 = 拼音音节 ID（值域 0~412，多音字多值）
- 上限 20,000 条由 IME 强制（合法 25,000 条容器导入后被截断）
- 直写文件会被 IME 回灌覆盖；官方导入稳定
- 文件名会变（`ChsPinyinUDL.dat` ↔ `ChsPinyinUDL_Setting.dat` ↔ `..._Beta.dat`），必须动态探测
- 自定义短语容器 `ChsPinyinEUDPv*.lex`（magic `mschxudp`），用途是"短码 → 长文本"，不适合当词库
