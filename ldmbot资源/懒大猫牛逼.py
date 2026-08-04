try:
    import random
    import time
    import sys
    import os
    
    # 判断操作系统
    if os.name == 'nt':      # Windows
        os.system('cls')
    else:                    # Linux / macOS
        os.system('clear')
    
    # ========== 原始艺术字与颜色定义 ==========
    ldmnb = r"""
         __          ______       __    __     __    __     _______ 
        |  |        |       \    |  \  /  |   |  \  |  |   |   _   \
        |  |        |  .--.  |   |   \/   |   |   \ |  |   |  |_)  |
        |  |        |  |  |  |   |        |   |    \|  |   |   _  < 
        |  `----.   |  '--'  |   |  |\/|  |   |  |\    |   |  |_)  |
        |_______|   |_______/    |__|  |__|   |__| \___|   |_______/
    """
    ldmbot = r"""
         __          ______      __    __    _______      ____      _________
        |  |        |       \   |  \  /  |  |   _   \    /    \    |___   ___|
        |  |        |  .--.  |  |   \/   |  |  |_)  |   /  __  \       |  |
        |  |        |  |  |  |  |        |  |   _  <   |  |  |  |      |  |
        |  `----.   |  '--'  |  |  |\/|  |  |  |_)  |   \  `'  /       |  |
        |_______|   |_______/   |__|  |__|  |_______/    \____/        |__|
    """
    
    # 基础颜色
    red     = "\033[31m"
    green   = "\033[32m"
    yellow  = "\033[33m"
    blue    = "\033[34m"
    purple  = "\033[35m"
    cyan    = "\033[36m"
    reset   = "\033[0m"
    
    # 亮色（高亮）版本
    bright_red     = "\033[1;31m"
    bright_green   = "\033[1;32m"
    bright_yellow  = "\033[1;33m"
    bright_blue    = "\033[1;34m"
    bright_purple  = "\033[1;35m"
    bright_cyan    = "\033[1;36m"
    
    # ========== 检测终端是否支持颜色 ==========
    def supports_color():
        if not sys.stdout.isatty():
            return False
        if os.environ.get('TERM') == 'dumb':
            return False
        if os.environ.get('NO_COLOR'):
            return False
        # 这里可以加入更精确的 Windows 判断，简单起见认为现代 Windows 终端都支持
        return True
    
    if not supports_color():
        # 不支持颜色时，将所有颜色代码清空，保留动画
        red = green = yellow = blue = purple = cyan = ""
        bright_red = bright_green = bright_yellow = bright_blue = bright_purple = bright_cyan = ""
        reset = ""
        # 重新构建列表，确保里面也是空字符串
        dark_colors = [red, green, yellow, blue, purple, cyan]
        bright_colors = [bright_red, bright_green, bright_yellow, bright_blue, bright_purple, bright_cyan]
    else:
        dark_colors = [red, green, yellow, blue, purple, cyan]
        bright_colors = [bright_red, bright_green, bright_yellow, bright_blue, bright_purple, bright_cyan]
    
    # ============================================
    
    def print_art_column_by_column(art, delay=0.03, start_row=1, extra_arts=None):
        """
        从左到右逐列彩色显示艺术字。
        如果提供了 extra_arts（列表，元素为 (start_row, rows, cols, padded_lines)），
        则每一帧都会先以随机颜色重绘这些额外的艺术字，从而让它们保持动态颜色闪烁。
        返回 (rows, cols, padded_lines)。
        """
        lines = art.split('\n')
        if lines and lines[0] == '':
            lines = lines[1:]
        if lines and lines[-1] == '':
            lines = lines[:-1]
    
        rows = len(lines)
        cols = max(len(line) for line in lines)
        padded = [line.ljust(cols) for line in lines]
    
        sys.stdout.write("\033[?25l")   # 隐藏光标
        sys.stdout.flush()
    
        try:
            for c in range(cols):
                # 1. 如果有额外的艺术字，先以随机颜色完整重绘它们
                if extra_arts:
                    for (sr, erows, ecols, epadded) in extra_arts:
                        for r in range(erows):
                            sys.stdout.write(f"\033[{sr + r};1H")
                            for cc in range(ecols):
                                ch = epadded[r][cc]
                                if ch == ' ':
                                    sys.stdout.write(' ')
                                else:
                                    color = random.choice(bright_colors + dark_colors)
                                    sys.stdout.write(f"{color}{ch}")
                            sys.stdout.write(reset)
    
                # 2. 绘制当前艺术字的第 0..c 列
                for r in range(rows):
                    sys.stdout.write(f"\033[{start_row + r};1H")
                    for cc in range(c + 1):
                        ch = padded[r][cc]
                        if ch == ' ':
                            sys.stdout.write(' ')
                        else:
                            color = random.choice(bright_colors + dark_colors)
                            sys.stdout.write(f"{color}{ch}")
                sys.stdout.write(reset)
                sys.stdout.flush()
                time.sleep(delay)
    
            # 最后光标移动到整体下方
            sys.stdout.write(f"\033[{start_row + rows};1H\n")
        finally:
            sys.stdout.write("\033[?25h")
            sys.stdout.flush()
    
        return rows, cols, padded
    
    
    def flash_unified_bright_dark(art_info_list, total_duration=3, interval=0.1):
        """
        整体闪烁：所有艺术字统一颜色，一亮一暗交替
        art_info_list: [(start_row, rows, cols, padded_lines), ...]
        """
        sys.stdout.write("\033[?25l")
        sys.stdout.flush()
        start_time = time.time()
    
        use_bright = True
    
        try:
            while time.time() - start_time < total_duration:
                if use_bright:
                    color = random.choice(bright_colors)
                else:
                    color = random.choice(dark_colors)
    
                for (start_row, rows, cols, padded) in art_info_list:
                    for r in range(rows):
                        sys.stdout.write(f"\033[{start_row + r};1H")
                        for c in range(cols):
                            ch = padded[r][c]
                            if ch == ' ':
                                sys.stdout.write(' ')
                            else:
                                sys.stdout.write(f"{color}{ch}")
                        sys.stdout.write(reset)
                sys.stdout.flush()
    
                use_bright = not use_bright
                time.sleep(interval)
        finally:
            sys.stdout.write("\033[?25h")
            sys.stdout.flush()
    
    
    # ========== 执行流程 ==========
    lines_ldmnb = [line for line in ldmnb.split('\n') if line != '']
    rows_first = len(lines_ldmnb)
    
    # 1. 第一个艺术字（此时 extra_arts 为空）
    info1 = print_art_column_by_column(ldmnb, delay=0.03, start_row=1)
    
    # 2. 第二个艺术字（传入第一个艺术字的完整信息，使其在打印过程中持续五颜六色交替）
    extra_art = (1, info1[0], info1[1], info1[2])   # start_row=1
    info2 = print_art_column_by_column(ldmbot, delay=0.03, start_row=rows_first + 2, extra_arts=[extra_art])
    
    # 3. 统一颜色、亮暗交替闪烁 3 秒
    flash_unified_bright_dark(
        [
            (1, info1[0], info1[1], info1[2]),
            (rows_first + 2, info2[0], info2[1], info2[2])
        ],
        total_duration=3,
        interval=0.12
    )
    
    # 4. 光标下移，结束
    total_rows = max(1, rows_first + 2 + info2[0])
    sys.stdout.write(f"\033[{total_rows + 1};1H\n")
except:
    exit(0)