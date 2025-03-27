#!/bin/sh

# 配置文件路径
MODDIR="${0%/*}"
LOGFILE="$MODDIR/日志.log"
CONFIG_FILE="$MODDIR/挂载目录.conf"

# 日志记录函数
log() {
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$1" >> "$LOGFILE"
}

# 安全卸载函数
safe_unmount() {
    _mount_point="$1"
    _desc="${2:-常规卸载}"
    if [ ! -d "$_mount_point" ]; then
        log "目录不存在: $_mount_point"
        return 1
    fi
    if mountpoint -q "$_mount_point"; then
        if umount -l "$_mount_point" 2>> "$LOGFILE"; then
            log "卸载成功: $_mount_point ($_desc)"
            return 0
        else
            log "错误：卸载失败 $_mount_point"
            return 1
        fi
    else
        log "未挂载: $_mount_point"
        return 2
    fi
}

# 清理空目录（可选）
clean_empty_dir() {
    _target_dir="$1"
    if [ -d "$_target_dir" ] && [ -z "$(ls -A "$_target_dir")" ]; then
        rmdir "$_target_dir" 2>> "$LOGFILE" && 
            log "清理空目录: $_target_dir" || 
            log "警告：目录清理失败 $_target_dir"
    fi
}

# 解析配置文件卸载
unmount_from_config() {
    log "开始解析卸载配置..."
    _valid_count=0

    while IFS=';' read -r src dest _; do
        case "$src" in
            ''|\#*) continue ;;
        esac

        media_path="/data/media/0/${src%/}"
        log "正在处理配置项：$media_path"

        if safe_unmount "$media_path" "配置项卸载"; then
            _valid_count=$((_valid_count + 1))
            clean_empty_dir "$media_path"
        fi
    done < "$CONFIG_FILE"

    log "成功卸载 $_valid_count 个配置挂载点"
}

# 主卸载流程
main_unmount() {
    log "======== 启动卸载流程 ========"

    # 卸载虚拟SD卡
    safe_unmount "/data/media/0/SD虚拟分区" "虚拟SD卡卸载"
    clean_empty_dir "/data/media/0/SD虚拟分区"

    # 卸载配置文件中的挂载点
    unmount_from_config

    # 卸载主分区（谨慎操作）
    if safe_unmount "/mnt/rannki" "主分区卸载"; then
        clean_empty_dir "/mnt/rannki"
    else
        log "警告：主分区保持挂载状态"
    fi

    log "======== 卸载操作完成 ========"
    exit 0
}

#音量键选择
getVolumeKey() {
  key=""
  while true; do
    key=$(getevent -qlc 1)
    if echo "$key" | grep -q "KEY_VOLUMEUP"; then
      return 0
    elif echo "$key" | grep -q "KEY_VOLUMEDOWN"; then
      return 1
    fi
  done
}

# 乱七八糟的💩💩💩
echo ""
echo ""
echo " - 如果遇到某些app无法找到图片等" 
echo " - 可运行媒体广播，更新并广播数据"
echo " - 运行后，短时间内手机功耗增加"
echo ""
echo " - 按音量键[+]媒体广播"
echo " - 按音量键[-]取消挂载"
echo ""

if getVolumeKey; then
  echo " "
  echo " - 你选择[+]"
  am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard" >/dev/null
#  am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/DCIM" >/dev/null
  echo " "
else
  echo ""
  echo " - 你选择[-]"
  main_unmount
  exit 0
fi

