"""stdout/stderr 统一 UTF-8（import 即生效）。

Windows 控制台默认代码页是 GBK，脚本输出被管道/agent 捕获时会乱码；
交互模式下 Python 走 WriteConsoleW，不受此处影响。
"""

import sys


def enable(streams=(sys.stdout, sys.stderr)):
    for s in streams:
        if s is not None and hasattr(s, 'reconfigure'):
            s.reconfigure(encoding='utf-8', errors='replace')


enable()
