#!/bin/bash

# NapCat Shell 安装脚本 (Root 专用) —— 增强版
# 用法: bash ldm_napcat_install.sh [-y] [-p <安装目录>]
#       curl -fsSL 'http://39.106.102.162:9800/napcat%E8%B5%84%E6%BA%90/ldm_napcat_install.sh' | bash -s -- -y -p /opt/NapCat
#   -y, --yes           目标目录已存在(已安装)时不再询问, 直接删除重装
#   -p, --path <目录>   指定安装目录(绝对路径), 默认 /root/NapCat
#
# 修复/增强内容:
#   1. 每一步(依赖安装/下载/解压/安装QQ/编译)都校验退出码, 失败立即终止, 不再"失败仍显示成功"
#   2. QQ 安装失败会直接报错退出: 校验 apt/dnf 退出码 + qq 可执行文件 + 软件包状态
#   3. wget 失败后清理半截文件, 避免下次运行"跳过下载"时误用损坏文件
#   4. 复用本地已下载文件前先校验完整性(zip/deb/rpm), 损坏则自动删除重新下载
#   5. 安装结束后做整体验证(QQ命令/napcat目录/launcher.so/启动脚本), 全部通过才提示成功
#   6. QQ 安装包按架构从懒大猫服务器获取: arm64 -> QQ-arm.deb, amd64 -> QQ-amd.deb,
#      并校验 deb 的 Architecture 字段, 架构不符自动改用官方源对应架构包
#   7. 支持 -p/--path 自定义安装目录; 检测到已安装(napcat 目录)时提示"删除重装 y/n",
#      只删除 napcat 子目录, QQ.deb/NapCat.Shell.zip 等安装包资源保留复用; -y 直接继续

set -uo pipefail

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
    *"失败"* | *"错误"* | *"sudo不存在"* | *"当前用户不是root用户"* | *"无法连接"* | *"终止"*)
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

function die() {
    log "错误: $1"
    log "安装已终止。"
    exit 1
}

function usage() {
    echo "用法: bash ldm_napcat_install.sh [-y] [-p <安装目录>]"
    echo "  -y, --yes           检测到已安装(napcat 目录)时不再询问, 直接删除重装"
    echo "  -p, --path <目录>   指定安装目录(绝对路径), 默认 /root/NapCat"
    echo "  -h, --help          显示本帮助"
    echo "管道方式: curl -fsSL '<脚本URL>' | bash -s -- -y -p /opt/NapCat"
}

# ---------------- 参数解析 ----------------
INSTALL_DIR="/root/NapCat"
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
    -p | --path)
        if [ $# -lt 2 ]; then
            log "错误: 参数 $1 后面需要跟一个安装目录。"
            exit 1
        fi
        INSTALL_DIR="$2"
        shift 2
        ;;
    -y | --yes)
        ASSUME_YES=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        log "错误: 未知参数: $1"
        usage
        exit 1
        ;;
    esac
done

# 去掉末尾斜杠并校验路径合法性
INSTALL_DIR="${INSTALL_DIR%/}"
if [ -z "${INSTALL_DIR}" ]; then
    # 原路径是 "/" 时会变成空串
    INSTALL_DIR="/"
fi
if [ "${INSTALL_DIR}" = "/" ] || [ "${INSTALL_DIR}" = "/root" ]; then
    log "错误: 安装目录不合法: ${INSTALL_DIR}，请指定一个专用目录(如 /root/NapCat)。"
    exit 1
