MODDIR="${0%/*}" 
#启动参数
TIMEOUT=180         #完全解锁手机时间超过180秒启动失败
BOOT_TIMEOUT=60   #开机超过60秒启动失败
CHECK_INTERVAL=1   #循环一次一秒

# 配置参数
LOGFILE="$MODDIR/日志.log"
CONFIG_FILE="$MODDIR/挂载目录.conf"
MAX_LOG_SIZE=$((1024 * 500))  #日志最大体积，默认500kb

# 日志记录函数
log() {
    _msg="$1"
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$_msg" >> "$LOGFILE"
}

# 广播通知
Boot_Toast() {
    su -lp 2000 -c "cmd notification post -t "挂载虚拟SD" "msg_tag" "$1""
}

# 广播更新媒体数据
am_broadcast() {
    am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/$1" >/dev/null
}

# 系统启动
check_boot_complete() {
    [ "$(getprop sys.boot_completed)" -eq 1 ]
}

# 输入限制解除
check_input_unrestricted() {
    dumpsys window policy | awk -F= '/mInputRestricted/ { 
        gsub(/[[:space:]]/, "", $2); 
        exit $2 != "false" 
    }'
}

# 第一阶段：等待系统启动
i=1
while [ $i -le $BOOT_TIMEOUT ]; do
    check_boot_complete && break
    sleep $CHECK_INTERVAL
    if [ $i -eq $BOOT_TIMEOUT ]; then
        echo "错误：系统启动超时（${BOOT_TIMEOUT}秒）" >&2
        Boot_Toast "阶段一启动失败😭"
        exit 1
    fi
    i=$((i + 1))
done

# 第二阶段：等待输入解除
j=1
input_timeout=$((TIMEOUT - i))
while [ $j -le $input_timeout ]; do
    check_input_unrestricted && break
    sleep $CHECK_INTERVAL
    if [ $j -eq $input_timeout ]; then
        echo "错误：输入限制解除超时（${input_timeout}秒）" >&2
        Boot_Toast "阶段二启动失败😭"
        exit 1
    fi
    j=$((j + 1))
done

#Boot_Toast "开机检测通过😋一阶段$i秒二阶段$j秒"
log "开机成功😋一阶段$i秒二阶段$j秒"

# 安全创建目录（带权限验证）
safe_create_dir() {
    _target_dir="$1"
    _default_uid="${2:-media_rw}"
    _default_gid="${3:-media_rw}"

    if [ ! -d "$_target_dir" ]; then
        if mkdir -p "$_target_dir" 2>> "$LOGFILE"; then
            log "创建目录成功: $_target_dir"
            chown "$_default_uid:$_default_gid" "$_target_dir" 2>> "$LOGFILE" || log "警告：无法设置目录所有者 $_default_uid:$_default_gid 到 $_target_dir"                
            chmod -R 777 "$_target_dir" 2>> "$LOGFILE" ||  log "警告：无法设置权限 $_target_dir"
                
            return 0
        else
            log "严重错误：创建目录失败 $_target_dir"
            return 1
        fi
    else
        log "目录已存在: $_target_dir"
        return 0
    fi
}

# 安全挂载操作
safe_mount() {
    _src="$1"
    _dest="$2"
    _desc="${3:-常规挂载}"

    if mountpoint -q "$_dest"; then
        log "挂载点已存在: $_dest ($_desc)"
        return 1
    fi

    if [ ! -d "$_src" ]; then
        log "错误：源目录不存在 $_src"
        return 2
    fi

    if mount --bind "$_src" "$_dest" 2>> "$LOGFILE"; then
        log "挂载成功: $_src => $_dest ($_desc)"
        return 0
    else
        log "严重错误：挂载失败 $_src => $_dest"
        return 3
    fi
}

