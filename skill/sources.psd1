@{
    # ============================================================
    # 词源注册表 —— agent 可读、可扩展
    #   Verified=$true   已实际下载使用、许可已核对
    #   Verified=$false  仅登记线索，用前必须按 ValidationChecklist 校验
    #   provenance: verified-open | wiki | agent-curated
    # agent 允许自己往 Sources 里加源（画像派生的新域就该这么干），并把校验结果写回
    # ============================================================

    Sources = @(
        # ---------- 通用（兜底） ----------
        @{ Id='jieba-dict'; Category='general'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt'
           Cache='cache/jieba-dict/dict.txt'; Extract='col1=word,col2=freq'; Weight=1.0 }

        # ---------- 行业领域（按画像行业激活） ----------
        @{ Id='thuocl-it';      Tag='IT';        Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_IT.txt';        Cache='cache/thuocl/THUOCL_IT.txt' }
        @{ Id='thuocl-medical'; Tag='医疗';      Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_medical.txt';   Cache='cache/thuocl/THUOCL_medical.txt' }
        @{ Id='thuocl-law';     Tag='法律';      Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_law.txt';       Cache='cache/thuocl/THUOCL_law.txt' }
        @{ Id='thuocl-caijing'; Tag='金融';      Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_caijing.txt';   Cache='cache/thuocl/THUOCL_caijing.txt' }
        @{ Id='thuocl-food';    Tag='美食';      Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_food.txt';      Cache='cache/thuocl/THUOCL_food.txt' }
        @{ Id='thuocl-car';     Tag='机车/汽车'; Category='brand';  Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_car.txt';       Cache='cache/thuocl/THUOCL_car.txt'
           Note='仅 1,752 条；品牌与车型绰号需自找（见 Discovery）' }
        @{ Id='thuocl-animal';  Tag='动物';      Category='domain'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_animal.txt';    Cache='cache/thuocl/THUOCL_animal.txt' }

        # ---------- 地名 / 人物 / 诗词 / 成语 ----------
        @{ Id='divisions-streets'; Category='place'; Verified=$true; License='WTFPL'; Format='json'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/modood/Administrative-divisions-of-China/master/dist/streets.json'
           Cache='cache/divisions/streets.json'
           Note='乡级（乡镇街道）41,352 条；村级见 villages.json(84MB)。用 fetch_sources.py --province 50,51 可按省提取' }
        @{ Id='thuocl-diming';  Category='place';  Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_diming.txt';    Cache='cache/thuocl/THUOCL_diming.txt' }
        @{ Id='thuocl-people';  Category='proper'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_lishimingren.txt'; Cache='cache/thuocl/THUOCL_lishimingren.txt' }
        @{ Id='thuocl-poem';    Tag='古典诗词'; Category='poem'; Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_poem.txt';       Cache='cache/thuocl/THUOCL_poem.txt' }
        @{ Id='thuocl-idiom';   Category='idiom';  Verified=$true; License='MIT'; Format='tsv'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/thunlp/THUOCL/master/data/THUOCL_chengyu.txt';    Cache='cache/thuocl/THUOCL_chengyu.txt'
           Note='成语内置覆盖接近 100%，配额要压低' }
        @{ Id='xinhua-idiom';   Category='idiom';  Verified=$true; License='MIT'; Format='json'; Extract='field=word'; provenance='verified-open'
           Url='https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/data/idiom.json';    Cache='cache/xinhua/idiom.json' }
        @{ Id='xinhua-ci';      Category='general';Verified=$true; License='MIT'; Format='json'; Extract='field=ci';   provenance='verified-open'
           Url='https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/data/ci.json';       Cache='cache/xinhua/ci.json' }

        # ---------- 本仓库附带（agent 整理，需用户确认） ----------
        @{ Id='wl-bike';   Category='brand'; Verified=$true; License='MIT(本项目)'; Format='txt'; provenance='agent-curated'
           Cache='skill/wordlists/bike-zh.txt';   Note='机车品牌/车型绰号/装备/黑话；**请用户确认**' }
        @{ Id='wl-games';  Category='media'; Verified=$true; License='MIT(本项目)'; Format='txt'; provenance='agent-curated'
           Cache='skill/wordlists/games-zh.txt';  Note='常见游戏中文名；**请用户确认**' }
        @{ Id='wl-slang';  Category='slang'; Verified=$true; License='MIT(本项目)'; Format='txt'; provenance='agent-curated'
           Cache='skill/wordlists/slang-zh.txt';  Note='官方年度十大流行语 + 常见网络用语；**请用户确认**' }
    )

    # ============================================================
    # Discovery —— 现成词库找不到时的找词指引（抓不到就产出取词单，见 SKILL.md §3.3）
    # ============================================================
    Discovery = @{
        QueryTemplates = @(
            '<领域> 术语 大全',
            '<品牌> 车型 中文名 列表',
            '<车型> 绰号 外号 叫什么',
            '<城市> 街道 乡镇 名录 区划代码',
            '<年份> 网络流行语 年度 十大',
            '<圈层> 黑话 用语 行话',
            'site:zh.wikipedia.org <主题> 列表',
            '<游戏> 角色 名称 列表 中文'
        )

        OpenEndpoints = @(
            @{ Id='wikidata-sparql'; License='CC0'; Verified=$false
               Url='https://query.wikidata.org/sparql?format=json&query=<URL编码SPARQL>'
               Note='按中文标签批量取实体名（游戏/影视/车型/品牌/人物），适合长尾专名' }
            @{ Id='wikipedia-category'; License='CC BY-SA'; Verified=$true
               Url='https://zh.wikipedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:<分类>&cmlimit=500&format=json'
               Note='实测可用但覆盖稀疏；适合当补充源' }
            @{ Id='stats-gov-divisions'; License='政府公开数据'; Verified=$false
               Note='国家统计局统计用区划代码（含乡镇/村级），可抓取性待核实' }
        )

        DomainHints = @{
            '机车/摩旅' = '品牌中文名（钱江/无极/春风/豪爵/隆鑫/本田/雅马哈/川崎/凯旋/杜卡迪…）、车型绰号（水鸟/金翼/小忍者…）、装备（头盔/骑行服/边箱/尾箱/风挡）、圈内黑话；来源：品牌官网中文页、车友社区、维基分类、WikiData'
            '程序员'     = '技术术语中文名、框架/工具中文名、大厂与产品中文简称、岗位黑话；来源：THUOCL_IT + 技术社区 + WikiData'
            '游戏'       = '游戏名、角色名、装备/技能名、游戏黑话；来源：WikiData（电子游戏）+ 游戏百科分类'
            '影视'       = '剧名、角色名、演员名、梗；来源：WikiData + 影视资料站分类'
            '新词/黑话'  = '年度网络用语、平台热榜词、圈层黑话；来源：官方年度榜单、平台公开热榜、社区整理帖'
            '地名长尾'   = '本市/区的乡镇、街道、村、社区、景区、服务区、加油站；来源：行政区划开放数据 + 地图 POI（注意条款）'
        }
    }

    ValidationChecklist = @(
        'URL 可达（HTTP 200 且内容长度合理）',
        '许可明确（MIT / CC0 / CC BY-SA / WTFPL / 公共领域），许可不明一律不用',
        '编码可识别（UTF-8 / GBK / UTF-16），解析出的词条抽样 20 条无乱码',
        '纯中文词条比例 ≥ 80%',
        '与内置已知词重复率有记录；重复率 > 90% 的源不采用',
        '把校验结果写回本注册表的 Verified 与 Note'
    )

    ExcludeBuiltin = @(
        'cache/builtin/builtin-domain-words.txt'   # 49 个专业词典（由 tools/extract_builtin_words.py 生成）
        'cache/builtin/builtin-phrase-words.txt'   # 内置短语（同上）
    )

    QuotaRatio = @{
        private  = '优先占位，不限'
        domain   = 0.25
        proper   = 0.15
        place    = 0.15
        general  = 0.20
        brand    = 0.10
        phrase   = 0.10
        idiom    = 0.05    # 内置覆盖接近 100%，刻意压低
    }
}
