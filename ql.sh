#!/bin/bash
set -e # 任何命令失败时立即退出脚本 (在函数内部，如果函数返回非零，也会退出脚本)

# --- 配置变量 ---
QL_DIR="/ql"                            # 青龙面板安装目录
VENV_NAME="open.venv"                   # Python 虚拟环境名称
VENV_PATH="${QL_DIR}/${VENV_NAME}"      # Python 虚拟环境绝对路径 (在QL_DIR下)
QL_STATIC_TEMP_DIR="/tmp/qinglong_static_temp" # 临时静态资源下载目录
NODEJS_VERSION="20.x"                   # Node.js 版本
QL_START_SCRIPT="/root/ql.sh"           # 青龙面板启动脚本的最终位置
QL_AUTOSTART_LOG="/var/log/qinglong_autostart.log" # 自启动日志文件

# URL for script update
UPDATE_URL="https://raw.githubusercontent.com/jfjdjdhsj/clashtubiao/refs/heads/main/ql.sh"
SCRIPT_NAME=$(basename "$0") # Get the script's filename
SCRIPT_PATH=$(readlink -f "$0") # Get the script's absolute path

# --- 辅助函数 ---

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误：此脚本需要 root 权限运行。请使用 'sudo ./$(basename "$0")' 或切换到 root 用户后运行。"
        return 1
    fi
    return 0
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 显示主菜单
display_menu() {
    echo ""
    echo "--- 青龙面板管理菜单 ---"
    echo "1. install          - 安装青龙面板"
    echo "2. uninstall        - 卸载青龙面板"
    echo "3. start            - 启动青龙面板服务并显示日志"
    echo "4. stop             - 停止青龙面板服务"
    echo "5. set_autostart    - 设置青龙面板开机自启动"
    echo "6. remove_autostart - 去除青龙面板开机自启动"
    echo "7. update           - 更新当前管理脚本"
    echo "8. exit             - 退出脚本"
    echo "--------------------------"
    echo -n "请输入你的选择 (1-8 或命令名称): "
}

# 检查当前是否在虚拟环境中，如果是则退出
check_and_deactivate_venv() {
    if [ -n "$VIRTUAL_ENV" ]; then
        echo "检测到当前处于虚拟环境 '$VIRTUAL_ENV'。正在退出..."
        deactivate 2>/dev/null
        echo "已退出虚拟环境。"
    fi
}

# --- 青龙面板操作函数 ---