# 权限及上下文设置
set_security_context() {
    _target="$1"
    _uid="${2:-media_rw}"
    _gid="${3:-media_rw}"
    _context="${4:-u:object_r:media_rw_data_file:s0}"
   
    # 设置权限
    if chmod -R 2777 "$_target" 2>> "$LOGFILE"; then
        log "设置权限成功: 2777 => $_target"
    else
        log "警告：权限设置失败 $_target"
    fi
    
    # 设置所有权
    if chown -R "$_uid:$_gid" "$_target" 2>> "$LOGFILE"; then
        log "设置所有者成功: $_uid:$_gid => $_target"
    else
        log "警告：所有者设置失败 $_target"
    fi

    # 设置SELinux上下文
    if chcon -R "$_context" "$_target" 2>> "$LOGFILE"; then
        log "设置上下文成功: $_context => $_target"
    else
        log "警告：上下文设置失败 $_target"
    fi
}

# 初始化基础环境
init_base_env() {
    # 创建必要目录结构
    safe_create_dir "/mnt/rannki" "media_rw" "media_rw" || return 1
    safe_create_dir "/data/media/0/SD虚拟分区" || return 1

    # 挂载主分区
    if ! mountpoint -q "/mnt/rannki"; then
        if ! mount -t ext4 /dev/block/by-name/rannki /mnt/rannki 2>> "$LOGFILE"; then
            log "致命错误：无法挂载主分区"
            return 2
        fi
        #运行太慢，尝试拒绝一下
        #set_security_context "/mnt/rannki"
    fi

    # 创建SD卡子目录
    safe_create_dir "/mnt/rannki/SD" || return 3
    safe_create_dir "/data/media/0/SD虚拟分区" || return 4
    
    #设置虚拟SD目录权限
    set_security_context "/mnt/rannki/SD"
    set_security_context "/data/media/0/SD虚拟分区" 
         
    # 挂载虚拟SD卡
    if ! mountpoint -q "/data/media/0/SD虚拟分区"; then
        safe_mount "/mnt/rannki/SD" "/data/media/0/SD虚拟分区" "虚拟SD卡挂载" || return 5
    fi
}

# 解析配置文件
parse_mount_config() {
    log "开始解析配置文件..."
    
    _valid_count=0
    while IFS=';' read -r src dest _; do
        # 跳过注释和空行
        case "$src" in
            ''|\#*) continue ;;
        esac

        # 路径标准化处理
        media_path="/data/media/0/${src%/}"
        rannki_path="/mnt/rannki/.DATA/${dest%/}"

        log "正在处理配置项：$src => $dest"
        
        # 创建目录结构
        safe_create_dir "$media_path" || continue
        safe_create_dir "$rannki_path" || continue

        # 获取权限信息
        if [ -e "$media_path" ]; then
            media_uid=$(stat -c '%u' "$media_path")
            media_gid=$(stat -c '%g' "$media_path")
        else
            media_uid="media_rw"
            media_gid="media_rw"
        fi

        # 设置权限
        set_security_context "$rannki_path" "$media_uid" "$media_gid"
        set_security_context "$media_path" "$media_uid" "$media_gid"

        # 执行挂载
        if safe_mount "$rannki_path" "$media_path" "自定义挂载"; then
            _valid_count=$((_valid_count + 1))
        fi
    done < "$CONFIG_FILE"

    log "成功加载 $_valid_count 个有效挂载配置"
}

# 主执行流程
main() {
    log "======== 启动挂载流程 ========"
    
    if ! init_base_env; then
        log "初始化失败，终止执行"
        exit 1
    fi

    parse_mount_config
    
    log "======== 挂载操作完成 ========"    
}

# 删除日志
if [[ -f "$LOGFILE" ]] && [[ $(stat -c%s "$LOGFILE") -gt $MAX_LOG_SIZE ]]; then
    rm -f "$LOGFILE"
fi

# 执行入口
main
Boot_Toast "成功运行😋"

# 乱七八糟
log "
    
    "
#am_broadcast "Pictures"
#am_broadcast "DCIM"
#resetprop -n ro.boot.vbmeta.digest 
exit 0
