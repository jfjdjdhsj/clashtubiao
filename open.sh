#!/bin/bash

# 定义 Open-WebUI 所需的 Python 版本
WEBUI_INSTALL_PYTHON_VERSION="3.11.11"
# 定义虚拟环境名称
VENV_NAME="open.venv"

# 默认 Open-WebUI 目录为当前目录，用于 install/uninstall/start/stop
# 对于 autostart，用户需要根据说明设置其绝对路径
WEBUI_CURRENT_DIR="$(pwd)"

# URL for script update
UPDATE_URL="https://raw.githubusercontent.com/jfjdjdhsj/clashtubiao/refs/heads/main/open.sh"
SCRIPT_NAME=$(basename "$0") # Get the script's filename
SCRIPT_PATH=$(readlink -f "$0") # Get the script's absolute path

# --- 辅助函数 ---

# 显示用法说明
display_menu() {
    echo ""
    echo "--- Open-WebUI 管理菜单 ---"
    echo "1. install      - 安装 Open-WebUI"
    echo "2. uninstall    - 卸载 Open-WebUI"
    echo "3. start        - 启动 Open-WebUI 服务"
    echo "4. stop         - 停止 Open-WebUI 服务"
    echo "5. autostart    - 显示 Open-WebUI 自启动配置的说明"
    echo "6. update       - 更新当前脚本"
    echo "7. exit         - 退出脚本"
    echo "--------------------------"
    echo -n "请输入你的选择 (1-7 或命令名称): "
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# --- 主要功能函数 ---

# 安装 Open-WebUI
install_webui() {
    echo "--- 开始安装 Open-WebUI ---"

    # 1. 检查并安装 uv
    echo "--- 1. 检查并安装 uv ---"
    if ! command_exists uv; then
        echo "uv 未安装，正在使用 pip 安装 uv..."
        pip install uv --break-system-packages
        if [ $? -ne 0 ]; then
            echo "错误：uv 安装失败。请检查 pip 是否可用以及系统权限。"
            return 1 # 返回错误码
        fi
        echo "uv 安装成功。"
    else
        echo "uv 已安装。"
    fi

    # 2. 检查并安装指定版本的 Python
    echo "--- 2. 检查并安装 Python ${WEBUI_INSTALL_PYTHON_VERSION} ---"
    PYTHON_INSTALLED=false
    if command_exists uv; then
        INSTALLED_PYTHONS=$(uv python list --json 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$INSTALLED_PYTHONS" ]; then
            # 使用 Python 脚本解析 JSON，严格检查版本
            # 注意：这里假设系统有 python3 可用
            PYTHON_VERSION_CHECK_SCRIPT='
import json
import sys
data = json.load(sys.stdin)
found = False
for p in data:
    if p.get("version") == sys.argv[1]:
        found = True
        break
print("True" if found else "False")
            '
            if echo "$INSTALLED_PYTHONS" | python3 -c "$PYTHON_VERSION_CHECK_SCRIPT" "$WEBUI_INSTALL_PYTHON_VERSION" | grep -q "True"; then
                PYTHON_INSTALLED=true
            fi
        fi
    fi

    if [ "$PYTHON_INSTALLED" = true ]; then
        echo "Python ${WEBUI_INSTALL_PYTHON_VERSION} 已通过 uv 安装。"
    else
        echo "Python ${WEBUI_INSTALL_PYTHON_VERSION} 未安装或版本不匹配，正在安装..."
        uv python install "${WEBUI_INSTALL_PYTHON_VERSION}"
        if [ $? -ne 0 ]; then
            echo "错误：Python ${WEBUI_INSTALL_PYTHON_VERSION} 安装失败。请检查 uv 配置或网络连接。"
            return 1 # 返回错误码
        fi
        echo "Python ${WEBUI_INSTALL_PYTHON_VERSION} 安装成功。"
    fi

    # 3. 设置 UV_LINK_MODE 环境变量
    echo "--- 3. 设置 UV_LINK_MODE 环境变量 ---"
    export UV_LINK_MODE=copy
    echo "UV_LINK_MODE=copy 已设置。"

    # 4. 创建并激活虚拟环境
    echo "--- 4. 创建并激活虚拟环境 ('${VENV_NAME}' 使用 Python ${WEBUI_INSTALL_PYTHON_VERSION}) ---"
    if [ -d "${VENV_NAME}" ]; then
        echo "${VENV_NAME} 目录已存在，跳过创建虚拟环境。"
    else
        uv venv -p "${WEBUI_INSTALL_PYTHON_VERSION}" "${VENV_NAME}"
        if [ $? -ne 0 ]; then
            echo "错误：虚拟环境创建失败。"
            return 1 # 返回错误码
        fi
        echo "虚拟环境 '${VENV_NAME}' 已创建。"
    fi
    source "${VENV_NAME}/bin/activate"
    echo "虚拟环境 '${VENV_NAME}' 已激活。"

    # 5. 安装 open-webui
    echo "--- 5. 正在安装 open-webui ---"
    uv pip install open-webui
    if [ $? -ne 0 ]; then
        echo "错误：open-webui 安装失败。请检查网络连接或依赖问题。"
        return 1 # 返回错误码
    fi
    echo "open-webui 安装成功。"

    # 6. 设置 Open-WebUI 环境变量 (这些变量通常在启动时设置，但安装时设置一次也无妨)
    echo "--- 6. 设置 Open-WebUI 环境变量 ---"
    export RAG_EMBEDDING_ENGINE=ollama
    export AUDIO_STT_ENGINE=openai
    echo "Open-WebUI 环境变量已设置 (临时生效)。"

    echo "--- Open-WebUI 安装完成。---"
}

# 卸载 Open-WebUI
uninstall_webui() {
    echo "--- 开始卸载 Open-WebUI ---"

    echo "--- 1. 尝试退出虚拟环境 (如果已激活) ---"
    # 尝试执行 deactivate，并忽略错误输出
    deactivate 2>/dev/null
    echo "已尝试退出虚拟环境。"

    echo "--- 2. 删除 Open-WebUI 虚拟环境目录 ('${VENV_NAME}') ---"
    if [ -d "${VENV_NAME}" ]; then
        rm -rf "${VENV_NAME}"
        echo "Open-WebUI 虚拟环境 ('${VENV_NAME}') 已成功删除。"
    else
        echo "未找到 '${VENV_NAME}' 虚拟环境目录，可能 Open-WebUI 未安装或已卸载。"
    fi

    # 如果你需要卸载 uv 本身，可以取消注释下面这行（但通常不建议，除非你不再使用 uv）
    # echo "--- 3. 卸载 uv (可选) ---"
    # pip uninstall uv --break-system-packages

    echo "--- Open-WebUI 卸载完成。---"
}

# 启动 Open-WebUI 服务
start_webui() {
    echo "--- 开始启动 Open-WebUI ---"

    echo "--- 1. 激活虚拟环境 ('${VENV_NAME}') ---"
    if [ -f "${VENV_NAME}/bin/activate" ]; then
        source "${VENV_NAME}/bin/activate"
    else
        echo "错误：未找到虚拟环境激活脚本。请确保 Open-WebUI 已安装，并且你处于正确的目录。"
        return 1 # 返回错误码
    fi
    echo "虚拟环境 '${VENV_NAME}' 已激活。"

    echo "--- 2. 设置 Open-WebUI 环境变量 ---"
    export RAG_EMBEDDING_ENGINE=ollama
    export AUDIO_STT_ENGINE=openai
    echo "Open-WebUI 环境变量已设置。"

    echo "--- 3. 启动 Open-WebUI 服务 (将在前台运行并显示日志) ---"
    # 确保 open-webui 命令在激活的虚拟环境中可用
    if command_exists open-webui; then
        open-webui serve
        # 当 open-webui serve 停止后，会继续执行这里
        echo "Open-WebUI 服务已停止或被中断。"
    else
        echo "错误：'open-webui' 命令未找到。请确保 Open-WebUI 已正确安装在虚拟环境中。"
        return 1 # 返回错误码
    fi
}

# 停止 Open-WebUI 服务
stop_webui() {
    echo "--- 开始停止 Open-WebUI ---"

    echo "--- 1. 尝试停止 Open-WebUI 服务 ---"
    # 查找 open-webui serve 进程并终止
    # 使用完整的路径来避免误杀，但 pgrep -f 已经足够精确
    PID=$(pgrep -f "open-webui serve")

    if [ -n "$PID" ]; then
        echo "找到 Open-WebUI 进程 (PID: $PID)，正在终止..."
        kill "$PID"
        if [ $? -eq 0 ]; then
            echo "Open-WebUI 服务已停止。"
        else
            echo "错误：无法终止 Open-WebUI 进程 $PID。可能需要手动终止。"
            return 1 # 返回错误码
        fi
    else
        echo "未找到 Open-WebUI 运行进程。"
    fi
    echo "--- Open-WebUI 停止完成。---"
}

# 显示自启动配置说明
autostart_webui_instructions() {
    echo "--- Open-WebUI 自启动配置说明 ---"
    echo "要配置 Open-WebUI 自启动，你需要将以下命令添加到你的系统自启动机制中 (例如 crontab @reboot 或 systemd 服务)。"
    echo ""
    echo "重要提示：请将以下示例脚本中的 'WEBUI_DIR=\"$(pwd)\"' 替换为你的 Open-WebUI 实际安装目录的绝对路径。"
    echo "例如，如果你的 Open-WebUI 脚本在此目录：${WEBUI_CURRENT_DIR}"
    echo "你需要在以下命令中替换它。"
    echo ""
    echo "1. 创建一个自启动脚本文件 (例如: openwebui_autostart.sh):"
    echo "   nano openwebui_autostart.sh"
    echo ""
    echo "2. 将以下内容粘贴到 openwebui_autostart.sh 文件中:"
    echo "---------------------------------------------------------"
    echo "#!/bin/bash"
    echo ""
    echo "WEBUI_DIR=\"${WEBUI_CURRENT_DIR}\" # <--- 重要：请确认这里是你的 Open-WebUI 实际安装目录的绝对路径，如果脚本不是在此目录运行，请修改此行"
    echo "VENV_NAME=\"${VENV_NAME}\""
    echo "LOG_FILE=\"\$WEBUI_DIR/open-webui_autostart.log\""
    echo ""
    echo "echo \"\$(date): 尝试自启动 Open-WebUI...\" >> \"\$LOG_FILE\""
    echo ""
    echo "# 切换到 Open-WebUI 目录"
    echo "cd \"\$WEBUI_DIR\" || { echo \"\$(date): 错误：无法切换到 Open-WebUI 目录 \$WEBUI_DIR\" >> \"\$LOG_FILE\"; exit 1; }"
    echo ""
    echo "# 激活虚拟环境"
    echo "if [ -f \"\$VENV_NAME/bin/activate\" ]; then"
    echo "    source \"\$VENV_NAME/bin/activate\""
    echo "else"
    echo "    echo \"\$(date): 错误：未找到虚拟环境激活脚本。请确保 Open-WebUI 已安装。\" >> \"\$LOG_FILE\""
    echo "    exit 1"
    echo "fi"
    echo ""
    echo "# 设置 Open-WebUI 环境变量"
    echo "export RAG_EMBEDDING_ENGINE=ollama"
    export AUDIO_STT_ENGINE=openai
    echo ""
    echo "# 检查是否已经有 Open-WebUI 进程在运行"
    echo "if pgrep -f \"open-webui serve\" > /dev/null; then"
    echo "    echo \"\$(date): Open-WebUI 已经在运行中，无需再次启动。\" >> \"\$LOG_FILE\""
    echo "else"
    echo "    echo \"\$(date): 启动 Open-WebUI 服务 (后台运行)...\" >> \"\$LOG_FILE\""
    echo "    nohup open-webui serve >> \"\$LOG_FILE\" 2>&1 &"
    echo "    echo \"\$(date): Open-WebUI 启动命令已执行。\" >> \"\$LOG_FILE\""
    echo "fi"
    echo ""
    echo "echo \"\$(date): 自启动脚本执行完毕。\" >> \"\$LOG_FILE\""
    echo "---------------------------------------------------------"
    echo ""
    echo "3. 给予自启动脚本执行权限:"
    echo "   chmod +x /path/to/your/openwebui_autostart.sh"
    echo ""
    echo "4. 将其添加到 crontab @reboot (推荐):"
    echo "   crontab -e"
    echo "   在文件末尾添加一行 (确保路径正确):"
    echo "   @reboot /bin/bash /path/to/your/openwebui_autostart.sh"
    echo ""
    echo "   或者，如果你使用 systemd，请参考相关文档创建 systemd 服务。"
    echo ""
    echo "注意：请务必确保自启动脚本中的 'WEBUI_DIR' 变量设置为 Open-WebUI 目录的绝对路径，并且该路径在系统启动时可访问。"
    echo "--- 自启动配置说明结束 ---"
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
            install_webui
            ;;
        2|uninstall)
            uninstall_webui
            ;;
        3|start)
            start_webui
            ;;
        4|stop)
            stop_webui
            ;;
        5|autostart)
            autostart_webui_instructions
            ;;
        6|update)
            update_script # update_script 会自行退出
            ;;
        7|exit)
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
    if [[ "$1" != "update" && "$1" != "exit" && "$1" != "6" && "$1" != "7" ]]; then
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
        5) command_to_execute="autostart" ;;
        6) command_to_execute="update" ;;
        7) command_to_execute="exit" ;;
        *) command_to_execute="$choice" ;; # 否则直接使用用户输入的命令名称
    esac

    handle_command "$command_to_execute"

    # 如果命令不是 update 或 exit，则暂停并等待用户确认返回菜单
    if [[ "$command_to_execute" != "update" && "$command_to_execute" != "exit" ]]; then
        echo ""
        read -p "按 Enter 返回主菜单..."
    fi
done
