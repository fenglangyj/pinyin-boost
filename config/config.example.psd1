<#
    pinyin-boost 配置模板。

    复制为 config.psd1 后修改（config.psd1 已被 gitignore，本机配置不会外泄）。
#>
@{
    # auto | lowspec | full —— 目前只影响提示信息与默认值
    Profile = 'auto'

    Network = @{
        # 下载/克隆使用的 HTTP 代理；留空自动探测（环境变量 → 本机 7890/10809/1080）
        Proxy = ''
    }

    Pinyin = @{
        # 隐私：关闭云候选（输入内容不再上云给微软）；本地自学习与动态词频保持开启
        DisableCloudCandidate = $true
        KeepSelfLearning      = $true
        KeepDynamicRanking    = $true
    }

    Lexicon = @{
        # imewlconverter 输出格式 id（v3.4 实测）：
        #   win10mspyss - 微软拼音自学习词库（导入这个）
        #   win10mspy   - 微软拼音用户自定义短语
        OutputFormat = 'win10mspyss'
        # 留空按扩展名自动推断（.scel→scel、.txt→word…）
        InputFormat  = ''
        # 单批条数上限提示值（IME 实际硬上限 20000，超出会被截断）
        SplitLines   = 20000
        # 缺少 imewlconverter 时自动下载
        DownloadTool = $true
    }
}
