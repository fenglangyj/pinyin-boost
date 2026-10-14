# 微软拼音词库：实测上限 + 可选用合集

本文汇总三项实测结果：词库容量上限、条目规则、以及本项目转码好的候选词库合集。

---

## 一、实测上限（本机数据，imewlconverter v3.4 + Windows 11 26300）

### 1. 条数上限：**20,000 条/份**（两个通道都是）

| 输入条数 | 自学习词库导出 | 自定义短语导出 |
|---:|---:|---:|
| 19,999 | 19,999 | 19,994 |
| 20,000 | 20,000 | 19,995 |
| 20,001 | **20,000**（过滤 1） | 19,996 |
| 25,000 | **20,000**（过滤 5,000） | **20,000**（过滤 5,000） |
| 50,000 | **20,000**（过滤 30,000） | **20,000**（过滤 30,000） |

结论：转换器在写入时就把多余条目丢掉，**20,000 是格式/工具的硬上限**，不是"每批"限制。

### 2. 文件容量与结构（自学习词库 `ChsPinyinUDL.dat`）

| 条目数 | 文件字节 | 字节/条 |
|---:|---:|---:|
| 1,000 | 69,632 | 69.6 |
| 5,000 | 309,248 | 61.9 |
| 10,000 | 609,280 | 60.9 |
| 15,000 | 909,312 | 60.6 |
| 20,000 | 1,209,344 | 60.5 |

- 稳态 **60 字节/条**，头部约 9.2–9.6 KB（随条目数缓慢增长），按 4 KB 块对齐
- 容器头结构（本机反推）：
  ```
  0x00  55 AA 88 81        magic（自学习词库容器）
  0x04  02 00 60 00        version / type
  0x08  55 AA 55 AA        分隔
  0x0C  <count>  u32 LE    ← 条目数（实测 0x4E20 = 20000）
  0x14  <time>   u32 LE    ← 写入时间
  记录自 ~0x2400 起，60 字节/条
  ```
- 自定义短语容器（`win10mspy`）magic 是 ASCII `mschxudp`，计数在 **偏移 0x1C**（实测 19,995 = `0x4E1B`）

### 3. 条目规则

| 规则 | 实测 |
|---|---|
| 字符集 | **纯中文**；含英文字母/数字/连字符/空格一律被过滤 |
| 长度 | **≤16 个汉字**（17 字、20 字均被过滤）；英文词条上限 32（帮助文本） |
| 扩展汉字 | `〇`（U+3007）可保留 |

### 4. 写入后会不会被 IME 重置？

不会。本机灌入 20,000 条后，IME 在 19:30 自行重写过一次该文件，**条数仍是 20,000、内容完整**（抽查覆盖率 97.94%，差的 412 条正是被保留在词表最前的个人词条）。说明这套"直接写入原生容器"的注入方式是稳定的。

### 5. 其它开关的影响

- `Enable Cloud Candidate = 0`（云候选关闭，隐私）
- `EnableDomainType = 0`（**专业词典已按你的要求禁用**，故以上测量不受其干扰）
- `Enable self-learning / SmartSelfLearning / Dynamic Candidate Ranking = 1`（本地学习保持开启）

---

## 二、可选用词库合集

来源全部为 **MIT 许可**：

