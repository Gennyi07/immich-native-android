#!/data/data/com.termux/files/usr/bin/bash
while true; do
    if ! curl -s --max-time 3 http://100.94.25.26:8080/ > /dev/null 2>&1; then
        echo "$(date): rclone down, riavvio..."
        ssh -p 8022 -o ConnectTimeout=10 u0_a421@100.94.25.26 \
            "pkill rclone 2>/dev/null; sleep 2; nohup rclone serve webdav /sdcard/BackupS25 --addr 0.0.0.0:8080 > /dev/null 2>&1 &" 2>/dev/null
    fi
    sleep 30
done
