#!/bin/bash

# 等待X服务器启动
until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do
    sleep 0.5
done

# 启动Steam游戏
# STEAM_APP_ID环境变量由用户指定要运行的游戏ID
if [ -n "${STEAM_APP_ID}" ]; then
    echo "Starting Steam game with AppID: ${STEAM_APP_ID}"
    steam -silent -noverifyfiles -nobootstrapupdate -applaunch "${STEAM_APP_ID}"
    
    # 监控Steam进程
    while pgrep -x "steam" > /dev/null; do
        sleep 1
    done
    
    # Steam进程结束后,使用supervisorctl关闭所有进程
    echo "Steam process ended, shutting down container..."
    supervisorctl shutdown
else
    # 如果没有指定STEAM_APP_ID,保持脚本运行但不做任何事
    echo "No STEAM_APP_ID specified, continuing without launching Steam"
    sleep infinity
fi 