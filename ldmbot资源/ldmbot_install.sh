#!/bin/bash

# ------------------------------------------------------------
# 提示：安装程序将从 GitHub Releases 自动下载 ldmbot.zip
# ------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------
# ldmbot 安装脚本
# ------------------------------------------------------------

DOWNLOAD_URL="https://github.com/landamao/ldm_AstrBot/releases/latest/download/ldmbot.zip"

# 自动检测代理的预设端口（非交互模式时使用）
PROXY_PORTS=(7890 7897)

# 公共 GitHub 代理列表（参考 NapCat 安装脚本 network_test）
GH_PROXY_LIST=(
    "https://ghfast.top"
    "https://gh.wuliya.xin"
    "https://gh-proxy.com"
    "https://github.moeyy.xyz"
)

# 颜色定义
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

# 解析脚本绝对路径
[[ "$0" = /* ]] && SCRIPT_PATH="$0" || SCRIPT_PATH="$PWD/$0"

# ---------- 记录脚本启动时的原始目录 ----------
ORIG_DIR="$(pwd)"

# ---------- 选项解析 ----------
AUTO_YES=false
AUTO_UPDATE=false
SKIP_SYNC=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -up|--update)
            AUTO_UPDATE=true
            AUTO_YES=true
            shift
            ;;
        --no-sync|-ns)
            SKIP_SYNC=true
            shift
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            exit 1
            ;;
    esac
done

# ---------- 辅助函数 ----------
prompt_continue() {
    if $AUTO_YES; then return 0; fi
    local msg="${1:-按回车键继续，或按 Ctrl+C 取消...}"
    read -p "$msg" < /dev/tty
}

ask_yes_no() {
    if $AUTO_YES; then return 0; fi
    local prompt="$1"
    local answer
    # 强制从终端读取，防止在子shell $() 中卡死
    read -p "${prompt} [Y/n] " answer < /dev/tty
    [[ "$answer" =~ ^[Nn] ]] && return 1 || return 0
}

test_proxy() {
    local port=$1
    curl -x "http://127.0.0.1:${port}" -s --connect-timeout 5 --max-time 10 \
        "http://httpbin.org/ip" > /dev/null 2>&1
}

# 测试公共 GitHub 代理可用性（参考 napcat.sh network_test）
# 成功时设置 TARGET_GH_PROXY 为可用代理前缀，失败时置空
network_test_github() {
    local timeout=10
    local status=0
    local found=0
    TARGET_GH_PROXY=""
    >&2 echo -e "${YELLOW}开始测试公共 GitHub 代理...${NC}"

    local check_url="https://raw.githubusercontent.com/landamao/ldm_AstrBot/main/README.md"
    local proxy
    for proxy in "${GH_PROXY_LIST[@]}"; do
        >&2 echo -e "${YELLOW}测试代理: ${proxy}${NC}"
        status=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout*2)) \
            -o /dev/null -s -w "%{http_code}" "${proxy}/${check_url}" 2>/dev/null || true)
        if [ "${status}" = "200" ]; then
            found=1
            TARGET_GH_PROXY="${proxy}"
            >&2 echo -e "${GREEN}将使用 GitHub 代理: ${proxy}${NC}"
            break
        else
            >&2 echo -e "${YELLOW}代理 ${proxy} 不可用 (HTTP ${status:-超时})${NC}"
        fi
    done

    if [ ${found} -eq 0 ]; then
        >&2 echo -e "${YELLOW}警告: 未找到可用的公共 GitHub 代理，将尝试直连...${NC}"
        TARGET_GH_PROXY=""
    fi
}

# 用 curl/wget 下载到临时文件；成功返回 0
# 参数: $1=最终下载 URL  $2=输出路径  [$3=可选 curl 额外参数，如 -x http://...]
_download_to_tmp() {
    local url="$1"
    local out="$2"
    shift 2
    # 剩余参数作为 curl 额外选项
    if curl "$@" -k -L -o "$out" "$url" --connect-timeout 15 --max-time 300 2>/dev/null; then
        # 简单校验：文件非空
        [[ -s "$out" ]] && return 0
    fi
    return 1
}

ensure_unzip() {
    if command -v unzip &>/dev/null; then return 0; fi
    echo -e "${YELLOW}未找到 unzip 命令，尝试安装...${NC}"
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y unzip || { echo -e "${RED}安装 unzip 失败。${NC}"; exit 1; }
    elif command -v yum &>/dev/null; then
        sudo yum install -y unzip || { echo -e "${RED}安装 unzip 失败. ${NC}"; exit 1; }
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y unzip || { echo -e "${RED}安装 unzip 失败。${NC}"; exit 1; }
    elif command -v brew &>/dev/null; then
        brew install unzip || { echo -e "${RED}安装 unzip 失败。${NC}"; exit 1; }
    else
        echo -e "${RED}无法自动安装 unzip。请手动安装 unzip 后重试。${NC}"; exit 1
    fi
}

# ---------- 下载 ldmbot.zip 函数（改为始终操作原始目录）----------
# 优先级：本地 HTTP 代理 → 公共 GitHub 代理 → 直连
download_ldmbot_zip() {
    local target_zip="${ORIG_DIR}/ldmbot.zip"    # 固定使用原始目录下的文件
    local tmp_zip="${target_zip}.tmp"
    local use_http_proxy=false
    local http_proxy_port=""
    local use_gh_proxy=false
    TARGET_GH_PROXY=""

    >&2 echo -e "\n${GREEN}=============================${NC}"
    >&2 echo -e "${GREEN}        下载 ldmbot 源码        ${NC}"
    >&2 echo -e "${GREEN}=============================${NC}\n"
    # 清理可能残留的临时文件
    rm -f "$tmp_zip"

    # 检查原始目录下是否已有文件
    if [[ -f "$target_zip" ]]; then
        >&2 echo -e "\n${YELLOW}检测到脚本启动目录（${ORIG_DIR}）下已存在 ldmbot.zip。${NC}"
        if ask_yes_no "是否直接使用已存在的 ldmbot.zip？"; then
            >&2 echo -e "${GREEN}-> 使用已存在的 ldmbot.zip (位于 ${ORIG_DIR})${NC}"
            echo "$target_zip"
            return
        fi
        # 用户选择重新下载，暂不删除旧文件，等下载成功后再替换
    fi

    >&2 echo -e "\n${YELLOW}开始下载最新 ldmbot.zip 到目录：脚本启动目录 ${ORIG_DIR}\n下载地址：${DOWNLOAD_URL}\n如无法下载，可手动下载到该目录，然后重新执行脚本\n${NC}"

    # ---------- 交互模式：先问 HTTP 代理，不用再问公共 GitHub 代理 ----------
    if ! $AUTO_YES && [ -t 0 ]; then
        if ask_yes_no "是否使用本地 HTTP 代理下载？"; then
            read -p "请输入代理端口（如 7890）: " proxy_port < /dev/tty
            if [[ "$proxy_port" =~ ^[0-9]+$ ]]; then
                use_http_proxy=true
                http_proxy_port="$proxy_port"
            else
                >&2 echo -e "${YELLOW}无效端口，跳过本地 HTTP 代理。${NC}"
            fi
        else
            # 不用本地 HTTP 代理时，再询问是否使用公共 GitHub 代理
            if ask_yes_no "是否使用公共 GitHub 代理下载？（国内网络环境推荐）"; then
                use_gh_proxy=true
            fi
        fi
    # ---------- 非交互模式：自动检测本地端口，失败再测公共代理 ----------
    else
        for port in "${PROXY_PORTS[@]}"; do
            if test_proxy "$port"; then
                use_http_proxy=true
                http_proxy_port="$port"
                >&2 echo -e "${GREEN}检测到本地代理端口 ${port}${NC}"
                break
            fi
        done
        if ! $use_http_proxy; then
            use_gh_proxy=true
            >&2 echo -e "${YELLOW}未检测到本地 HTTP 代理，将尝试公共 GitHub 代理...${NC}"
        fi
    fi

    # ---------- 1) 本地 HTTP 代理下载 ----------
    if $use_http_proxy && [[ -n "$http_proxy_port" ]]; then
        >&2 echo -e "${GREEN}尝试通过本地代理 127.0.0.1:${http_proxy_port} 下载...${NC}"
        if _download_to_tmp "$DOWNLOAD_URL" "$tmp_zip" -x "http://127.0.0.1:${http_proxy_port}"; then
            >&2 echo -e "${GREEN}下载完成（本地 HTTP 代理）${NC}"
            mv "$tmp_zip" "$target_zip"
            echo "$target_zip"
            return
        fi
        >&2 echo -e "${RED}本地 HTTP 代理下载失败。${NC}"
        # 交互模式下 HTTP 失败后，再询问是否用公共代理
        if ! $AUTO_YES && [ -t 0 ]; then
            if ask_yes_no "本地代理失败，是否改用公共 GitHub 代理？"; then
                use_gh_proxy=true
            fi
        else
            use_gh_proxy=true
        fi
    fi

    # ---------- 2) 公共 GitHub 代理下载 ----------
    if $use_gh_proxy; then
        network_test_github
        if [[ -n "$TARGET_GH_PROXY" ]]; then
            local gh_url="${TARGET_GH_PROXY}/${DOWNLOAD_URL}"
            >&2 echo -e "${GREEN}尝试通过公共代理下载: ${gh_url}${NC}"
            if _download_to_tmp "$gh_url" "$tmp_zip"; then
                >&2 echo -e "${GREEN}下载完成（公共 GitHub 代理: ${TARGET_GH_PROXY}）${NC}"
                mv "$tmp_zip" "$target_zip"
                echo "$target_zip"
                return
            fi
            >&2 echo -e "${RED}公共 GitHub 代理下载失败，将尝试直连...${NC}"
        fi
    fi

    # ---------- 3) 直连下载 ----------
    >&2 echo -e "${YELLOW}使用直连下载...${NC}"
    if _download_to_tmp "$DOWNLOAD_URL" "$tmp_zip"; then
        >&2 echo -e "${GREEN}下载完成（直连）${NC}"
        mv "$tmp_zip" "$target_zip"
        echo "$target_zip"
        return
    elif command -v wget &>/dev/null && wget -O "$tmp_zip" "$DOWNLOAD_URL" --timeout=30 2>/dev/null && [[ -s "$tmp_zip" ]]; then
        >&2 echo -e "${GREEN}下载完成（wget 直连）${NC}"
        mv "$tmp_zip" "$target_zip"
        echo "$target_zip"
        return
    else
        >&2 echo -e "${RED}下载 ldmbot.zip 失败，已保留原有文件（如有）。${NC}"
        rm -f "$tmp_zip"
        exit 1
    fi
}

# ====== 更新 ldmbot 函数 ======
update_ldmbot() {
    local interactive=$1
    echo -e "\n${GREEN}=============================${NC}"
    echo -e "${GREEN}        更新 ldmbot        ${NC}"
    echo -e "${GREEN}=============================${NC}\n"
    
    echo "正在搜索标志目录 astrbot/builtin_stars/astrbot/ldm ..."
    local search_results
    search_results=$( { find ~/ -type d -path "*astrbot/builtin_stars/astrbot/ldm" 2>/dev/null || true; } | sed 's|/astrbot/builtin_stars/astrbot/ldm$||' | sort -u )
    if [[ -z "$search_results" ]]; then
        echo -e "${RED}未找到包含 astrbot/builtin_stars/astrbot/ldm 的目录。${NC}"
        exit 1
    fi

    readarray -t candidates <<< "$search_results"
    local target_dir=""
    if $interactive; then
        echo -e "\n${YELLOW}找到以下可能的 ldmbot 根目录：${NC}"
        local i=1
        for dir in "${candidates[@]}"; do
            echo "  $i) $dir"
            ((i++))
        done
        echo
        while true; do
            read -p "请选择序号（或输入 0 退出）: " choice < /dev/tty
            if [[ "$choice" == "0" ]]; then
                echo -e "${YELLOW}已取消更新。${NC}"
                exit 0
            elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
                target_dir="${candidates[$((choice-1))]}"
                break
            else
                echo -e "${RED}无效选择。${NC}"
            fi
        done
    else
        if [[ ${#candidates[@]} -eq 1 ]]; then
            target_dir="${candidates[0]}"
            echo -e "${GREEN}检测到唯一目标目录：${target_dir}${NC}"
        else
            echo -e "${RED}错误：检测到多个可能的目标目录，无法进行自动更新，请手动运行脚本。${NC}"
            echo "找到的目录："
            for dir in "${candidates[@]}"; do
                echo "  - $dir"
            done
            exit 1
        fi
    fi

    # 先展示目标目录内容（尚未 cd）
    echo -e "\n${GREEN}目标目录：${target_dir}${NC}"
    ls "$target_dir"
    echo

    if $interactive; then
        if ! ask_yes_no "请检查文件内容，应包含 astrbot、main.py 等文件，是否确认？"; then
            echo -e "${YELLOW}已取消。${NC}"
            exit 0
        fi
    else
        echo -e "${GREEN}开始自动更新...${NC}"
    fi

    # ---------- 在原始目录下获取 ZIP（仍在原目录） ----------
    local downloaded_zip
    downloaded_zip=$(download_ldmbot_zip)

    # ---------- 进入目标目录进行替换 ----------
    cd "$target_dir" || { echo -e "${RED}无法进入目录。${NC}"; exit 1; }

    local tmp_extract=$(mktemp -d)
    ensure_unzip
    
    echo -e "${YELLOW}正在解压并验证文件结构...${NC}"
    if ! unzip -o "$downloaded_zip" -d "$tmp_extract" >/dev/null; then
        echo -e "${RED}解压 ldmbot.zip 失败，可能是文件损坏或磁盘空间不足。${NC}"
        rm -rf "$tmp_extract"
        exit 1
    fi

    # 验证解压结构
    if [[ ! -d "$tmp_extract/ldmbot" ]]; then
        echo -e "${RED}错误，解压后未找到 ldmbot 目录，失败，请尝试重新执行脚本${NC}"
        rm -rf "$tmp_extract"
        exit 1
    fi

    # 删除旧文件并替换
    echo -e "${GREEN}清理旧程序文件（astrbot 和 data/dist）...${NC}"
    rm -rf astrbot data/dist 2>/dev/null || true

    echo -e "${GREEN}正在覆盖更新文件...${NC}"
    cp -rf "$tmp_extract/ldmbot/." .
    
    # 清理临时解压目录（保留原始目录下的 zip 文件）
    rm -rf "$tmp_extract"

    echo -e "\n${GREEN}=============================${NC}"
    echo -e "${GREEN}      ldmbot 更新完成！      ${NC}"
    echo -e "${GREEN}=============================${NC}"
    echo -e "${YELLOW}提示：文件已更新，请手动重启 ldmbot 使其生效。${NC}"
    echo -e "${YELLOW}（例如: systemctl restart ldmbot 或通过 WebUI 面板设置页面重启）${NC}\n"
    exit 0
}

# 若为更新模式，直接调用并退出
if $AUTO_UPDATE; then
    update_ldmbot false
    exit 0
fi

INSTALL_DEPS=true
if $SKIP_SYNC; then
    INSTALL_DEPS=false
fi

install_python3_12() {
    echo "正在尝试自动安装 Python 3.12..."
    if command -v apt-get &>/dev/null; then
        sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
        sudo apt-get update -qq
        sudo apt-get install -y python3.12 python3.12-venv python3.12-distutils
    elif command -v yum &>/dev/null; then
        sudo yum install -y python3.12 || true
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y python3.12 || true
    elif command -v brew &>/dev/null; then
        brew install python@3.12
    else
        echo -e "${RED}无法自动安装 Python，请手动安装 Python 3.12+。${NC}"
        exit 1
    fi
}

try_direct_run() {
    if [[ ! -d ldmbot ]]; then
        echo -e "${RED}没有可用的 ldmbot 项目文件，无法直接启动。${NC}"
        exit 1
    fi
    cd ldmbot
    if command -v uv &>/dev/null && [[ -f pyproject.toml ]]; then
        echo -e "${GREEN}使用 uv 启动...${NC}"
        exec uv run main.py
    elif [[ -d .venv ]]; then
        echo -e "${GREEN}使用虚拟环境中的 python 启动...${NC}"
        source .venv/bin/activate
        exec python main.py
    elif command -v python3 &>/dev/null; then
        echo -e "${YELLOW}尝试直接使用系统 python3 启动...${NC}"
        exec python3 main.py
    else
        echo -e "${RED}无法找到可用的启动方式，请选择重新安装。${NC}"
        exit 1
    fi
}

# ====== 全新安装 ldmbot（从 1.old.sh 提取，ZIP 改为下载） ======
install_ldmbot() {
    echo -e "\n${GREEN}=== 安装 ldmbot ===${NC}"

    # 始终在脚本启动目录安装
    cd "$ORIG_DIR" || { echo -e "${RED}无法进入启动目录：${ORIG_DIR}${NC}"; exit 1; }

    if [[ -d ldmbot ]]; then
        echo -e "${YELLOW}检测到已存在的 ldmbot 目录。${NC}"
        # -y 非更新模式：已有 main.py 则直接尝试启动，否则覆盖安装
        if $AUTO_YES && ! $AUTO_UPDATE; then
            if [[ -f ldmbot/main.py ]]; then
                echo -e "${GREEN}检测到 ldmbot/main.py，-y 模式下直接尝试启动...${NC}"
                try_direct_run
                return
            fi
            echo -e "${YELLOW}未找到 ldmbot/main.py，将覆盖安装...${NC}"
        elif ! ask_yes_no "是否覆盖安装（解压覆盖现有文件）？"; then
            echo -e "${YELLOW}已取消安装。${NC}"
            exit 0
        fi
    fi

    # 0. 下载并解压
    echo -e "\n${GREEN}[步骤 0/6] 正在获取并解压 ldmbot 压缩包...${NC}\n"
    local downloaded_zip
    downloaded_zip=$(download_ldmbot_zip)
    ensure_unzip
    if ! unzip -o "$downloaded_zip" -d "$ORIG_DIR" >/dev/null; then
        echo -e "${RED}解压 ldmbot.zip 失败。${NC}"
        exit 1
    fi
    if [[ ! -d "$ORIG_DIR/ldmbot" ]]; then
        echo -e "${RED}解压后未找到 ldmbot 目录，请检查压缩包。${NC}"
        exit 1
    fi
    prompt_continue "压缩包解压完成，按回车继续配置环境..."

    # 1. 代理设置（用于后续 uv / pip 下载依赖）
    echo -e "\n${GREEN}[步骤 1/6] 代理设置...${NC}\n"
    PROXY_PORT=""

    if $AUTO_YES; then
        for port in "${PROXY_PORTS[@]}"; do
            if test_proxy "$port"; then
                PROXY_PORT="$port"
                break
            fi
        done
        if [[ -n "$PROXY_PORT" ]]; then
            echo -e "${GREEN}检测到可用代理端口：${PROXY_PORT}${NC}"
            if ask_yes_no "是否启用代理？"; then
                export http_proxy="http://127.0.0.1:${PROXY_PORT}"
                export https_proxy="http://127.0.0.1:${PROXY_PORT}"
                export all_proxy="http://127.0.0.1:${PROXY_PORT}"
                echo -e "${GREEN}已启用代理。${NC}\n"
            else
                echo -e "${YELLOW}已选择不启用代理。${NC}\n"
            fi
        else
            echo -e "${YELLOW}警告：未检测到可用代理，下载可能较慢。${NC}"
            prompt_continue "按回车继续..."
        fi
    else
        if ask_yes_no "是否使用代理端口？（用于加速依赖下载）"; then
            while true; do
                read -p "请输入代理端口号（例如 7890，直接回车使用 7890）: " custom_port < /dev/tty
                custom_port=${custom_port:-7890}
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
                    if test_proxy "$custom_port"; then
                        PROXY_PORT="$custom_port"
                        echo -e "${GREEN}代理端口 ${PROXY_PORT} 连接成功。${NC}"
                        break
                    else
                        echo -e "${RED}端口 ${custom_port} 不可用，请检查代理是否已开启。${NC}"
                        if ! ask_yes_no "是否重新输入？"; then
                            echo -e "${YELLOW}跳过代理设置。${NC}"
                            PROXY_PORT=""
                            break
                        fi
                    fi
                else
                    echo -e "${RED}无效端口号。${NC}"
                    if ! ask_yes_no "是否重新输入？"; then
                        echo -e "${YELLOW}跳过代理设置。${NC}"
                        PROXY_PORT=""
                        break
                    fi
                fi
            done
            if [[ -n "$PROXY_PORT" ]]; then
                export http_proxy="http://127.0.0.1:${PROXY_PORT}"
                export https_proxy="http://127.0.0.1:${PROXY_PORT}"
                export all_proxy="http://127.0.0.1:${PROXY_PORT}"
                echo -e "${GREEN}已启用代理。${NC}\n"
            fi
        else
            echo -e "${YELLOW}已选择不使用代理。${NC}\n"
        fi
    fi

    # 2. uv 检查
    echo -e "\n${GREEN}[步骤 2/6] 检查 uv 包管理器...${NC}\n"
    USE_UV=false
    if command -v uv &>/dev/null; then
        USE_UV=true
        echo -e "${GREEN}已找到 uv：$(which uv)${NC}\n"
    else
        echo -e "${YELLOW}未找到 uv。${NC}"
        prompt_continue "按回车自动安装 uv..."
        if curl -LsSf https://astral.sh/uv/install.sh | sh; then
            export PATH="$HOME/.local/bin:$PATH"
            command -v uv &>/dev/null && USE_UV=true && echo -e "${GREEN}uv 安装成功。${NC}\n" || echo -e "${YELLOW}uv 不在 PATH 中。${NC}\n"
        else
            echo -e "${YELLOW}uv 安装失败。${NC}\n"
        fi
    fi

    # 进入项目目录
    cd "$ORIG_DIR/ldmbot" || { echo -e "${RED}无法进入 ldmbot 目录。${NC}"; exit 1; }

    # 3. uv sync 询问与执行
    if $USE_UV; then
        if $SKIP_SYNC; then
            echo -e "\n${YELLOW}已通过 --no-sync 跳过 uv sync。直接尝试启动...${NC}\n"
            exec uv run main.py
        fi

        if ! $AUTO_YES; then
            if ask_yes_no "是否运行 uv sync 安装/更新依赖？"; then
                INSTALL_DEPS=true
            else
                INSTALL_DEPS=false
                echo -e "${YELLOW}跳过 uv sync。直接尝试启动...${NC}"
            fi
        else
            INSTALL_DEPS=true
        fi

        if $INSTALL_DEPS; then
            echo -e "\n${GREEN}[步骤 3/6] uv sync 并启动...${NC}\n"
            if uv sync; then
                echo -e "${GREEN}通过 uv 启动...${NC}\n"
                exec uv run main.py
            fi
            echo -e "${YELLOW}uv sync 失败，回退到 pip。${NC}"
            prompt_continue "按回车继续..."
        else
            exec uv run main.py
        fi
    fi

    # 4. 回退：pip + Python ≥ 3.12
    echo -e "\n${GREEN}[步骤 4/6] 准备 pip 环境...${NC}\n"

    if ! $USE_UV && ! $AUTO_YES && $INSTALL_DEPS; then
        if ! ask_yes_no "是否使用 pip 安装依赖？"; then
            INSTALL_DEPS=false
            echo -e "${YELLOW}跳过依赖安装。${NC}"
        fi
    fi

    PYTHON_CMD=""
    if command -v python3.12 &>/dev/null; then
        PYTHON_CMD="python3.12"
    elif command -v python3 &>/dev/null; then
        python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' && PYTHON_CMD="python3"
    fi

    if [[ -z "$PYTHON_CMD" ]]; then
        echo -e "${YELLOW}未找到 Python 3.12+。${NC}"
        prompt_continue "按回车自动安装..."
        install_python3_12
        command -v python3.12 &>/dev/null && PYTHON_CMD="python3.12" || {
            command -v python3 &>/dev/null && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' && PYTHON_CMD="python3"
        }
        [[ -z "$PYTHON_CMD" ]] && { echo -e "${RED}无法获取 Python 3.12，中止。${NC}"; exit 1; }
    fi

    if $INSTALL_DEPS; then
        echo -e "${GREEN}Python 解释器：$PYTHON_CMD${NC}\n"
        echo -e "${GREEN}创建虚拟环境并安装依赖...${NC}"
        $PYTHON_CMD -m venv .venv
        # shellcheck disable=SC1091
        source .venv/bin/activate
        [[ -f requirements.txt ]] && pip install -r requirements.txt || pip install .
    else
        echo -e "${YELLOW}跳过依赖安装，直接尝试启动...${NC}"
        if [[ -d .venv ]]; then
            # shellcheck disable=SC1091
            source .venv/bin/activate
        fi
    fi

    echo -e "\n${GREEN}[启动] 正在启动 ldmbot...${NC}\n"
    exec python main.py
}
# ==========================

install_napcat() {
    echo -e "\n${GREEN}=== 安装 NapCat ===${NC}"

    # 固定安装到脚本启动目录下的 NapCat（绝对路径）
    # 注意：子 shell / bash 脚本里的 cd 不会改变「用户当前交互终端」的目录；
    # NapCat 官方 launcher.sh 又依赖相对路径 ./libnapcat_launcher.so，
    # 所以安装结束后必须明确提示用户先 cd 到该绝对路径再启动。
    local napcat_dir="${ORIG_DIR}/NapCat"
    mkdir -p "$napcat_dir" || { echo -e "${RED}无法创建 NapCat 目录：${napcat_dir}${NC}"; exit 1; }
    cd "$napcat_dir" || { echo -e "${RED}无法进入目录：${napcat_dir}${NC}"; exit 1; }

    echo -e "${GREEN}安装目录（绝对路径）：${napcat_dir}${NC}"
    echo -e "${YELLOW}说明：安装脚本内部的 cd 不会改变你当前终端所在目录。${NC}"
    echo -e "${YELLOW}安装完成后请务必先进入上述目录，再执行启动命令。${NC}\n"

    echo -e "请选择安装线路：\n"
    echo -e "${GREEN}1)${NC} 线路1（国内）：${YELLOW}curl -o napcat.sh https://jiashu.1win.eu.org/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh${NC}\n"
    echo -e "${GREEN}2)${NC} 线路2（国内）：${YELLOW}curl -o napcat.sh https://github.moeyy.xyz/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh${NC}\n"
    echo -e "${GREEN}3)${NC} 线路3（国外）：${YELLOW}curl -o napcat.sh https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh && sudo bash napcat.sh${NC}\n"

    local choice
    read -p "请输入选择 [1-3]: " choice < /dev/tty
    local url=""
    case $choice in
        1) url="https://jiashu.1win.eu.org/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh" ;;
        2) url="https://github.moeyy.xyz/https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh" ;;
        3) url="https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh" ;;
        *) echo -e "${RED}无效选择${NC}"; exit 1 ;;
    esac

    echo -e "${GREEN}正在下载并执行安装脚本...${NC}"
    # 不用 exec：exec 会替换本进程，结束后无法再打印「请 cd 到哪里」的提示
    curl -o napcat.sh "$url" || { echo -e "${RED}下载失败${NC}"; exit 1; }
    # set -e 下必须先关再开，才能拿到官方安装脚本的退出码并继续打印 cd 提示
    set +e
    sudo bash napcat.sh
    local rc=$?
    set -e

    echo
    echo -e "${GREEN}=============================${NC}"
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}      NapCat 安装流程已结束      ${NC}"
    else
        echo -e "${YELLOW}      NapCat 安装脚本退出码：${rc}      ${NC}"
    fi
    echo -e "${GREEN}=============================${NC}"
    echo -e "${YELLOW}重要：你当前终端仍在「运行本安装脚本时」的目录，不会自动进入 NapCat。${NC}"
    echo -e "${YELLOW}官方 launcher.sh 使用相对路径（./libnapcat_launcher.so），必须先 cd 再启动。${NC}"
    echo
    echo -e "${GREEN}请复制执行以下命令启动 NapCat：${NC}"
    echo -e "  ${YELLOW}cd \"${napcat_dir}\"${NC}"
    echo -e "  ${YELLOW}sudo bash ./launcher.sh${NC}"
    echo
    echo -e "或一行：${YELLOW}cd \"${napcat_dir}\" && sudo bash ./launcher.sh${NC}"
    echo

    # 可选：直接帮用户在本脚本进程内启动（仍无法改用户 shell 的 cwd，但可省一次手敲）
    if [[ $rc -eq 0 ]] && [[ -f "${napcat_dir}/launcher.sh" ]]; then
        if ask_yes_no "是否现在就在本脚本内启动 NapCat？（Ctrl+C 可结束）"; then
            cd "$napcat_dir" || exit 1
            echo -e "${GREEN}正在启动：cd ${napcat_dir} && sudo bash ./launcher.sh${NC}"
            exec sudo bash ./launcher.sh
        fi
    elif [[ ! -f "${napcat_dir}/launcher.sh" ]]; then
        echo -e "${RED}未在 ${napcat_dir} 找到 launcher.sh，请检查上方安装日志。${NC}"
        echo -e "${YELLOW}若文件在其他目录，请先 find 定位后再 cd 过去启动。${NC}"
    fi
}

migrate_official() {
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${GREEN}   从官方迁移（替换官方源码为 ldmbot）   ${NC}"
    echo -e "${GREEN}=====================================${NC}\n"
    echo -e "${YELLOW}此操作将删除目标 AstrBot 目录下的 astrbot 和 data/dist 目录，并替换为 ldmbot 源码。${NC}"
    echo -e "请确保目标目录是 AstrBot 的根目录（包含 astrbot, data, main.py 等）。\n"

    local target_dir=""
    while true; do
        read -p "请输入目标 AstrBot 目录路径（输入 0 进行自动搜索）: " input < /dev/tty
        if [[ "$input" == "0" ]]; then
            echo -e "\n${YELLOW}正在搜索可能的目标目录...${NC}"
            local search_results
            search_results=$( { find ~/ -type f -path "*astrbot/api/event/filter*" 2>/dev/null || true; } | sed 's|/astrbot/api/event/filter/.*||' | sort -u )
            if [[ -z "$search_results" ]]; then
                echo -e "${RED}未找到匹配的目录。${NC}\n"
                continue
            fi
            echo "找到以下可能的目录："
            echo "$search_results" | nl
            echo
            read -p "请选择序号或直接输入路径: " choice < /dev/tty
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                target_dir=$(echo "$search_results" | sed -n "${choice}p")
            else
                target_dir="$choice"
            fi
            if [[ -z "$target_dir" ]]; then
                echo -e "${RED}无效选择。${NC}\n"
                continue
            fi
        else
            target_dir="$input"
        fi

        if [[ ! -d "$target_dir" ]]; then
            echo -e "${RED}目录不存在：$target_dir${NC}\n"
            continue
        fi

        if [[ ! -d "$target_dir/astrbot" ]] || [[ ! -f "$target_dir/main.py" ]]; then
            echo -e "${YELLOW}警告：该目录下未找到 astrbot 目录或 main.py，可能不是正确的 AstrBot 根目录。${NC}"
            if ! ask_yes_no "是否仍然强制继续？"; then
                echo
                continue
            fi
        fi
        break
    done

    # 展示目标目录内容，确认
    echo -e "\n${GREEN}目标目录：${target_dir}${NC}"
    ls "$target_dir"
    echo

    if ! ask_yes_no "请检查文件内容，应包含 astrbot、main.py 等文件，是否确认？"; then
        echo -e "${YELLOW}已取消迁移。${NC}"
        return
    fi

    # ---------- 在原始目录下获取 ZIP ----------
    local downloaded_zip
    downloaded_zip=$(download_ldmbot_zip)

    # ---------- 进入目标目录进行替换 ----------
    cd "$target_dir" || { echo -e "${RED}无法进入目录。${NC}"; exit 1; }

    local tmp_extract=$(mktemp -d)
    ensure_unzip
    
    echo -e "${YELLOW}正在解压文件以准备覆盖...${NC}"
    if ! unzip -o "$downloaded_zip" -d "$tmp_extract" >/dev/null; then
        echo -e "${RED}解压 ldmbot.zip 失败，迁移中止。${NC}"
        rm -rf "$tmp_extract"
        exit 1
    fi

    if [[ ! -d "$tmp_extract/ldmbot" ]]; then
        echo -e "${RED}错误，解压后未找到 ldmbot 目录，失败，请尝试重新执行脚本${NC}"
        rm -rf "$tmp_extract"
        exit 1
    fi

    echo -e "${GREEN}删除旧官方程序文件（astrbot 和 data/dist）...${NC}"
    rm -rf astrbot data/dist 2>/dev/null || true

    echo -e "${GREEN}正在注入 ldmbot 文件...${NC}"
    cp -rf "$tmp_extract/ldmbot/." .
    
    rm -rf "$tmp_extract"

    echo -e "\n${GREEN}=============================${NC}"
    echo -e "${GREEN}          迁移完成！         ${NC}"
    echo -e "${GREEN}=============================${NC}"
    echo -e "${YELLOW}请手动重启 AstrBot（例如执行重启命令或通过 WebUI 面板设置页面重启）。${NC}"
    echo -e "${YELLOW}提示：如果使用 systemctl 管理，可执行 systemctl restart astrbot 等。${NC}\n"
}

configure_napcat_connection() {
    echo -e "\n${GREEN}=== 配置 ldmbot 与 NapCat 连接 ===${NC}\n"
    echo -e "${YELLOW}请勿重复执行此项。${NC}"
    echo -e "${YELLOW}请先重启 ldmbot 和 NapCat 检查是否已经能连上。${NC}"
    echo -e "${YELLOW}重复执行此项会创建多个连接信息。${NC}"
    echo -e "${YELLOW}请阅读后确认。${NC}\n"
    if ! ask_yes_no "已阅读以上提示，确认继续配置？"; then
        echo -e "${YELLOW}已取消。${NC}"
        return 0
    fi

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}未找到 python3，无法运行配置脚本。${NC}"
        exit 1
    fi

    local tmp_py
    tmp_py=$(mktemp).py
    cat > "$tmp_py" <<'LDMBOT_NAPCAT_CONFIG_PY'
import json
import os
import socket
import sys
from pathlib import Path
from urllib.parse import urlparse
from typing import Any, Callable, Optional, Set

# ---------- 常量 ----------
ANCHOR = "astrbot/builtin_stars/astrbot/ldm"        # 用来定位 ldmbot 的路径片段
CONFIG_REL = Path("data") / "cmd_config.json"       # ldmbot 配置文件相对路径
DEFAULT_PORT = 6199                                 # 起始端口
DEFAULT_ID_PREFIX = "NapCat"                        # ldmbot 平台 id 前缀
DEFAULT_WS_CLIENT_NAME = "ldmbot"                   # NapCat 反向 ws 客户端名称（不带QQ，因为文件已分QQ）

# 全局搜索时跳过的目录名（加速 + 避免权限噪声）
_跳过目录名 = {
    "proc", "sys", "dev", "run", "snap", "boot",
    ".git", "node_modules", "__pycache__", ".cache",
    "lost+found", "tmp", "var", "media", "cdrom",
}


# ---------- 未找到配置时的回退 ----------
def 询问未找到时的处理方式(配置名: str) -> str:
    """未搜索到配置时，让用户选择后续动作。返回 '1'/'2'/'0'。"""
    print(f"\n❌ 未找到 {配置名}。")
    print("请选择：")
    print("  [1] 在全局搜索（耗时可能很长）")
    print("  [2] 手动输入绝对路径")
    print("  [0] 退出")
    while True:
        choice = input("请输入选项（默认 1）：").strip() or "1"
        if choice in ("0", "1", "2"):
            return choice
        print("无效选项，请输入 0、1 或 2。")


def 手动输入绝对路径(
    描述: str,
    校验: Optional[Callable[[Path], Optional[str]]] = None,
) -> Path:
    """循环提示用户输入绝对路径，直到文件存在且通过可选校验。

    校验函数返回 None 表示通过；返回字符串表示错误信息。
    """
    print(f"\n请输入 {描述} 的绝对路径。")
    print("提示：可直接粘贴完整路径；路径两端的引号会自动去掉。")
    while True:
        raw = input("绝对路径：").strip().strip('"').strip("'")
        if not raw:
            print("路径不能为空，请重新输入。")
            continue
        p = Path(raw).expanduser()
        if not p.is_absolute():
            print("请输入绝对路径（以 / 开头，Windows 盘符请用 /mnt/c/... 等形式）。")
            continue
        if not p.exists():
            print(f"文件不存在：{p}")
            continue
        if not p.is_file():
            print(f"不是文件：{p}")
            continue
        if 校验 is not None:
            err = 校验(p)
            if err:
                print(err)
                continue
        return p


def _全局遍历收集(
    匹配: Callable[[str, list[str]], list[Path]],
    进度提示: str,
) -> list[Path]:
    """从常见根目录 os.walk 搜索，忽略权限错误。"""
    print(f"\n⏳ {进度提示}")
    print("   （可能需要较长时间，按 Ctrl+C 可中断）")
    roots: list[Path] = []
    for r in (Path("/"), Path.home()):
        if r.exists() and r not in roots:
            roots.append(r)
    # WSL 常见 Windows 挂载
    mnt = Path("/mnt")
    if mnt.is_dir():
        for child in sorted(mnt.iterdir()):
            if child.is_dir() and child.name.isalpha() and len(child.name) == 1:
                roots.append(child)

    found: list[Path] = []
    seen: Set[str] = set()
    try:
        for root in roots:
            print(f"   … 扫描 {root}")
            for dirpath, dirnames, filenames in os.walk(root, onerror=lambda _e: None):
                # 原地裁剪，避免进入无意义/高权限目录
                dirnames[:] = [
                    d for d in dirnames
                    if d not in _跳过目录名 and not d.startswith(".")
                ]
                try:
                    hits = 匹配(dirpath, filenames)
                except (PermissionError, OSError):
                    continue
                for p in hits:
                    key = str(p.resolve()) if p.exists() else str(p)
                    if key not in seen:
                        seen.add(key)
                        found.append(p)
    except KeyboardInterrupt:
        print("\n⚠️ 全局搜索已被中断，将使用目前已找到的结果。")
    print(f"   共找到 {len(found)} 个候选。")
    return found


def 校验NapCat配置文件(path: Path) -> Optional[str]:
    """校验是否像可用的 NapCat onebot 配置；通过返回 None。"""
    name = path.name
    if not name.endswith(".json"):
        return "文件扩展名应为 .json"
    if name.endswith("_.json"):
        return "这是模板文件（*_ .json），请选择带 QQ 号的正式配置"
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return f"无法解析 JSON：{e}"
    if not isinstance(data, dict):
        return "配置根节点应为 JSON 对象"
    return None


def 校验ldmbot配置文件(path: Path) -> Optional[str]:
    """校验是否像可用的 ldmbot cmd_config.json；通过返回 None。"""
    if path.name != "cmd_config.json":
        # 不强制文件名，但给出提醒并仍允许
        pass
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return f"无法解析 JSON：{e}"
    if not isinstance(data, dict):
        return "配置根节点应为 JSON 对象"
    return None


def 从NapCat路径提取QQ(path: Path) -> str:
    """从 onebot11_QQ.json 这类文件名提取 QQ；失败则询问用户。"""
    parts = path.stem.split("_")
    if len(parts) >= 2:
        candidate = parts[-1]
        if candidate.isdigit():
            return candidate
    while True:
        qq = input("无法从文件名识别 QQ 号，请手动输入：").strip()
        if qq:
            return qq
        print("QQ 号不能为空。")


# ---------- NapCat 配置查找 ----------
def 查找NapCat配置文件(搜索根: Optional[Path] = None) -> list[Path]:
    """在指定根（默认家目录）下查找 NapCat 的 onebot 配置文件。"""
    root = 搜索根 or Path.home()
    try:
        results = [
            p for p in root.glob("**/napcat/config/onebot*_*.json")
            if not p.name.endswith("_.json")  # 排除模板文件
        ]
    except (PermissionError, OSError):
        results = []
    return results


def 全局搜索NapCat配置文件() -> list[Path]:
    """全盘搜索 NapCat onebot 配置。"""

    def 匹配(dirpath: str, filenames: list[str]) -> list[Path]:
        base = Path(dirpath)
        # 路径形如 .../napcat/config/
        if base.name != "config":
            return []
        if base.parent.name.lower() != "napcat":
            return []
        hits = []
        for name in filenames:
            if not name.startswith("onebot"):
                continue
            if not name.endswith(".json") or name.endswith("_.json"):
                continue
            if "_" not in name:
                continue
            hits.append(base / name)
        return hits

    return _全局遍历收集(匹配, "正在全局搜索 NapCat 配置…")


def 获取NapCat配置路径() -> Path:
    """查找 / 回退选择 NapCat 配置文件，返回最终路径。"""
    napcat_configs = 查找NapCat配置文件()
    if not napcat_configs:
        while True:
            choice = 询问未找到时的处理方式("NapCat 的 onebot 配置文件")
            if choice == "0":
                print("已退出。请先安装并启动一次 NapCat 并登录 QQ 后再试。")
                sys.exit(1)
            if choice == "1":
                napcat_configs = 全局搜索NapCat配置文件()
                if napcat_configs:
                    break
                print("全局搜索仍未找到，可改选手动输入路径，或再试一次。")
                continue
            # choice == "2"
            return 手动输入绝对路径("NapCat onebot 配置文件", 校验NapCat配置文件)

    if len(napcat_configs) == 1:
        return napcat_configs[0]

    print("\n找到多个 NapCat 配置文件：")
    for idx, p in enumerate(napcat_configs, 1):
        qq_guess = p.stem.split("_")[-1] if "_" in p.stem else "?"
        print(f"  [{idx}] {p}  (QQ: {qq_guess})")
    choice = input("\n请选择编号（默认 1）：").strip()
    if choice.isdigit() and 1 <= int(choice) <= len(napcat_configs):
        return napcat_configs[int(choice) - 1]
    return napcat_configs[0]


# ---------- 工具：从配置中提取已用端口 ----------
def extract_ports(config: Any, used_ports: Set[int] = None) -> Set[int]:
    """递归遍历配置对象，收集所有端口号"""
    if used_ports is None:
        used_ports = set()
    if isinstance(config, dict):
        for key, value in config.items():
            if key == "port" and isinstance(value, int):
                used_ports.add(value)
            elif key == "url" and isinstance(value, str):
                port = _extract_port_from_url(value)
                if port is not None:
                    used_ports.add(port)
            else:
                extract_ports(value, used_ports)
    elif isinstance(config, list):
        for item in config:
            extract_ports(item, used_ports)
    return used_ports


def _extract_port_from_url(url: str) -> Optional[int]:
    """从 URL 中解析端口号"""
    try:
        parsed = urlparse(url)
        if parsed.port is not None:
            return parsed.port
    except Exception:
        pass
    return None


# ---------- 工具：从配置中提取已用名称 ----------
def extract_names(config, names_set=None):
    """递归提取所有 "name" 键的值"""
    if names_set is None:
        names_set = set()
    if isinstance(config, dict):
        for key, value in config.items():
            if key == "name" and isinstance(value, str):
                names_set.add(value)
            else:
                extract_names(value, names_set)
    elif isinstance(config, list):
        for item in config:
            extract_names(item, names_set)
    return names_set


# ---------- 端口占用检测 ----------
def is_port_in_use(port: int, host: str = "127.0.0.1") -> bool:
    """检测本机端口是否被占用"""
    if not (1 <= port <= 65535):
        raise ValueError("端口号必须在 1~65535 之间")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind((host, port))
            return False
        except OSError:
            return True


# ---------- NapCat 配置写入 ----------
def 写入NapCat反向WS配置(path: Path, port: int, client_name: str):
    """在 NapCat 的 onebot 配置中添加一条反向 websocket 客户端"""
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    # 确保 network 和 websocketClients 存在
    if "network" not in cfg or not isinstance(cfg.get("network"), dict):
        cfg["network"] = {}
    if "websocketClients" not in cfg["network"] or not isinstance(cfg["network"]["websocketClients"], list):
        cfg["network"]["websocketClients"] = []

    # 生成不重复的 name
    existing_names = extract_names(cfg["network"]["websocketClients"])
    final_name = client_name
    counter = 1
    while final_name in existing_names:
        final_name = f"{client_name}_{counter}"
        counter += 1

    new_client = {
        "enable": True,
        "name": final_name,
        "url": f"ws://127.0.0.1:{port}/ws",
        "reportSelfMessage": False,
        "messagePostFormat": "array",
        "token": "",
        "debug": False,
        "heartInterval": 5000,
        "reconnectInterval": 5000,
        "verifyCertificate": False
    }
    cfg["network"]["websocketClients"].append(new_client)

    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=4)
    print(f"✅ 已向 NapCat 配置添加反向 WS 客户端：name={final_name}, port={port}")
    return final_name