# 安装青龙面板
install_qinglong() {
    if ! check_root; then return 1; fi
    echo "--- 开始安装青龙面板 ---"

    # 在安装前检查并退出任何活动虚拟环境
    check_and_deactivate_venv

    # 1. 检查并安装 Git
    echo "--- 1. 检查并安装 Git ---"
    if ! command -v git &> /dev/null; then
        apt update
        apt install -y git
        echo "Git 安装成功。"
    else
        echo "Git 已安装。"
    fi

    # 2. 克隆青龙面板仓库
    echo "--- 2. 克隆青龙面板仓库到 $QL_DIR ---"
    if [ -d "$QL_DIR" ]; then
        read -p "警告：目录 '$QL_DIR' 已存在。是否删除并重新克隆？(y/N): " confirm_delete
        if [[ "$confirm_delete" == [yY] ]]; then
            echo "正在删除旧的 '$QL_DIR' 目录..."
            rm -rf "$QL_DIR"
        else
            echo "取消克隆。请手动处理 '$QL_DIR' 目录或选择删除。"
            return 1
        fi
    fi
    git clone --depth=1 -b develop https://github.com/whyour/qinglong.git "$QL_DIR"
    echo "青龙面板仓库克隆到 '$QL_DIR' 成功。"

    # 3. 安装 Python3, pip 和 venv，并创建/激活虚拟环境
    echo "--- 3. 安装 Python3, pip 和 python3-venv ---"
    apt update
    apt install -y python3 python3-pip python3-venv

    echo "--- 创建 Python 虚拟环境 '$VENV_PATH' ---"
    if [ -d "$VENV_PATH" ]; then
        echo "虚拟环境 '$VENV_PATH' 已存在，跳过创建。"
    else
        # 确保在 QL_DIR 目录下创建虚拟环境
        (cd "$QL_DIR" && python3 -m venv "$VENV_NAME")
        echo "虚拟环境 '$VENV_PATH' 创建成功。"
    fi
    
    # 激活当前会话的虚拟环境
    source "$VENV_PATH/bin/activate"
    echo "虚拟环境已激活 (当前会话)。"

    echo "--- 将虚拟环境激活命令添加到 ~/.bashrc ---"
    # 确保添加到 ~/.bashrc 的是绝对路径
    if ! grep -q "source $VENV_PATH/bin/activate" ~/.bashrc; then
        echo "source $VENV_PATH/bin/activate" >> ~/.bashrc
        echo "已将虚拟环境激活命令添加到 ~/.bashrc。"
    else
        echo "虚拟环境激活命令已存在于 ~/.bashrc，跳过添加。"
    fi

    # 4. 安装 Node.js 和 pnpm 相关包
    echo "--- 4. 安装 Node.js ${NODEJS_VERSION} ---"
    # 添加 NodeSource PPA
    curl -fsSL "https://deb.nodesource.com/setup_${NODEJS_VERSION}" | bash -
    apt install -y nodejs

    echo "--- 安装 pnpm, pm2, ts-node (全局) ---"
    npm i -g pnpm@8.3.1 pm2 ts-node

    echo "--- 在 '$QL_DIR' 目录安装 pnpm 依赖 ---"
    # 确保进入青龙目录，否则 pnpm install 会在当前目录执行
    (
        cd "$QL_DIR"
        pnpm install --prod
    )
    echo "pnpm 依赖安装完成。"

    # 5. 设置青龙相关环境变量到 ~/.bashrc
    echo "--- 5. 添加青龙相关环境变量到 ~/.bashrc ---"
    local env_vars=(
        "export QL_DIR=$QL_DIR"
        "export QL_DATA_DIR=$QL_DIR/data"
        "export PNPM_HOME=/root/.local/share/pnpm"
        "export PATH=/root/.local/share/pnpm:/root/.local/share/pnpm/global/5/node_modules:\$PATH"
        "export NODE_PATH=$QL_DIR/node_modules:/usr/local/bin:/usr/local/pnpm-global/5/node_modules:/usr/local/lib/node_modules:/root/.local/share/pnpm/global/5/node_modules"
    )

    for var in "${env_vars[@]}"; do
        # 针对 grep 转义特殊字符
        local escaped_var=$(echo "$var" | sed 's/[\/&]/\\&/g')
        if ! grep -q "^${escaped_var}$" ~/.bashrc; then
            echo "$var" >> ~/.bashrc
            echo "已添加: $var"
        else
            echo "已存在: $var，跳过添加。"
        fi
    done
    echo "青龙环境变量已添加到 ~/.bashrc。请注意：这些变量在当前脚本执行环境中不会立即生效。你需要重新登录或运行 'source ~/.bashrc' 来加载它们。"

    # 6. 安装其他必要的 apt 包
    echo "--- 6. 安装其他必要的 apt 包 ---"
    apt update
    apt install -y --no-install-recommends \
        bash \
        coreutils \
        wget \
        tzdata \
        perl \
        openssl \
        nginx \
        jq \
        openssh-server \
        procps \
        netcat-openbsd \
        unzip
    echo "其他 apt 包安装完成。"

    # 7. 设置系统时区
    echo "--- 7. 设置系统时区为 Asia/Shanghai ---"
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata # 应用时区更改
    echo "时区设置完成。"

    # 8. 清理缓存
    echo "--- 8. 清理不必要的缓存 ---"
    rm -rf /root/.pnpm-store && rm -rf /root/.local/share/pnpm/store && rm -rf /root/.cache
    echo "缓存清理完成。"

    # 9. 设置 ulimit
    echo "--- 9. 设置 ulimit 为 0 ---"
    ulimit -c 0
    echo "ulimit 已设置。"

    # 10. 配置青龙面板
    echo "--- 10. 配置青龙面板 ---"
    echo "--- 设置 '$QL_DIR/shell/' 和 '$QL_DIR/docker/' 目录内脚本的执行权限 ---"
    chmod 777 "$QL_DIR"/shell/*.sh
    chmod 777 "$QL_DIR"/docker/*.sh
    echo "执行权限设置完成。"

    echo "--- 拉取青龙面板静态资源 ---"
    if [ -d "$QL_STATIC_TEMP_DIR" ]; then
        echo "临时静态资源目录 '$QL_STATIC_TEMP_DIR' 已存在，正在删除..."
        rm -rf "$QL_STATIC_TEMP_DIR"
    fi
    git clone --depth=1 -b develop https://github.com/whyour/qinglong-static.git "$QL_STATIC_TEMP_DIR"

    echo "--- 复制静态资源到 '$QL_DIR/static' 并清理临时文件 ---"
    mkdir -p "$QL_DIR"/static
    cp -rf "$QL_STATIC_TEMP_DIR"/* "$QL_DIR"/static
    rm -rf "$QL_STATIC_TEMP_DIR"
    echo "静态资源拉取和配置完成。"

    echo "--- 复制启动脚本到 $QL_START_SCRIPT ---"
    cp "$QL_DIR"/docker/docker-entrypoint.sh "$QL_START_SCRIPT"
    chmod +x "$QL_START_SCRIPT"
    echo "青龙面板安装完成。你可以使用 './$SCRIPT_NAME start' 启动它。"
    echo "如果需要开机自启动，请选择菜单中的 '设置开机自启动' 选项。"
}

# 卸载青龙面板
uninstall_qinglong() {
    if ! check_root; then return 1; fi
    echo "--- 开始卸载青龙面板 ---"

    echo "--- 1. 尝试停止青龙面板服务 ---"
    stop_qinglong # 调用停止函数
    sleep 2 # 稍作等待确保进程停止

    echo "--- 2. 尝试去除开机自启动配置 ---"
    remove_qinglong_autostart_entry # 调用去除自启动函数
    sleep 1

    echo "--- 3. 删除青龙面板安装目录 ('$QL_DIR') ---"
    if [ -d "$QL_DIR" ]; then
        read -p "确定要删除青龙面板安装目录 '$QL_DIR' 吗？这会删除所有数据！(y/N): " confirm_delete
        if [[ "$confirm_delete" == [yY] ]]; then
            rm -rf "$QL_DIR"
            echo "目录 '$QL_DIR' 已删除。"
        else
            echo "取消删除目录 '$QL_DIR'。"
        fi
    else
        echo "目录 '$QL_DIR' 不存在，跳过删除。"
    fi

    echo "--- 4. 删除 Python 虚拟环境 ('$VENV_PATH') ---"
    if [ -d "$VENV_PATH" ]; then
        rm -rf "$VENV_PATH"
        echo "虚拟环境 '$VENV_PATH' 已删除。"
    else
        echo "虚拟环境 '$VENV_PATH' 不存在，跳过删除。"
    fi

    echo "--- 5. 删除青龙启动脚本 ('$QL_START_SCRIPT') ---"
    if [ -f "$QL_START_SCRIPT" ]; then
        rm -f "$QL_START_SCRIPT"
        echo "启动脚本 '$QL_START_SCRIPT' 已删除。"
    else
        echo "启动脚本 '$QL_START_SCRIPT' 不存在，跳过删除。"
    fi

    echo "--- 6. 清理 ~/.bashrc 中的环境变量 ---"
    local env_vars_to_remove=(
        "source $VENV_PATH/bin/activate"
        "export QL_DIR=$QL_DIR"
        "export QL_DATA_DIR=$QL_DIR/data"
        "export PNPM_HOME=/root/.local/share/pnpm"
        "export PATH=/root/.local/share/pnpm:/root/.local/share/pnpm/global/5/node_modules:\$PATH"
        "export NODE_PATH=$QL_DIR/node_modules:/usr/local/bin:/usr/local/pnpm-global/5/node_modules:/usr/local/lib/node_modules:/root/.local/share/pnpm/global/5/node_modules"
    )
    for var in "${env_vars_to_remove[@]}"; do
        # 针对 grep 和 sed 转义特殊字符
        local escaped_var=$(echo "$var" | sed 's/[\/&]/\\&/g')
        if grep -q "^${escaped_var}$" ~/.bashrc; then
            sed -i "/^${escaped_var}$/d" ~/.bashrc
            echo "已从 ~/.bashrc 移除: $var"
        fi
    done
    echo "~/.bashrc 清理完成。请注意，一些全局安装的包 (如 Node.js, pnpm, pm2, ts-node) 未被移除，你可能需要手动卸载。"
    echo "--- 青龙面板卸载完成。---"
}

# 启动青龙面板服务
start_qinglong() {
    if ! check_root; then return 1; fi
    echo "--- 开始启动青龙面板 ---"

    echo "--- 1. 确保青龙启动脚本存在并可执行 ---"
    if [ ! -f "$QL_START_SCRIPT" ]; then
        echo "错误：青龙启动脚本 '$QL_START_SCRIPT' 不存在。请先执行安装命令。"
        return 1
    fi
    if [ ! -x "$QL_START_SCRIPT" ]; then
        chmod +x "$QL_START_SCRIPT"
        echo "已为 '$QL_START_SCRIPT' 添加执行权限。"
    fi

    echo "--- 2. 尝试激活虚拟环境并加载环境变量 (当前会话) ---"
    # 对于当前交互式会话，确保环境变量和虚拟环境被加载
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "警告：未找到虚拟环境激活脚本 '$VENV_PATH/bin/activate'。尝试在非虚拟环境启动。"
    fi
    source ~/.bashrc 2>/dev/null # 尝试加载 bashrc 中的环境变量

    echo "--- 3. 启动青龙面板服务 (pm2 管理，后台运行) ---"
    # docker-entrypoint.sh 脚本内部通常会使用 pm2 来启动青龙，并使其在后台运行
    # 所以直接执行该脚本即可，不需要额外的 &
    (
        cd "$QL_DIR" # 切换到青龙目录执行启动脚本
        "$QL_START_SCRIPT"
    )
    
    echo "青龙面板启动命令已执行。等待服务初始化..."
    sleep 5 # 稍作等待，让 pm2 有时间启动服务

    echo "--- 4. 显示青龙面板实时日志 (按 Ctrl+C 停止查看日志并返回菜单) ---"
    if command_exists pm2; then
        echo "pm2 进程列表:"
        pm2 list
        echo ""
        echo "如果青龙未显示在 pm2 列表中，请检查 '$QL_START_SCRIPT' 的执行情况。"
        echo "正在显示 'qinglong' 进程的日志。按 Ctrl+C 停止查看日志。"
        # pm2 logs --raw 默认会阻塞当前终端，直到 Ctrl+C
        pm2 logs qinglong --raw || echo "无法获取 'qinglong' 进程日志，可能服务未以该名称启动或 pm2 未运行。"
    else
        echo "警告：pm2 命令未找到。无法显示实时日志。请手动检查青龙面板状态。"
        echo "你可以尝试访问服务器IP:5700来检查青龙面板Web界面。"
    fi

    echo "--- 青龙面板启动操作完成。---"
}

# 停止青龙面板服务
stop_qinglong() {
    if ! check_root; then return 1; fi
    echo "--- 开始停止青龙面板 ---"

    echo "--- 1. 尝试激活虚拟环境并加载环境变量 (当前会话) ---"
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "警告：未找到虚拟环境激活脚本 '$VENV_PATH/bin/activate'。尝试在非虚拟环境停止。"
    fi
    source ~/.bashrc 2>/dev/null # 尝试加载 bashrc 中的环境变量

    echo "--- 2. 尝试停止 pm2 中的青龙进程 ---"
    if command_exists pm2; then
        if pm2 list | grep -q "qinglong"; then
            echo "找到 pm2 中的 'qinglong' 进程，正在停止并删除..."
            pm2 stop qinglong
            pm2 delete qinglong # 停止并从 pm2 列表中删除
            echo "青龙面板服务已停止并从 pm2 列表中移除。"
        else
            echo "pm2 中未找到名为 'qinglong' 的进程。"
            echo "尝试停止所有 pm2 进程..."
            pm2 stop all && pm2 delete all
            echo "所有 pm2 进程已停止并删除。"
        fi
    else
        echo "警告：pm2 命令未找到。尝试通过杀掉 Node.js 进程来停止青龙面板..."
        PIDS=$(pgrep -f "node /ql/build/app.js") # 根据青龙实际启动命令调整
        if [ -n "$PIDS" ]; then
            echo "找到以下 Node.js 进程 (PIDs: $PIDS)，正在终止..."
            kill "$PIDS"
            echo "Node.js 进程已终止。"
        else
            echo "未找到青龙面板运行进程。可能服务未运行。"
        fi
    fi
    echo "--- 青龙面板停止操作完成。---"
}

# 设置开机自启动
set_qinglong_autostart_entry() {
    if ! check_root; then return 1; fi
    echo "--- 开始设置青龙面板开机自启动 ---"

    if [ ! -f "$QL_START_SCRIPT" ]; then
        echo "错误：青龙启动脚本 '$QL_START_SCRIPT' 不存在。请先执行安装命令。"
        return 1
    fi

    # 清除旧的自启动配置，避免重复
    remove_qinglong_autostart_entry

    # 使用 bash -lc 确保 cron 作业在登录 shell 环境中运行，从而加载 ~/.bashrc
    local CRON_JOB="@reboot /bin/bash -lc \"$QL_START_SCRIPT > $QL_AUTOSTART_LOG 2>&1\""

    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    if [ $? -eq 0 ]; then
        echo "青龙面板开机自启动已成功设置。"
        echo "启动日志将被记录到 '$QL_AUTOSTART_LOG'。"
    else
        echo "错误：设置青龙面板开机自启动失败。请检查 crontab 配置或权限。"
        return 1
    fi
    echo "--- 青龙面板开机自启动设置完成。---"
}

# 去除开机自启动
remove_qinglong_autostart_entry() {
    if ! check_root; then return 1; fi
    echo "--- 开始去除青龙面板开机自启动 ---"

    # 构建用于匹配的 cron job 字符串
    local CRON_JOB_PATTERN="@reboot /bin/bash -lc \"$QL_START_SCRIPT > $QL_AUTOSTART_LOG 2>&1\""
    # 针对 grep 和 sed 转义特殊字符
    local ESCAPED_CRON_JOB_PATTERN=$(echo "$CRON_JOB_PATTERN" | sed 's/[\/&]/\\&/g')

    if crontab -l 2>/dev/null | grep -q "$ESCAPED_CRON_JOB_PATTERN"; then
        crontab -l 2>/dev/null | grep -v "$ESCAPED_CRON_JOB_PATTERN" | crontab -
        if [ $? -eq 0 ]; then
            echo "青龙面板开机自启动已成功去除。"
        else
            echo "错误：去除青龙面板开机自启动失败。请检查 crontab 配置或权限。"
            return 1
        fi
    else
        echo "未找到青龙面板的开机自启动配置，无需去除。"
    fi
    echo "--- 青龙面板开机自启动去除完成。---"
}

# 退出脚本
exit_script() {
    echo "--- 退出脚本 ---"
    exit 0
}

# 更新脚本
update_script() {
    echo "--- 开始更新脚本 ---"
    echo "将从以下 URL 更新脚本: ${UPDATE_URL}"
    echo "当前脚本路径: ${SCRIPT_PATH}"

    read -p "确定要更新脚本吗？(y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "脚本更新已取消。"
        return 0
    fi

    if ! command_exists curl && ! command_exists wget; then
        echo "错误：未找到 'curl' 或 'wget' 命令，无法下载更新。请安装其中一个。"
        return 1
    fi

    TEMP_SCRIPT=$(mktemp)
    if command_exists curl; then
        curl -sSL "${UPDATE_URL}" -o "${TEMP_SCRIPT}"
    elif command_exists wget; then
        wget -q -O "${TEMP_SCRIPT}" "${UPDATE_URL}"
    fi

    if [ $? -ne 0 ]; then
        echo "错误：下载更新脚本失败。请检查网络连接或 URL 是否正确。"
        rm -f "${TEMP_SCRIPT}"
        return 1
    fi

    # 替换当前运行的脚本
    mv "${TEMP_SCRIPT}" "${SCRIPT_PATH}"
    if [ $? -ne 0 ]; then
        echo "错误：无法将临时脚本移动到 '${SCRIPT_PATH}'。请检查文件权限。"
        rm -f "${TEMP_SCRIPT}"
        return 1
    fi

    chmod +x "${SCRIPT_PATH}"
    echo "脚本已成功更新。请重新运行此脚本以使用新版本。"
    exit 0 # 退出当前运行的旧版本脚本
}

# 处理命令
handle_command() {
    case "$1" in
        1|install)
            install_qinglong
            ;;
        2|uninstall)
            uninstall_qinglong
            ;;
        3|start)
            start_qinglong
            ;;
        4|stop)
            stop_qinglong
            ;;
        5|set_autostart)
            set_qinglong_autostart_entry
            ;;
        6|remove_autostart)
            remove_qinglong_autostart_entry
            ;;
        7|update)
            update_script # update_script 会自行退出
            ;;
        8|exit)
            exit_script
            ;;
        *)
            echo "无效的命令或选择: '$1'。请重新输入。"
            ;;
    esac
}

# --- 脚本主逻辑 ---

# 如果有命令行参数，则先执行该参数对应的命令
if [ -n "$1" ]; then
    handle_command "$1"
    # 如果命令不是 update 或 exit，则继续进入交互式菜单
    if [[ "$1" != "update" && "$1" != "exit" && "$1" != "7" && "$1" != "8" ]]; then
        echo ""
        read -p "按 Enter 返回主菜单..."
    fi
fi

# 进入主循环，显示菜单并等待用户输入
while true; do
    clear # 清屏以保持菜单整洁
    display_menu
    read -r choice

    # 将数字选择转换为对应的命令名称，以便 handle_command 处理
    case "$choice" in
        1) command_to_execute="install" ;;
        2) command_to_execute="uninstall" ;;
        3) command_to_execute="start" ;;
        4) command_to_execute="stop" ;;
        5) command_to_execute="set_autostart" ;;
        6) command_to_execute="remove_autostart" ;;
        7) command_to_execute="update" ;;
        8) command_to_execute="exit" ;;
        *) command_to_execute="$choice" ;; # 否则直接使用用户输入的命令名称
    esac

    handle_command "$command_to_execute"

    # 如果命令不是 update 或 exit，则暂停并等待用户确认返回菜单
    if [[ "$command_to_execute" != "update" && "$command_to_execute" != "exit" ]]; then
        echo ""
        read -p "按 Enter 返回主菜单..."
    fi
done