fi
case "${INSTALL_DIR}" in
/*) ;;
*)
    log "错误: 安装目录请使用绝对路径，例如 /opt/NapCat。"
    exit 1
    ;;
esac
case "${INSTALL_DIR}" in
/ | /root | /usr | /etc | /var | /opt | /home | /boot | /dev | /proc | /sys | /tmp | /lib | /lib64 | /bin | /sbin | /mnt | /media | /srv | /run)
    log "错误: 不能使用系统关键目录作为安装目录: ${INSTALL_DIR}"
    exit 1
    ;;
esac

log "NapCat Shell 安装脚本 (Root 专用)"
log "将安装到 ${INSTALL_DIR}"

# ---------------- 强制 root 运行 ----------------
if [ "$EUID" -ne 0 ]; then
    log "错误: 此脚本需要以 root 权限运行。"
    exit 1
fi
log "脚本正在以 root 权限运行。"

# ---------------- 已安装则删除重装(先确认) ----------------
# 只检测/删除 napcat 子目录; QQ.deb、NapCat.Shell.zip 等已下载的安装包资源保留复用
if [ -d "${INSTALL_DIR}/napcat" ] && [ -n "$(ls -A "${INSTALL_DIR}/napcat" 2>/dev/null)" ]; then
    log "警告: 检测到 ${INSTALL_DIR}/napcat 已存在(可能已安装)，将删除 napcat 目录后重新安装，已下载的安装包资源会保留。"
    if [ "${ASSUME_YES}" -ne 1 ]; then
        answer=""
        while [ "${answer}" != "y" ] && [ "${answer}" != "n" ]; do
            printf "是否继续 y/n: "
            if ! read -r answer < /dev/tty; then
                log "错误: 无法读取输入(非交互环境)，请加 -y 参数直接继续。"
                exit 1
            fi
            answer="$(printf '%s' "${answer}" | tr '[:upper:]' '[:lower:]')"
            case "${answer}" in
            y | yes) answer="y" ;;
            n | no) answer="n" ;;
            *) answer="" ;;
            esac
        done
        if [ "${answer}" = "n" ]; then
            log "已取消安装。"
            exit 0
        fi
    fi
    rm -rf "${INSTALL_DIR}/napcat"
    log "已删除 ${INSTALL_DIR}/napcat，开始重新安装。"
fi

# 固定资源地址
INTERNAL_BASE="http://39.106.102.162:9800/napcat%E8%B5%84%E6%BA%90"
target_proxy=""

mkdir -p "${INSTALL_DIR}" || die "创建安装目录 ${INSTALL_DIR} 失败。"
cd "${INSTALL_DIR}" || die "无法进入安装目录 ${INSTALL_DIR}。"
rm -rf "${INSTALL_DIR}/napcat" >/dev/null 2>&1

# 通用下载函数: 失败时删除残留的半截文件并返回非0
function fetch() {
    local out="$1"
    local url="$2"
    rm -f "$out"
    if wget -q --show-progress -T 60 -t 3 -O "$out" "$url"; then
        [ -s "$out" ] && return 0
    fi
    rm -f "$out"
    return 1
}

function detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        package_manager="apt-get"
        package_installer="dpkg"
    elif command -v dnf &> /dev/null; then
        package_manager="dnf"
        package_installer="rpm"
    else
        die "高级包管理器检查失败, 目前仅支持apt-get/dnf。"
    fi
    log "当前高级包管理器: ${package_manager}"
    log "当前基础包管理器: ${package_installer}"
}

function install_dependency() {
    log "开始更新依赖..."
    detect_package_manager
    log "警告: 此过程可能需要几分钟时间，若耗时超过十分钟，请尝试开启VPN"

    export DEBIAN_FRONTEND=noninteractive

    if [ "${package_manager}" = "apt-get" ]; then
        if ! apt-get update -y -qq; then
            log "警告: apt-get update 失败，将继续尝试安装依赖(可能使用本地缓存的软件源索引)。"
        fi
        apt-get install -y -qq zip unzip jq wget xvfb screen xauth procps g++ \
            || die "依赖安装失败(apt-get)，请检查软件源是否可用或网络是否畅通。"
    elif [ "${package_manager}" = "dnf" ]; then
        if ! dnf install -y epel-release; then
            log "警告: epel-release 安装失败，继续安装其余依赖。"
        fi
        dnf install --allowerasing -y zip unzip jq wget xorg-x11-server-Xvfb screen procps-ng gcc-c++ \
            || die "依赖安装失败(dnf)，请检查软件源是否可用或网络是否畅通。"
    fi

    # 逐项校验关键命令确实可用，防止包管理器返回0但实际没装上
    local cmd
    for cmd in wget unzip zip screen Xvfb g++; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            die "依赖校验失败: 未找到命令 ${cmd}，依赖安装未成功。"
        fi
    done
    log "依赖安装成功。"
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
    local raw
    raw="$(arch 2>/dev/null || uname -m)"
    system_arch="$(echo "$raw" | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)"
    if [ "${system_arch}" != "amd64" ] && [ "${system_arch}" != "arm64" ]; then
        die "无法识别或不支持的系统架构: ${raw}，仅支持 amd64/arm64。"
    fi
    log "当前系统架构: ${system_arch}"
}

# 文件完整性校验
function verify_zip() {
    [ -s "$1" ] || return 1
    unzip -t "$1" >/dev/null 2>&1
}

function verify_deb() {
    [ -s "$1" ] || return 1
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb --info "$1" >/dev/null 2>&1
    else
        return 0
    fi
}

function deb_arch_ok() {
    # deb 的 Architecture 字段必须与系统架构一致(或为 all)
    local deb_arch
    deb_arch="$(dpkg-deb -f "$1" Architecture 2>/dev/null | tr -d '[:space:]')"
    if [ "${deb_arch}" != "${system_arch}" ] && [ "${deb_arch}" != "all" ]; then
        log "警告: $1 的包架构为 ${deb_arch:-未知}，与系统架构 ${system_arch} 不匹配。"
        return 1
    fi
    return 0
}

function verify_rpm() {
    [ -s "$1" ] || return 1
    if command -v rpm >/dev/null 2>&1; then
        rpm -qp --nosignature "$1" >/dev/null 2>&1
    else
        return 0
    fi
}

function download_napcat() {
    cd "${INSTALL_DIR}" || die "无法进入安装目录 ${INSTALL_DIR}。"

    if [ -f "NapCat.Shell.zip" ]; then
        if verify_zip NapCat.Shell.zip; then
            log "检测到已下载且完整的 NapCat.Shell.zip，跳过下载。"
        else
            log "警告: 本地 NapCat.Shell.zip 不完整或已损坏，删除后重新下载。"
            rm -f NapCat.Shell.zip
        fi
    fi

    if [ ! -f "NapCat.Shell.zip" ]; then
        log "开始从懒大猫服务器下载 NapCat.Shell.zip ..."
        if ! fetch NapCat.Shell.zip "${INTERNAL_BASE}/NapCat.Shell.zip"; then
            log "懒大猫服务器下载失败，尝试备用下载..."
            network_test
            napcat_download_url="${target_proxy:+${target_proxy}/}https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
            fetch NapCat.Shell.zip "${napcat_download_url}" \
                || die "NapCat.Shell.zip 下载失败, 请检查网络。"
        fi
        verify_zip NapCat.Shell.zip || {
            rm -f NapCat.Shell.zip
            die "NapCat.Shell.zip 校验失败(不是有效的zip文件)，请重新运行脚本。"
        }
        log "NapCat.Shell.zip 下载成功。"
    fi

    log "正在解压 NapCat.Shell.zip 到 ./napcat ..."
    rm -rf "${INSTALL_DIR}/napcat" >/dev/null 2>&1
    unzip -q -o -d ./napcat NapCat.Shell.zip || die "NapCat 解压失败, 请检查错误。"
    if [ -z "$(ls -A ./napcat 2>/dev/null)" ]; then
        die "NapCat 解压结果为空，安装无法继续。"
    fi
    log "NapCat 解压完成。"
}

# QQ 运行依赖(libnss3/libgbm1/libasound2)，Ubuntu 24.04 上 libasound2 被 libasound2t64 取代
function install_qq_runtime_deps() {
    local dep
    for dep in libnss3 libgbm1 libasound2; do
        if apt-get install -y --allow-downgrades -qq "$dep" >/dev/null 2>&1; then
            continue
        fi
        if [ "$dep" = "libasound2" ] && apt-get install -y --allow-downgrades -qq libasound2t64 >/dev/null 2>&1; then
            log "已使用 libasound2t64 替代 libasound2 安装成功。"
        else
            log "警告: 运行依赖 ${dep} 安装失败，QQ 运行时可能异常。"
        fi
    done
}

function verify_qq_installed() {
    # 三个条件任一满足即认为安装成功: qq 命令存在 / 包状态为已安装 / 主程序文件存在
    if command -v qq >/dev/null 2>&1; then
        return 0
    fi
    if [ "${package_installer:-}" = "dpkg" ] \
        && dpkg-query -W -f='${Status}' qq 2>/dev/null | grep -q "install ok installed"; then
        return 0
    fi
    if [ "${package_installer:-}" = "rpm" ] && rpm -q qq >/dev/null 2>&1; then
        return 0
    fi
    if [ -x /opt/QQ/qq ]; then
        return 0
    fi
    return 1
}

function install_linuxqq() {
    cd "${INSTALL_DIR}" || die "无法进入安装目录 ${INSTALL_DIR}。"
    get_system_arch
    detect_package_manager
    log "安装 LinuxQQ..."

    if [ "${package_manager}" = "apt-get" ]; then
        # 懒大猫服务器按架构提供: arm64 -> QQ-arm.deb, amd64 -> QQ-amd.deb
        case "${system_arch}" in
        arm64) internal_qq_file="QQ-arm.deb" ;;
        amd64) internal_qq_file="QQ-amd.deb" ;;
        *) internal_qq_file="QQ.deb" ;;
        esac

        if [ -f "QQ.deb" ] && verify_deb QQ.deb && deb_arch_ok QQ.deb; then
            log "检测到已下载且架构匹配的 QQ.deb，跳过下载。"
        else
            if [ -f "QQ.deb" ]; then
                log "警告: 本地 QQ.deb 不完整、已损坏或架构不匹配，删除后重新下载。"
                rm -f QQ.deb
            fi
            log "开始从懒大猫服务器下载 ${internal_qq_file} ..."
            if fetch QQ.deb "${INTERNAL_BASE}/${internal_qq_file}" \
                && verify_deb QQ.deb && deb_arch_ok QQ.deb; then
                log "QQ.deb 下载成功。"
            else
                rm -f QQ.deb
                log "懒大猫服务器下载失败或包架构不符，改用官方源下载..."
                if [ "${system_arch}" = "amd64" ]; then
                    qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_amd64_01.deb"
                elif [ "${system_arch}" = "arm64" ]; then
                    qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_arm64_01.deb"
                else
                    die "无法确定 QQ.deb 下载地址: 不支持的架构 ${system_arch}。"
                fi
                fetch QQ.deb "${qq_download_url}" || die "QQ.deb 下载失败。"
                verify_deb QQ.deb || {
                    rm -f QQ.deb
                    die "QQ.deb 校验失败(不是有效的deb包)，请重新运行脚本。"
                }
                deb_arch_ok QQ.deb || {
                    rm -f QQ.deb
                    die "官方源 QQ.deb 架构异常(期望 ${system_arch})，请反馈。"
                }
                log "QQ.deb 下载成功。"
            fi
        fi

        log "正在安装 LinuxQQ ..."
        if ! apt-get install -f -y --allow-downgrades -qq ./QQ.deb; then
            log "警告: LinuxQQ 首次安装失败，尝试修复依赖后重试..."
            apt-get -f install -y -qq >/dev/null 2>&1 || true
            if ! apt-get install -f -y --allow-downgrades -qq ./QQ.deb; then
                log "错误: LinuxQQ 安装失败，依赖分析如下(不实际安装):"
                apt-get install -y --allow-downgrades --simulate ./QQ.deb 2>&1 \
                    | grep -v "^Reading\|^Building" | sed 's/^/    /'
                die "LinuxQQ 安装失败(apt-get)，请根据上方依赖分析检查系统软件源，或先手动安装缺失的依赖。"
            fi
            log "依赖修复后 LinuxQQ 安装成功。"
        fi
        install_qq_runtime_deps

    elif [ "${package_manager}" = "dnf" ]; then
        log "内部源未提供 rpm，使用官方源..."
        if [ "${system_arch}" = "amd64" ]; then
            qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_x86_64_01.rpm"
        elif [ "${system_arch}" = "arm64" ]; then
            qq_download_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_aarch64_01.rpm"
        else
            die "无法确定 QQ.rpm 下载地址: 不支持的架构 ${system_arch}。"
        fi

        if [ -f "QQ.rpm" ]; then
            if verify_rpm QQ.rpm; then
                log "检测到已下载且完整的 QQ.rpm，跳过下载。"
            else
                log "警告: 本地 QQ.rpm 不完整或已损坏，删除后重新下载。"
                rm -f QQ.rpm
            fi
        fi

        if [ ! -f "QQ.rpm" ]; then
            fetch QQ.rpm "${qq_download_url}" || die "QQ.rpm 下载失败。"
            verify_rpm QQ.rpm || {
                rm -f QQ.rpm
                die "QQ.rpm 校验失败(不是有效的rpm包)，请重新运行脚本。"
            }
            log "QQ.rpm 下载成功"
        fi

        log "正在安装 LinuxQQ ..."
        dnf localinstall -y ./QQ.rpm \
            || die "LinuxQQ 安装失败(dnf localinstall)，请检查上方错误输出。"
    fi

    # 安装结果双重校验: 即使包管理器返回成功，也要确认 qq 确实装上了
    if ! verify_qq_installed; then
        die "LinuxQQ 安装失败: 未检测到 qq 可执行文件或已安装的软件包。"
    fi
    log "LinuxQQ 安装成功。"
}

function download_launcher_so() {
    cd "${INSTALL_DIR}" || die "无法进入安装目录 ${INSTALL_DIR}。"
    get_system_arch

    log "开始从懒大猫服务器下载 launcher.cpp ..."
    if ! fetch launcher.cpp "${INTERNAL_BASE}/launcher.cpp"; then
        log "懒大猫服务器下载失败，尝试备用下载..."
        network_test
        cpp_url="https://raw.githubusercontent.com/NapNeko/napcat-linux-launcher/refs/heads/main/launcher.cpp"
        if [ -n "${target_proxy}" ]; then
            cpp_url="${target_proxy}/${cpp_url}"
        fi
        fetch launcher.cpp "${cpp_url}" || die "launcher.cpp 下载失败，请检查网络。"
    fi
    [ -s launcher.cpp ] || die "launcher.cpp 下载异常(文件为空)，请重新运行脚本。"
    log "launcher.cpp 下载成功。"

    log "正在编译 libnapcat_launcher.so ..."
    if ! g++ -shared -fPIC launcher.cpp -o libnapcat_launcher.so -ldl; then
        die "libnapcat_launcher.so 编译失败，请检查g++是否安装或源码是否有误。"
    fi
    [ -s libnapcat_launcher.so ] || die "libnapcat_launcher.so 编译异常(文件为空)。"
    log "libnapcat_launcher.so 编译成功。"
}

function verify_installation() {
    local ok=1
    if [ ! -x "${INSTALL_DIR}/start_napcat.sh" ]; then
        log "错误: 缺少启动脚本 ${INSTALL_DIR}/start_napcat.sh"
        ok=0
    fi
    if [ ! -s "${INSTALL_DIR}/libnapcat_launcher.so" ]; then
        log "错误: 缺少 ${INSTALL_DIR}/libnapcat_launcher.so"
        ok=0
    fi
    if [ -z "$(ls -A "${INSTALL_DIR}/napcat" 2>/dev/null)" ]; then
        log "错误: 缺少 ${INSTALL_DIR}/napcat 目录(或目录为空)"
        ok=0
    fi
    if ! verify_qq_installed; then
        log "错误: 未检测到已安装的 LinuxQQ"
        ok=0
    fi
    if [ "$ok" -ne 1 ]; then
        die "安装结果校验失败，NapCat 未能成功安装。"
    fi
    log "安装校验通过: LinuxQQ / NapCat / libnapcat_launcher.so 均已就绪。"
}

# ---------------- 主流程 ----------------
install_dependency
download_napcat
install_linuxqq
download_launcher_so

cat > "${INSTALL_DIR}/start_napcat.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

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
[ -s "${INSTALL_DIR}/start_napcat.sh" ] || die "生成 start_napcat.sh 失败。"

chmod +x "${INSTALL_DIR}/start_napcat.sh" || die "设置 start_napcat.sh 可执行权限失败。"
cp "${INSTALL_DIR}/start_napcat.sh" "${INSTALL_DIR}/launcher.sh" || die "复制 launcher.sh 失败。"

verify_installation

log "启动命令: cd ${INSTALL_DIR} && bash ${INSTALL_DIR}/start_napcat.sh"

log "启动命令2: cd ${INSTALL_DIR} && bash ${INSTALL_DIR}/launcher.sh"

# 安装完成自动启动（前台运行）
log "安装完成，正在前台启动 NapCat ..."
cd "${INSTALL_DIR}" || die "无法进入目录 ${INSTALL_DIR}。"
bash "${INSTALL_DIR}/start_napcat.sh"
napcat_exit=$?
if [ "$napcat_exit" -ne 0 ]; then
    log "错误: NapCat 启动失败(退出码 ${napcat_exit})，请检查上方输出。"
fi
exit "$napcat_exit"