# ---------- ldmbot 配置相关 ----------
def find_ldmbot_config_dirs(home: Path) -> list[Path]:
    """搜索 home 下所有包含 ANCHOR 的路径，返回对应的项目根目录列表"""
    try:
        results = list(home.glob(f"**/{ANCHOR}/**"))
    except (PermissionError, OSError):
        results = []
    dynamic_dirs = set()
    for p in results:
        try:
            rel = p.relative_to(home)
        except ValueError:
            continue
        str_rel = rel.as_posix()
        before, _ = str_rel.split(ANCHOR, 1)
        before = before.rstrip("/")
        first_dir = home / before if before else home
        dynamic_dirs.add(first_dir)
    return sorted(dynamic_dirs)


def 全局搜索ldmbot配置文件() -> list[Path]:
    """全盘搜索 ldmbot 的 data/cmd_config.json（要求同树内存在 ANCHOR）。"""
    anchor_parts = ANCHOR.split("/")

    def 匹配(dirpath: str, filenames: list[str]) -> list[Path]:
        if "cmd_config.json" not in filenames:
            return []
        base = Path(dirpath)
        if base.name != "data":
            return []
        # 项目根 = data 的父目录；要求其下存在 ANCHOR
        project_root = base.parent
        if not (project_root.joinpath(*anchor_parts)).exists():
            return []
        return [base / "cmd_config.json"]

    return _全局遍历收集(匹配, "正在全局搜索 ldmbot 配置 (cmd_config.json)…")


