 

print_modname() {
   echo ""
   echo ""
   echo  "*******************************"
   echo  " "
   echo  " 无需关闭selinux挂载虚拟sd "
   echo  " 自动挂载rannki到SD虚拟分区 "
   echo  " "
   echo  "*******************************"
   echo ""
}
   
on_install() {
  echo  "- 正在释放文件"
  echo ""
  echo  "*******************************"
  echo ""
CONFIG_FILE="$MODPATH/挂载目录.conf"
SOURCE_FILE="/data/adb/modules/RannkiSD/挂载目录.conf"
if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$MODPATH"
    echo "文件已复制到 $MODPATH"
    echo ""
fi

if [[ -f "$CONFIG_FILE" ]]; then
    echo  "保留配置文件"    
    echo ""
    echo  "*******************************"
else
    echo  ""
    echo  "第一次刷入，生成挂载目录.conf"
    echo  ""
    echo  "*******************************"
    cat <<EOL > "$CONFIG_FILE"
#重启之后自动挂载，也可以手动用mt运行service.sh
#必须使用英文 ";" 中文的无法正常识别，不要使用空格
#SD虚拟分区所有数据在mnt/rannki/SD，不在mnt/rannki
#mnt/rannki能查看完整的分区数据，下面是参考格式
#系统位置;虚拟分区位置（数据真实保存位置）
同步挂载测试;同步挂载测试
#此句结尾
EOL

mount_install

fi

}

set_permissions() {
  set_perm_recursive  $MODPATH  0  0  0755  0644
}

mount_install() {
    mkdir -p /mnt/media_rw/0000-1
    mount -t ext4 /dev/block/by-name/rannki /mnt/media_rw/0000-1
    mkdir -p "/mnt/media_rw/0000-1.DATA/同步挂载测试"
    touch "/mnt/media_rw/0000-1/.DATA/同步挂载测试/成功挂载"    
    chmod -R 2777 /mnt/media_rw
    chown -R media_rw:media_rw /mnt/media_rw
    chcon -R "u:object_r:media_rw_data_file:s0" "/mnt/media_rw"
}




if [[ ! -b "/dev/block/by-name/rannki" ]]; then
    echo " "
    echo  "*******************************"
    echo  " 分区不存在，请使用 \"多系统工具箱\"进行分区" # 输出分区不存在信息
    echo  "********************************"
    echo " "
     getVolumeKey() {
        echo " - 按音量键[+]打开单系统+虚拟SD制作教程"
        echo " - 按音量键[-]退出模块"
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

    if getVolumeKey; then
        echo ""
        echo " - 你选择打开教程"
        am start -d 'coolmarket://feed/58405420' >/dev/null 2>&1
    else
        echo ""
        echo " - 你选择退出"
        exit 1
fi
    exit 1
    
else
    print_modname 
    on_install
    set_permissions
    
fi
