#!/bin/bash

# 颜色变量
MAGENTA='\033[0;1;35;95m'
RED='\033[0;1;31;91m'
YELLOW='\033[0;1;33;93m'
GREEN='\033[0;1;32;92m'
CYAN='\033[0;1;36;96m'
BLUE='\033[0;1;34;94m'
NC='\033[0m'

function log() {
    time=$(date +"%Y-%m-%d %H:%M:%S")
    message="[${time}]: $1 "
    case "$1" in
    *"失败"* | *"错误"* | *"sudo不存在"* | *"当前用户不是root用户"* | *"无法连接"*)
        echo -e "${RED}${message}${NC}"
        ;;
    *"成功"*)
        echo -e "${GREEN}${message}${NC}"
        ;;
    *"忽略"* | *"跳过"* | *"默认"* | *"警告"*)
        echo -e "${YELLOW}${message}${NC}"
        ;;
    *)
        echo -e "${BLUE}${message}${NC}"
        ;;
    esac
}

# 强制 root 运行
if [ "$EUID" -ne 0 ]; then
    log "错误: 此脚本需要以 root 权限运行。"
    exit 1
fi
log "脚本正在以 root 权限运行。"

# 固定安装路径
INSTALL_DIR="/root/NapCat"
INTERNAL_BASE="http://39.106.102.162:9800/napcat%E8%B5%84%E6%BA%90"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1
rm -rf /root/NapCat/napcat >/dev/null 2>&1

function detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        package_manager="apt-get"
        package_installer="dpkg"
    elif command -v dnf &> /dev/null; then
        package_manager="dnf"
        package_installer="rpm"
    else
        log "高级包管理器检查失败, 目前仅支持apt-get/dnf。"
        exit 1
    fi
    log "当前高级包管理器: ${package_manager}"
    log "当前基础包管理器: ${package_installer}"
}

function install_dependency() {
    log "开始更新依赖..."
    detect_package_manager
    log "警告: 此过程可能需要几分钟时间，若耗时超过十分钟，请尝试开启VPN"

    if [ "${package_manager}" = "apt-get" ]; then
        apt-get update -y -qq
        apt-get install -y -qq zip unzip jq wget xvfb screen xauth procps g++
    elif [ "${package_manager}" = "dnf" ]; then
        dnf install -y epel-release
        dnf install --allowerasing -y zip unzip jq wget xorg-x11-server-Xvfb screen procps-ng gcc-c++
    fi
    log "依赖安装成功..."
}

function network_test() {
    local timeout=10
    local found=0
    target_proxy=""
    log "开始网络测试: Github..."

    proxy_arr=("https://ghfast.top" "https://gh.wuliya.xin" "https://gh-proxy.com" "https://github.moeyy.xyz")
    check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"

    for proxy in "${proxy_arr[@]}"; do
        log "测试代理: ${proxy}"
        if wget -q --spider --timeout=${timeout} --tries=1 "${proxy}/${check_url}" 2>/dev/null; then
            found=1
            target_proxy="${proxy}"
            log "将使用Github代理: ${proxy}"
            break
        else
            log "代理 ${proxy} 测试失败或超时"
        fi
    done

    if [ ${found} -eq 0 ]; then
        log "警告: 无法找到可用的Github代理，将尝试直连..."
        if wget -q --spider --timeout=${timeout} --tries=1 "${check_url}" 2>/dev/null; then
            log "直连Github成功，将不使用代理"
            target_proxy=""
        else
            log "警告: 无法连接到Github，请检查网络。将继续尝试安装，但可能会失败。"
        fi
    fi
}

function get_system_arch() {
    system_arch=$(arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)
    if [ "${system_arch}" = "none" ]; then
        log "无法识别的系统架构, 请检查错误。"
        exit 1
    fi
    log "当前系统架构: ${system_arch}"
}

function download_napcat() {
    cd "$INSTALL_DIR" || exit 1

    if [ -f "NapCat.Shell.zip" ]; then
        log "检测到已下载 NapCat.Shell.zip，跳过下载..."
    else
        log "开始从内部源下载 NapCat.Shell.zip ..."
        wget -q --show-progress -O NapCat.Shell.zip "${INTERNAL_BASE}/NapCat.Shell.zip"
        if [ $? -ne 0 ]; then
            log "内部源下载失败，尝试备用下载..."
            network_test
            napcat_download_url="${target_proxy:+${target_proxy}/}https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
            wget -q --show-progress -O NapCat.Shell.zip "${napcat_download_url}"
            if [ $? -ne 0 ]; then
                log "文件下载失败, 请检查错误。"
                exit 1
            fi
        fi
        log "NapCat.Shell.zip 下载成功。"
    fi

    log "正在验证 NapCat.Shell.zip..."
    unzip -t NapCat.Shell.zip > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "文件验证失败, 请检查错误。"
        exit 1
    fi

    log "正在解压 NapCat.Shell.zip 到 ./napcat ..."
    rm -rf /root/NapCat/napcat >/dev/null 2>&1
    unzip -q -o -d ./napcat NapCat.Shell.zip
    if [ $? -ne 0 ]; then
        log "文件解压失败, 请检查错误。"
        exit 1
    fi
    log "NapCat 解压完成。"
}