def get_ldmbot_config_paths(base_dirs: list[Path]) -> list[Path]:
    """返回所有可能存在的 ldmbot 配置文件路径"""
    return [d / CONFIG_REL for d in base_dirs]


def filter_existing(paths: list[Path]) -> tuple[list[Path], list[Path]]:
    """分离存在与不存在的配置文件路径"""
    valid, invalid = [], []
    for p in paths:
        (valid if p.exists() else invalid).append(p)
    return valid, invalid


def 获取ldmbot配置路径() -> Path:
    """查找 / 回退选择 ldmbot 配置文件，返回最终路径。"""
    print("\n--- 正在搜索 ldmbot 配置 ---")
    home = Path.home()
    dirs = find_ldmbot_config_dirs(home)
    valid_ldm: list[Path] = []

    if dirs:
        config_paths = get_ldmbot_config_paths(dirs)
        valid_ldm, invalid_ldm = filter_existing(config_paths)
        if invalid_ldm:
            print("⚠️ 以下 ldmbot 配置路径不存在，已忽略：")
            for p in invalid_ldm:
                print(f"   • {p}")

    if not valid_ldm:
        while True:
            choice = 询问未找到时的处理方式("ldmbot 的配置文件 (cmd_config.json)")
            if choice == "0":
                print("已退出。请先安装并启动一次 ldmbot 后再试。")
                sys.exit(1)
            if choice == "1":
                valid_ldm = 全局搜索ldmbot配置文件()
                if valid_ldm:
                    break
                print("全局搜索仍未找到，可改选手动输入路径，或再试一次。")
                continue
            # choice == "2"
            return 手动输入绝对路径("ldmbot 配置文件 (cmd_config.json)", 校验ldmbot配置文件)

    if len(valid_ldm) == 1:
        return valid_ldm[0]

    print("\n找到多个 ldmbot 配置文件：")
    for idx, p in enumerate(valid_ldm, 1):
        print(f"  [{idx}] {p}")
    choice = input("\n请选择编号（默认 1）：").strip()
    if choice.isdigit() and 1 <= int(choice) <= len(valid_ldm):
        return valid_ldm[int(choice) - 1]
    return valid_ldm[0]