| 来源 | 内容 | 许可 |
|---|---|---|
| [fxsjy/jieba](https://github.com/fxsjy/jieba) | 通用词表 + 词频（336,856 条可用） | MIT |
| [thunlp/THUOCL](https://github.com/thunlp/THUOCL) | 清华开放中文词库，11 个领域（IT/医学/法律/财经/饮食/汽车/动物/地名/历史名人/诗词/成语），带词频 | MIT |
| [pwxcoo/chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua) | 新华词库：成语 30,895 条、词语 264,434 条 | MIT |

### 完整清单

见 `artifacts\lexicon-pack\MANIFEST.md`（含条数、大小、说明）。文件在 `artifacts\lexicon-pack\dat\*.mspinyin.dat`，已转成微软拼音原生格式，可直接导入/写入。

重点推荐：

| 清单 | 说明 |
|---|---|
| `general-mid20k` | 通用中频词（**跳过最高频 3000 条**）——内置词库本来就认识高频词，中频才是真正的增量 |
| `combo-general-mid-it` | 通用中频 12,000 + IT 术语 8,000 |
| `combo-general-mid-medical` | 通用中频 12,000 + 医学术语 8,000 |
| `combo-general-mid-idioms` | 通用中频 12,000 + 成语 8,000 |
| `thuocl-diming` | 地名（19,999 条，接近满额） |

### 三种写入方式

```powershell
# 方式 1：官方导入（最稳，手动点几下）
powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1     # 打开设置页，手工导入
#   设置 → 时间和语言 → 语言和区域 → 中文 → 语言选项 → 微软拼音 → 词库和自学习 → 导入

# 方式 2：直接写入现成合集（自动停 IME、备份、校验魔数）
powershell -ExecutionPolicy Bypass -File .\scripts\A\Write-LexiconFile.ps1 `
  -File .\artifacts\lexicon-pack\dat\combo-general-mid-it.mspinyin.dat -IUnderstandTheRisk

# 方式 3：合并个人词条后再写入（保留你原来学到的词）
python .\tools\merge_wordlists.py --personal .\artifacts\public\personal.txt `
  --public .\artifacts\lexicon-pack\general-mid20k.txt --out .\data\lexicons\merged.txt
powershell -ExecutionPolicy Bypass -File .\scripts\A\Import-Lexicon.ps1 -Mode Direct -IUnderstandTheRisk
```

### 自己组合

```powershell
# 多个来源按顺序拼接，超 20000 自动截断
python .\tools\merge_wordlists.py --public .\artifacts\lexicon-pack\general-mid20k.txt `
  .\artifacts\lexicon-pack\thuocl-law.txt --out .\data\lexicons\merged.txt

# 或修改 tools\build_lexicon_pack.py 里的 combo() 配额，重新生成整套
python .\tools\build_lexicon_pack.py
```

---

## 三、上限能不能突破？——不能，且已定位在 IME 侧（实测）

做过的实验：

1. **容器格式已解出**：记录 = `[汉字×K(u16)][音节ID×K(u16)][学习字段]`，**60 字节定长**（K ≤ 15）；
   头部 9,228 字节（几乎全 0，**无索引表**）；**无校验和**（同一输入转两次仅差 4 字节时间戳）；
   文件大小 = `ceil((9228 + 60N) / 1024) × 1024`；条数在偏移 `0x0C`。
   其中每字 u16 = **拼音音节 ID**（值域 0~412；多音字对应多个 ID，98.5% 的字唯一确定）。
2. **构造了合法的 25,000 条容器**（基准 20,000 条 + 自行编码追加 5,000 条；自检可读回 25,000 条，尺寸公式吻合）。
3. **通过官方导入提交** → IME 只保留**前 20,000 条**，追加的 5,000 条 **0% 进入**。

→ 结论：**20,000 是 IME 强制的上限**（不是文件格式限制），改文件、改计数、追加记录都无效。

## 三之二、写入方式：直写会被回灌，官方导入才可靠（实测）

| 方式 | 结果 |
|---|---|
| 脚本直写文件（停 IME 后替换 `ChsPinyinUDL.dat`） | ❌ 几分钟内被 IME 用自有状态回灌覆盖（19,900 条 → 重合度掉到 6.9%） |
| **官方导入**（设置 → 词库和自学习 → 导入） | ✅ 稳定保持（20,000 条导入后 100% 完好，且 IME 会按拼音重排） |

因此：**推荐路径 = 生成容器 → 官方导入**。`Import-Lexicon.ps1 -Mode Prepare` 就是给这条路准备的。

## 四、注意事项

Windows 会**改名/迁移**词库文件，写死文件名会失效。本机 19:39 前后（禁用专业词典后）观察到一次迁移：

| 时间 | 变化 |
|---|---|
| ~19:30 之前 | `ChsPinyinUDL.dat`（1,181 KB，20,000 条）+ `ChsPinyinIH.dat` + Pinned/DeletedCands |
| 19:39 | 新增 `ChsPinyinEUDPv1.lex`、`ChsPinyinEUDPv2.lex`（各 106 字节，magic `mschxudp` = 自定义短语容器，空） |
| 19:43 | `ChsPinyinUDL.dat` → **`ChsPinyinUDL_Setting.dat`**（1,209,344 字节，计数仍为 20,000，内容完好） |

也就是说：

- **文件没丢**：反解 `ChsPinyinUDL_Setting.dat` 得到 20,000 条，与注入的词表交集 97.94%（差的 412 条正是保留的个人词条）
- **自学习词库的真实文件名会变**（`ChsPinyinUDL.dat` ↔ `ChsPinyinUDL_Setting.dat`）
- **自定义短语的真实容器是 `ChsPinyinEUDPv1/v2.lex`**（magic 与我们 `win10mspy` 产物一致）

因此脚本已改为**动态探测**：优先取目录下最新的 `ChsPinyinUDL*.dat`，没有才回退创建旧名 `ChsPinyinUDL.dat`（`Resolve-PinyinLexiconFiles`，`Import-Lexicon.ps1` / `Write-LexiconFile.ps1` 都已接入）。自定义短语的直写通道（`ChsPinyinEUDPv*.lex`）尚未验证，留作下一步实验。

---

## 四、注意事项

1. **一次只能激活一份**：自学习词库是单个文件，换清单 = 再写一次（旧文件会被备份到 `artifacts\backups\ChsPinyinUDL.dat-*`）。
2. **直接写入会替换现有个人词条**：个人词条已导出到 `artifacts\public\personal.txt`，需要就用"方式 3"合并。
3. **许可与再分发**：三个来源都是 MIT，但再分发作词库本体时请保留各自的 LICENSE 与出处（本项目已把 `data\`、`artifacts\` 列入 `.gitignore`，仓库里只放**生成脚本**不放数据）。
4. **词表质量**：THUOCL 带词频、jieba 带词频、新华词库不带词频（已用 jieba 词频排序补救）。
