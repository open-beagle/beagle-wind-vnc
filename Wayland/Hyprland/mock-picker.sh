#!/bin/bash
# Portal ScreenCast 自动授权 — 返回第一个 Hyprland 输出
# xdg-desktop-portal-hyprland 的 custom_picker_binary 调用此脚本
# 输出格式: [SELECTION]FLAGS/TYPE:VALUE
MONITOR=$(HYPRLAND_INSTANCE_SIGNATURE=$(ls -t ${XDG_RUNTIME_DIR}/hypr/ 2>/dev/null | head -1) hyprctl -j monitors 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['name'])" 2>/dev/null)
echo "[SELECTION]r/screen:${MONITOR:-HEADLESS-2}"