def load_json(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)


def 向ldmbot添加NapCat平台(config: dict, port: int, platform_id: str):
    """在 ldmbot 的 cmd_config.json 中添加 aiocqhttp 平台配置"""
    if "platform" not in config or not isinstance(config.get("platform"), list):
        config["platform"] = []

    platforms = config["platform"]

    # 生成不重复的 id
    existing_ids = set()
    for item in platforms:
        if isinstance(item, dict) and "id" in item:
            existing_ids.add(item["id"])

    final_id = platform_id
    counter = 1
    while final_id in existing_ids:
        final_id = f"{platform_id}_{counter}"
        counter += 1

    platforms.append({
        "id": final_id,
        "type": "aiocqhttp",
        "enable": True,
        "ws_reverse_host": "127.0.0.1",
        "ws_reverse_port": port,
        "ws_reverse_token": ""
    })
    return final_id


# ---------- 主流程 ----------
def main():
    print("=" * 50)
    print("🔧 NapCat ↔ ldmbot 自动连接配置工具")
    print("=" * 50)

    # 1. 查找 NapCat 配置
    target_napcat = 获取NapCat配置路径()
    qq = 从NapCat路径提取QQ(target_napcat)
    print(f"\n📌 使用 NapCat 配置：{target_napcat}")
    print(f"   绑定 QQ：{qq}")

    # 2. 查找 ldmbot 配置
    target_ldm = 获取ldmbot配置路径()
    print(f"\n📌 使用 ldmbot 配置：{target_ldm}")

    # 3. 收集已占用端口并选择空闲端口
    print("\n--- 正在检测端口占用 ---")
    napcat_cfg = load_json(target_napcat)
    ldm_cfg = load_json(target_ldm)

    used_ports = set()
    # NapCat 中 network.websocketClients 的端口
    network = napcat_cfg.get("network", {})
    clients = network.get("websocketClients", [])
    if isinstance(clients, list):
        for client in clients:
            if isinstance(client, dict) and "url" in client:
                p = _extract_port_from_url(client["url"])
                if p:
                    used_ports.add(p)
    # ldmbot 中平台的 ws_reverse_port
    platforms = ldm_cfg.get("platform", [])
    if isinstance(platforms, list):
        for plat in platforms:
            if isinstance(plat, dict) and "ws_reverse_port" in plat:
                port_val = plat["ws_reverse_port"]
                if isinstance(port_val, int):
                    used_ports.add(port_val)

    # 选择一个空闲端口（同时检测系统占用）
    port = DEFAULT_PORT
    while port in used_ports or is_port_in_use(port):
        port += 1
    print(f"🔌 选定通信端口：{port}")

    # 4. 生成名称
    # NapCat 客户端名称不带 QQ，因为配置文件已区分 QQ
    ws_client_name = DEFAULT_WS_CLIENT_NAME
    # ldmbot 平台 ID 可以带上 QQ 便于区分（按需，这里仍带）
    ldm_platform_id = f"{DEFAULT_ID_PREFIX}_{qq}"

    # 5. 写入配置
    print("\n--- 正在写入配置 ---")
    写入NapCat反向WS配置(target_napcat, port, ws_client_name)
    final_ldm_id = 向ldmbot添加NapCat平台(ldm_cfg, port, ldm_platform_id)
    save_json(target_ldm, ldm_cfg)
    print(f"✅ 已向 ldmbot 添加平台配置：id={final_ldm_id}, port={port}")

    print("\n" + "=" * 50)
    print("🎉 配置完成！")
    print(f"   NapCat 反向 WS 客户端：{ws_client_name} (端口 {port})")
    print(f"   ldmbot 平台 ID：{final_ldm_id} (端口 {port})")
    print("请分别重启 NapCat 和 ldmbot 以使设置生效。")
    print("=" * 50)


