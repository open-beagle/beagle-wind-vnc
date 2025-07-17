#!/bin/bash
if [ -f "/tools/bgctl" ]; then
  cp -r /tools/bgctl /usr/local/bin/bgctl && chmod +x /usr/local/bin/bgctl
  bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET
fi

# 遍历 /usr/local/lib/ 下的所有文件夹
for dir in /usr/local/lib/*/; do
    # 检查文件夹是否存在且可访问
    if [ -d "$dir" ]; then
        # 查找 .desktop 文件
        desktop_files=$(find "$dir" -maxdepth 1 -name "*.desktop" -type f)
        
        # 如果找到 .desktop 文件，则复制到桌面
        if [ -n "$desktop_files" ]; then
            cp -v $desktop_files "$HOME/Desktop/"
        fi
    fi
done