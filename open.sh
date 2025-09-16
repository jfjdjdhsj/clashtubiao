#!/bin/bash

# ================== 配置 ==================
WEBUI_INSTALL_PYTHON_VERSION="3.11.11"
VENV_NAME="open.venv"
WEBUI_CURRENT_DIR="$(pwd)"
LOG_FILE="${WEBUI_CURRENT_DIR}/open-webui.log"
UPDATE_URL="https://raw.githubusercontent.com/jfjdjdhsj/clashtubiao/refs/heads/main/open.sh"
SCRIPT_PATH=$(readlink -f "$0")

# ================== 辅助函数 ==================
command_exists() { command -v "$1" &>/dev/null; }

display_menu() {
    echo ""
    echo "--- Open-WebUI 管理菜单 ---"
    echo "1. install          - 安装 Open-WebUI"
    echo "2. uninstall        - 卸载 Open-WebUI"
    echo "3. start            - 启动 Open-WebUI (日志直接输出到控制台)"
    echo "4. stop             - 停止 Open-WebUI 服务"
    echo "5. set_autostart    - 设置开机自启动"
    echo "6. remove_autostart - 去除开机自启动"
    echo "7. update           - 更新管理脚本"
    echo "8. exit             - 退出脚本"
    echo "---------------------------------------------"
    echo -n "请输入选择 (1-8 或命令名称): "
}

# ================== 功能实现 ==================
install_webui() {
    if [ -n "$VIRTUAL_ENV" ]; then
        echo "⚠️ 检测到已在虚拟环境中：$VIRTUAL_ENV"
        echo "请退出虚拟环境后再安装。"
        return 1
    fi
    echo "--- 开始安装 Open-WebUI ---"

    # 1. 安装 uv
    if ! command_exists uv; then
        echo "安装 uv..."
        pip install uv --break-system-packages || { echo "❌ uv 安装失败"; return 1; }
    fi

    # 2. 安装指定版本 Python
    if ! uv python list --json 2>/dev/null | grep -q "\"version\": \"${WEBUI_INSTALL_PYTHON_VERSION}\""; then
        echo "安装 Python ${WEBUI_INSTALL_PYTHON_VERSION}..."
        uv python install "${WEBUI_INSTALL_PYTHON_VERSION}" || { echo "❌ Python 安装失败"; return 1; }
    fi

    # 3. 创建虚拟环境
    export UV_LINK_MODE=copy
    if [ ! -d "$VENV_NAME" ]; then
        echo "创建虚拟环境..."
        uv venv -p "${WEBUI_INSTALL_PYTHON_VERSION}" "${VENV_NAME}" || { echo "❌ 创建虚拟环境失败"; return 1; }
    fi

    # 4. 安装 open-webui
    source "${VENV_NAME}/bin/activate"
    uv pip install open-webui || { echo "❌ open-webui 安装失败"; deactivate; return 1; }
    deactivate
    echo "✅ Open-WebUI 安装完成。"
}

uninstall_webui() {
    echo "--- 卸载 Open-WebUI ---"
    deactivate 2>/dev/null
    rm -rf "${VENV_NAME}" && echo "✅ 虚拟环境已删除。" || echo "⚠️ 未找到虚拟环境。"
}

start_webui() {
    echo "--- 启动 Open-WebUI (日志直接输出到控制台) ---"
    if [ ! -f "${VENV_NAME}/bin/activate" ]; then
        echo "❌ 未找到虚拟环境，请先安装。"; return 1
    fi
    source "${VENV_NAME}/bin/activate"
    export RAG_EMBEDDING_ENGINE=ollama
    export AUDIO_STT_ENGINE=openai

    # 停止已有进程
    PID=$(pgrep -f "open-webui serve")
    if [ -n "$PID" ]; then
        echo "⚠️ 检测到已有进程，先停止..."
        kill "$PID"
        sleep 2
    fi

    echo "✅ 服务已启动，日志如下（按 Ctrl+C 停止服务）"
    # 前台启动：日志直接输出到终端，同时保存到文件
    exec open-webui serve 2>&1 | tee -a "$LOG_FILE"

    deactivate
}

stop_webui() {
    PID=$(pgrep -f "open-webui serve")
    if [ -n "$PID" ]; then
        kill "$PID" && echo "✅ Open-WebUI 已停止。" || echo "❌ 停止失败。"
    else
        echo "⚠️ 未找到正在运行的 Open-WebUI 进程。"
    fi
}

set_autostart() {
    echo "--- 设置开机自启动 ---"
    CMD="@reboot cd ${WEBUI_CURRENT_DIR} && source ${WEBUI_CURRENT_DIR}/${VENV_NAME}/bin/activate && RAG_EMBEDDING_ENGINE=ollama AUDIO_STT_ENGINE=openai open-webui serve >> ${LOG_FILE} 2>&1 &"
    (crontab -l 2>/dev/null | grep -v "open-webui" ; echo "$CMD") | crontab -
    echo "✅ 已设置开机自启动。"
}

remove_autostart() {
    echo "--- 去除开机自启动 ---"
    crontab -l 2>/dev/null | grep -v "open-webui" | crontab -
    echo "✅ 已去除开机自启动。"
}

update_script() {
    echo "--- 更新脚本 ---"
    if ! command_exists curl && ! command_exists wget; then
        echo "❌ 需要 curl 或 wget"; return 1
    fi
    TMP=$(mktemp)
    if command_exists curl; then
        curl -sSL "$UPDATE_URL" -o "$TMP"
    else
        wget -q -O "$TMP" "$UPDATE_URL"
    fi
    mv "$TMP" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH" && echo "✅ 脚本已更新，请重新运行。" && exit 0
}

exit_script() { echo "退出脚本"; exit 0; }

handle_command() {
    case "$1" in
        1|install)          install_webui ;;
        2|uninstall)        uninstall_webui ;;
        3|start)            start_webui ;;
        4|stop)             stop_webui ;;
        5|set_autostart)    set_autostart ;;
        6|remove_autostart) remove_autostart ;;
        7|update)           update_script ;;
        8|exit)             exit_script ;;
        *) echo "无效命令: $1" ;;
    esac
}

# ================== 主循环 ==================
if [ -n "$1" ]; then
    handle_command "$1"; exit 0
fi

while true; do
    clear
    display_menu
    read -r choice
    handle_command "$choice"
    [ "$choice" != "7" ] && [ "$choice" != "8" ] && read -p "按 Enter 返回菜单..."
done