function install_linuxqq() {
    cd "$INSTALL_DIR" || exit 1
    get_system_arch
    detect_package_manager
    log "安装 LinuxQQ..."

    if [ "${package_manager}" = "apt-get" ]; then
        # 优先内部源 QQ.deb
        if [ ! -f "QQ.deb" ]; then
            log "开始从内部源下载 QQ.deb ..."
            wget -q --show-progress -O QQ.deb "${INTERNAL_BASE}/QQ.deb"
            if [ $? -ne 0 ]; then
                log "内部源下载 QQ.deb 失败，尝试官方下载..."
                if [ "${system_arch}" = "amd64" ]; then
                    qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_amd64_01.deb"
                elif [ "${system_arch}" = "arm64" ]; then
                    qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_arm64_01.deb"
                fi
                wget -q --show-progress -O QQ.deb "${qq_download_url}"
                if [ $? -ne 0 ]; then
                    log "QQ.deb 下载失败。"
                    exit 1
                fi
            fi
            log "QQ.deb 下载成功"
        else
            log "检测到已下载 QQ.deb，跳过下载"
        fi

        log "正在安装 LinuxQQ ..."
        apt-get install -f -y --allow-downgrades -qq ./QQ.deb
        apt-get install -y --allow-downgrades -qq libnss3 libgbm1 libasound2 || apt-get install -y --allow-downgrades -qq libasound2t64

    elif [ "${package_manager}" = "dnf" ]; then
        log "内部源未提供 rpm，使用官方源..."
        if [ "${system_arch}" = "amd64" ]; then
            qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_x86_64_01.rpm"
        elif [ "${system_arch}" = "arm64" ]; then
            qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_aarch64_01.rpm"
        fi
        if [ ! -f "QQ.rpm" ]; then
            wget -q --show-progress -O QQ.rpm "${qq_download_url}"
            if [ $? -ne 0 ]; then
                log "QQ.rpm 下载失败。"
                exit 1
            fi
            log "QQ.rpm 下载成功"
        else
            log "检测到已下载 QQ.rpm，跳过下载"
        fi

        log "正在安装 LinuxQQ ..."
        dnf localinstall -y ./QQ.rpm
    fi

    log "LinuxQQ 安装完成"
}

function download_launcher_so() {
    cd "$INSTALL_DIR" || exit 1
    get_system_arch

    # 只支持 amd64/arm64 架构
    if [ "${system_arch}" != "amd64" ] && [ "${system_arch}" != "arm64" ]; then
        log "不支持的架构: ${system_arch}"
        exit 1
    fi

    log "开始从内部源下载 launcher.cpp ..."
    wget -q --show-progress -O launcher.cpp "${INTERNAL_BASE}/launcher.cpp"
    if [ $? -ne 0 ]; then
        log "内部源下载失败，尝试备用下载..."
        network_test
        cpp_url="https://raw.githubusercontent.com/NapNeko/napcat-linux-launcher/refs/heads/main/launcher.cpp"
        if [ -n "${target_proxy}" ]; then
            cpp_url="${target_proxy}/${cpp_url}"
        fi
        wget -q --show-progress -O launcher.cpp "${cpp_url}"
        if [ $? -ne 0 ]; then
            log "launcher.cpp 下载失败，请检查网络。"
            exit 1
        fi
    fi
    log "launcher.cpp 下载成功。"

    log "正在编译 libnapcat_launcher.so ..."
    g++ -shared -fPIC launcher.cpp -o libnapcat_launcher.so -ldl
    if [ $? -ne 0 ]; then
        log "libnapcat_launcher.so 编译失败，请检查g++是否安装或源码是否有误。"
        exit 1
    fi
    log "libnapcat_launcher.so 编译成功。"
}

# 主流程
# clear
log "NapCat Shell 安装脚本 (Root 专用)"
install_dependency
download_napcat
install_linuxqq
download_launcher_so

cat > /root/NapCat/start_napcat.sh << 'EOF'
#!/bin/bash
cd /root/NapCat

# 先尝试清理可能残留的 Xvfb 进程
killall Xvfb 2>/dev/null
sleep 1

success=0
for i in {1..10}; do
    # 生成 10-99 的随机端口
    port=$((RANDOM % 90 + 10))
    
    # 清理该端口可能残留的锁文件
    rm -rf /tmp/.X${port}-lock /tmp/.X11-unix/X${port} 2>/dev/null
    
    # 尝试启动 Xvfb
    Xvfb :${port} -screen 0 1080x1920x24 > /dev/null 2>&1 &
    XVFB_PID=$!
    sleep 1
    
    # 检查 Xvfb 是否存活
    if kill -0 $XVFB_PID 2>/dev/null; then
        export DISPLAY=:${port}
        success=1
        echo "✅ Xvfb 启动成功，使用显示器端口 :${port} (PID: $XVFB_PID)"
        break
    fi
done

if [ $success -eq 0 ]; then
    echo "❌ 错误：尝试 10 次后，Xvfb 仍然无法启动。建议重启容器清理环境。"
    exit 1
fi

trap "" SIGPIPE
echo "正在启动 NapCat..."
LD_PRELOAD=./libnapcat_launcher.so qq --no-sandbox --disable-gpu --disable-dev-shm-usage
EOF

chmod +x /root/NapCat/start_napcat.sh
cp /root/NapCat/start_napcat.sh /root/NapCat/launcher.sh

log "启动命令: cd /root/NapCat && bash /root/NapCat/start_napcat.sh"

log "启动命令2: cd /root/NapCat && bash /root/NapCat/launcher.sh"


# 安装完成自动启动（前台运行）
log "安装完成，正在前台启动 NapCat ..."
cd /root/NapCat && bash /root/NapCat/start_napcat.sh