if __name__ == "__main__":
    main()
LDMBOT_NAPCAT_CONFIG_PY

    set +e
    python3 "$tmp_py"
    local rc=$?
    set -e
    rm -f "$tmp_py"
    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}配置脚本执行失败（退出码 $rc）。${NC}"
        exit $rc
    fi
}


show_menu() {
    if $AUTO_YES; then
        echo "1"   # 非交互默认：安装 ldmbot
        return
    fi
    sleep 0.1
    cat >&2 <<EOF

${YELLOW}请选择操作：${NC}
----------------------------------------
${GREEN}1) 安装 ldmbot${NC}
${GREEN}2) 直接尝试启动（使用现有文件）${NC}
${GREEN}3) 更新 ldmbot${NC}
${RED}4) 退出${NC}
${GREEN}5) 从官方迁移（替换官方源码）${NC}
${GREEN}6) 安装 NapCat${NC}
${GREEN}7) 配置 ldmbot 与 NapCat 连接${NC}
----------------------------------------
EOF
    read -p "请选择 [1]: " choice < /dev/tty
    choice=${choice:-1}
    echo "$choice"
}

choice=$(show_menu)
case $choice in
    1)
        install_ldmbot
        ;;
    2)
        echo -e "\n${GREEN}直接尝试启动...${NC}"
        if [[ -d ldmbot ]]; then
            try_direct_run
        else
            echo -e "${YELLOW}当前目录未检测到 ldmbot 项目。${NC}"
            if $AUTO_YES; then
                echo -e "${RED}非交互模式下无法输入路径，退出。${NC}"
                exit 1
            fi
            while true; do
                read -p "请输入 ldmbot 项目目录路径（输入 0 自动搜索）: " target_path < /dev/tty
                if [[ "$target_path" == "0" ]]; then
                    echo -e "\n${YELLOW}正在搜索标志目录 astrbot/builtin_stars/astrbot/ldm ...${NC}"
                    search_results=$( { find ~/ -type d -path "*astrbot/builtin_stars/astrbot/ldm" 2>/dev/null || true; } | sed 's|/astrbot/builtin_stars/astrbot/ldm$||' | sort -u )
                    if [[ -z "$search_results" ]]; then
                        echo -e "${RED}未找到包含 astrbot/builtin_stars/astrbot/ldm 的目录。${NC}\n"
                        continue
                    fi
                    readarray -t candidates <<< "$search_results"
                    if [[ ${#candidates[@]} -eq 1 ]]; then
                        target_path="${candidates[0]}"
                        echo -e "${GREEN}自动选择唯一目录：${target_path}${NC}\n"
                    else
                        echo "找到以下可能的 ldmbot 根目录："
                        i=1
                        for dir in "${candidates[@]}"; do
                            echo "  $i) $dir"
                            ((i++))
                        done
                        echo
                        while true; do
                            read -p "请选择序号（或输入 0 退出）: " choice_idx < /dev/tty
                            if [[ "$choice_idx" == "0" ]]; then
                                echo -e "${YELLOW}已取消。${NC}"
                                exit 0
                            elif [[ "$choice_idx" =~ ^[0-9]+$ ]] && (( choice_idx >= 1 && choice_idx <= ${#candidates[@]} )); then
                                target_path="${candidates[$((choice_idx-1))]}"
                                break
                            else
                                echo -e "${RED}无效选择。${NC}"
                            fi
                        done
                    fi
                    break
                elif [[ -d "$target_path" ]]; then
                    if [[ -f "$target_path/main.py" ]] || [[ -d "$target_path/ldmbot" ]]; then
                        break
                    else
                        echo -e "${RED}目录 $target_path 中未找到 main.py 或 ldmbot 子目录，请重新输入。${NC}\n"
                    fi
                else
                    echo -e "${RED}目录 $target_path 不存在。${NC}\n"
                fi
            done

            cd "$target_path" || { echo -e "${RED}无法进入目录。${NC}"; exit 1; }
            if [[ -d ldmbot ]]; then cd ldmbot || exit 1; fi
            if command -v uv &>/dev/null && [[ -f pyproject.toml ]]; then
                echo -e "${GREEN}使用 uv 启动...${NC}"
                exec uv run main.py
            elif [[ -d .venv ]]; then
                echo -e "${GREEN}使用虚拟环境中的 python 启动...${NC}"
                source .venv/bin/activate
                exec python main.py
            elif command -v python3 &>/dev/null; then
                echo -e "${YELLOW}尝试直接使用系统 python3 启动...${NC}"
                exec python3 main.py
            else
                echo -e "${RED}无法找到可用的启动方式，请检查目录内容。${NC}"
                exit 1
            fi
        fi
        ;;
    3)
        update_ldmbot true
        ;;
    4)
        echo -e "${RED}已退出。${NC}"
        exit 0
        ;;
    5)
        migrate_official
        exit 0
        ;;
    6)
        install_napcat
        ;;
    7)
        configure_napcat_connection
        ;;
    *)
        echo -e "${RED}无效选项，已退出。${NC}"
        exit 1
        ;;
esac

exit 0