#!/bin/bash

# 等待X服务器启动
until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do
  sleep 0.5
done

# 等待Fcitx进程启动
echo "Waiting for Fcitx to start..."
until pgrep -x "fcitx" > /dev/null; do
  sleep 1
done
echo "Fcitx is running."

# 启动Steam游戏
# STEAM_APP_ID环境变量由用户指定要运行的游戏ID
if [ -n "${STEAM_APP_ID}" ]; then
  echo "Starting Steam game with AppID: ${STEAM_APP_ID}"
  
  # 启动游戏
  # -gameid 582010
  # steam://rungameid/582010
  steam -silent -noverifyfiles -nobootstrapupdate "steam://rungameid/${STEAM_APP_ID}" &

  # 等待游戏进程出现，最多等待90秒
  WAIT_TIME=0
  MAX_WAIT_TIME=90
  GAME_PID=""

  while [ "$WAIT_TIME" -lt "$MAX_WAIT_TIME" ]; do
    # 查找包含"\Steam\steamapps\common\"的游戏进程
    GAME_PID=$(ps -ef | grep -E "\-gameid ${STEAM_APP_ID}" | grep -v grep | awk '{print $2}')
    
    # 如果找到游戏进程，则退出等待循环
    if [ -n "$GAME_PID" ]; then
      echo "Game process started with PID: $GAME_PID"
      
      # 打印游戏进程信息
      ps -p "$GAME_PID" -o pid,ppid,cmd

      break
    fi

    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
  done

  # 如果在90秒内没有找到游戏进程，则输出提示
  if [ -z "$GAME_PID" ]; then
    echo "No game process found after waiting for $MAX_WAIT_TIME seconds."
  else
    # 监控游戏进程
    while ps -p "$GAME_PID" > /dev/null; do
      sleep 1
    done

    # 游戏进程结束后,使用supervisorctl关闭所有进程
    echo "Game process ended, shutting down container..."
    supervisorctl shutdown
  fi
else
  # 如果没有指定STEAM_APP_ID,保持脚本运行但不做任何事
  echo "No STEAM_APP_ID specified, continuing without launching Steam"
fi
