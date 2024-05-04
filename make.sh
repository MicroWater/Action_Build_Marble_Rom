#!/bin/bash

sudo timedatectl set-timezone Asia/Shanghai
sudo apt-get remove -y firefox zstd
sudo apt-get install python3 aria2

URL="$1"              # 移植包下载地址
VENDOR_URL="$2"       # 底包下载地址
GITHUB_ENV="$3"       # 输出环境变量
GITHUB_WORKSPACE="$4" # 工作目录
IMAGE_TYPE="$5"       #镜像类型
EXT4_RW="$6"          #是否可读

Red='\033[1;31m'    # 粗体红色
Yellow='\033[1;33m' # 粗体黄色
Blue='\033[1;34m'   # 粗体蓝色
Green='\033[1;32m'  # 粗体绿色

device=marble
vendor_model=23049RAD8C

port_os_version=$(echo ${URL} | cut -d"/" -f4)                   # 移植包的 OS 版本号, 例: OS1.0.7.0.UNACNXM
port_version=$(echo ${port_os_version} | sed 's/OS1/V816/g')     # 移植包的实际版本号, 例: V816.0.7.0.UNACNXM
port_zip_name=$(echo ${URL} | cut -d"/" -f5)                     # 移植包的 zip 名称, 例: miui_AURORA_OS1.0.7.0.UNACNXM_81a48e3c20_14.0.zip
vendor_os_version=$(echo ${VENDOR_URL} | cut -d"/" -f4)          # 底包的 OS 版本号, 例: OS1.0.32.0.UNCCNXM
vendor_version=$(echo ${vendor_os_version} | sed 's/OS1/V816/g') # 底包的实际版本号, 例: V816.0.32.0.UNCCNXM
vendor_zip_name=$(echo ${VENDOR_URL} | cut -d"/" -f5)            # 底包的 zip 名称, 例: miui_HOUJI_OS1.0.32.0.UNCCNXM_4fd0e15877_14.0.zip

android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1) # Android 版本号, 例: 14
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   # 构建时间

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools


magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
ksud="$GITHUB_WORKSPACE"/tools/KernelSU/ksud
lkm="$GITHUB_WORKSPACE"/tools/KernelSU/android12-5.10_kernelsu.ko

a7z="$GITHUB_WORKSPACE"/tools/7zzs
zstd="$GITHUB_WORKSPACE"/tools/zstd
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools


Start_Time() {
  Start_s=$(date +%s)
  Start_ns=$(date +%N)
}

End_Time() {
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi

  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))

  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒"
  fi
}

### 系统包下载
echo -e "${Red}- 开始下载系统包"
echo -e "${Yellow}- 开始下载移植包"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$URL"
End_Time 下载移植包
Start_Time
echo -e "${Yellow}- 开始下载底包"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$VENDOR_URL"
End_Time 下载底包
### 系统包下载结束

### 解包
echo -e "${Red}- 开始解压系统包"
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解压移植包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${port_zip_name} -r -o"$GITHUB_WORKSPACE"/Third_Party >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${port_zip_name}
End_Time 解压移植包
echo -e "${Yellow}- 开始解压底包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压底包
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
echo -e "${Red}- 开始解底包payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/"${device}"/payload.bin -X system,system_ext,product,mi_ext -e -T0
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
echo -e "${Red}- 开始分解底包image"
for i in odm vendor vendor_dlkm; do
  echo -e "${Yellow}- 正在分解底包: $i.img"
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
cd "$GITHUB_WORKSPACE"/images
echo -e "${Red}- 开始解移植包payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/images/ -i "$GITHUB_WORKSPACE"/Third_Party/payload.bin -X product,system,system_ext,mi_ext -T0
echo -e "${Red}- 开始分解移植包image"
for i in product system system_ext mi_ext; do
  echo -e "${Yellow}- 正在分解移植包: $i"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/images/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束

### 写入变量
echo -e "${Red}- 开始写入变量"
# 构建日期
echo "build_time=$build_time" >>$GITHUB_ENV
echo -e "${Blue}- 构建日期: $build_time"
# 移植包版本
echo "port_os_version=$port_os_version" >>$GITHUB_ENV
echo -e "${Blue}- 移植包版本: $port_os_version"
# 底包版本
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
echo -e "${Blue}- 底包版本: $vendor_os_version"
# 移植包安全补丁
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
port_security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 移植包安全补丁版本: $port_security_patch"
echo "port_security_patch=$port_security_patch" >>$GITHUB_ENV
# 底包安全补丁
vendor_build_prop=$GITHUB_WORKSPACE/${device}/vendor/build.prop
vendor_security_patch=$(grep "ro.vendor.build.security_patch=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包安全补丁版本: $vendor_security_patch"
echo "vendor_security_patch=$vendor_security_patch" >>$GITHUB_ENV
# 移植包基线版本
port_base_line=$(grep "ro.system.build.id=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 移植包基线版本: $port_base_line"
echo "port_base_line=$port_base_line" >>$GITHUB_ENV
# 底包基线版本
vendor_base_line=$(grep "ro.vendor.build.id=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包基线版本: $vendor_base_line"
echo "vendor_base_line=$vendor_base_line" >>$GITHUB_ENV
### 写入变量结束

### 功能修复
echo -e "\e[1;31m - 开始功能修复 \e[0m"
Start_Time
# 去除 AVB2.0 校验
echo -e "\e[1;31m - 去除 AVB2.0 校验 \e[0m"
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta.img
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta_system.img
# 修改 Vendor Boot
echo -e "\e[1;31m - 修改 Vendor Boot \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1
fi
## 添加 FEAS 支持 (perfmgr.ko from diting)
sudo mv -f $GITHUB_WORKSPACE/tools/added_vboot_kmods/* "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/
echo "/lib/modules/perfmgr.ko:" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.dep
echo "perfmgr.ko" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.load
echo "perfmgr.ko" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.load.recovery
## 添加更新的内核模块 (vboot)
sudo mv -f $GITHUB_WORKSPACE/"${device}"_files/updated_vboot_kmods/* "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/*
## 移除 mi_ext 和 pangu (fstab)
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  echo -e "\e[1;33m - 移除 mi_ext 和 pangu (fstab) \e[0m"
  sudo sed -i "/mi_ext/d" "$GITHUB_WORKSPACE"/tools/fstab.qcom
  sudo sed -i "/overlay/d" "$GITHUB_WORKSPACE"/tools/fstab.qcom
fi
## 添加液态 2.0 支持 (fstab)
echo -e "\e[1;31m - 添加液态 2.0 支持 (fstab) \e[0m"
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
## 重新打包 Vendor Boot
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  cp -f $ramdisk ramdisk.cpio
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 Vendor 的 fstab
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom
# 内置 TWRP
  echo -e "\e[1;31m - 内置 TWRP \e[0m"
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/recovery.zip -d "$GITHUB_WORKSPACE"/"${device}"/firmware-update
# 修改 Vendor DLKM
echo -e "\e[1;31m - 修改 Vendor DLKM \e[0m"
## 添加更新的内核模块
echo -e "\e[1;31m - 添加更新的内核模块 \e[0m"
sudo mv -f $GITHUB_WORKSPACE/"${device}"_files/updated_dlkm_kmods/* "$GITHUB_WORKSPACE"/"${device}"/vendor_dlkm/lib/modules/
## 移除无用的内核模块
echo -e "\e[1;31m - 移除无用的内核模块 \e[0m"
unneeded_kmods='atmel_mxt_ts.ko cameralog.ko coresight-csr.ko coresight-cti.ko coresight-dummy.ko coresight-funnel.ko coresight-hwevent.ko coresight-remote-etm.ko coresight-replicator.ko coresight-stm.ko coresight-tgu.ko coresight-tmc.ko coresight-tpda.ko coresight-tpdm.ko coresight.ko cs35l41_dlkm.ko f_fs_ipc_log.ko focaltech_fts.ko icnss2.ko nt36xxx-i2c.ko nt36xxx-spi.ko qca_cld3_qca6750.ko qcom-cpufreq-hw-debug.ko qcom_iommu_debug.ko qti_battery_debug.ko rdbg.ko spmi-glink-debug.ko spmi-pmic-arb-debug.ko stm_console.ko stm_core.ko stm_ftrace.ko stm_p_basic.ko stm_p_ost.ko synaptics_dsx.ko'
for i in $unneeded_kmods; do
  sudo rm -rf "$GITHUB_WORKSPACE/${device}/vendor_dlkm/lib/modules/$i"
  sed -i "/$i/d" "$GITHUB_WORKSPACE/${device}/vendor_dlkm/lib/modules/modules.load"
done
# 添加 Root (刷入时可自行选择)
echo -e "\e[1;31m - 添加 ROOT (刷入时可自行选择) \e[0m"
## Patch KernelSU
echo -e "\e[1;31m - 添加 KernelSU 支持（可选择） \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/boot
cd "$GITHUB_WORKSPACE"/boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/boot.img "$GITHUB_WORKSPACE"/boot/boot.img
$ksud boot-patch -b "$GITHUB_WORKSPACE"/boot/boot.img -m $lkm --magiskboot $magiskboot
mv -f "$GITHUB_WORKSPACE"/boot/kernelsu_boot*.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/boot-kernelsu.img
rm -rf "$GITHUB_WORKSPACE"/boot
# 添加 FEAS 支持 (libmigui/joyose)
$magiskboot hexpatch "$GITHUB_WORKSPACE"/images/system_ext/lib64/libmigui.so 726F2E70726F647563742E70726F647563742E6E616D65 726F2E70726F647563742E70726F646375742E6E616D65
for product_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/product -type f -name "build.prop"); do
  sudo sed -i ''"$(sudo sed -n '/ro.product.product.name/=' "$product_build_prop")"'a ro.product.prodcut.name=diting' "$product_build_prop"
done
for joyose_files in $(sudo find "$GITHUB_WORKSPACE"/images/product/pangu/system/ -iname "*joyose_files*"); do
  echo -e "\e[1;33m - 找到文件: $joyose_files \e[0m"
  sudo rm -rf "$joyose_files"
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/Joyose.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/
# 替换 Overlay 叠加层
echo -e "\e[1;31m - 替换 Overlay 叠加层 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/auto-install.json "$GITHUB_WORKSPACE"/images/product/etc/
# 替换 device_features 文件
echo -e "${Red}- 替换 device_features 文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/device_features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/
# 增强HyperOS开机动画
 echo -e "\e[1;31m - 增强HyperOS开机动画 \e[0m"
 sudo rm -rf "$GITHUB_WORKSPACE"/images/product/media/bootanimation.zip
 sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/bootanimation.zip "$GITHUB_WORKSPACE"/images/product/media/
# 修复精准电量（亮屏可用时长）
echo -e "${Red}- 修复精准电量（亮屏可用时长）"
sudo rm -rf "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/PowerKeeper.zip -d "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/
# 统一 build.prop
echo -e "${Red}- 统一 build.prop"
update_prop_file() {
    local file=$1
    local commands=(
        's/ro.build.user=[^*]*/ro.build.user=AtriMyDearMoments/'
        's/build.date=[^*]*/build.date='"${build_time}"'/'
        's/build.date.utc=[^*]*/build.date.utc='"${build_utc}"'/'
        's/'"${port_os_version}"'/'"${vendor_os_version}"'/g'
        's/'"${port_version}"'/'"${vendor_version}"'/g'
        's/'"${port_base_line}"'/'"${vendor_base_line}"'/g'
        's/ro.product.product.name=[^*]*/ro.product.product.name='"${device}"'/'
        's/ro.mi.os.version.incremental=[^*]*/ro.mi.os.version.incremental='"${port_os_version}"'/'
    )
    for cmd in "${commands[@]}"; do
        sudo sed -i "$cmd" "$file"
    done
}
while IFS= read -r -d '' file; do
    update_prop_file "$file"
done < <(sudo find ""$GITHUB_WORKSPACE"/images" ""$GITHUB_WORKSPACE"/"${device}"" -type f -name "*build.prop" -print0)
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
  for erofs_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ext4' | sed 's/^\.\///' | sort); do
    sudo sed -i 's/ext4//g' "$erofs_build_prop"
  done
fi
# 修改 build.prop 中性能文件
echo -e "\e[1;31m - 添加build.prop中性能文件 \e[0m"
cat ""$GITHUB_WORKSPACE"/marble_files/add.txt" | sudo tee -a ""$GITHUB_WORKSPACE"/images/product/etc/build.prop"
# 补全HyperOS 版本信息
echo -e "\e[1;31m - 开始补全HyperOS 版本信息 \e[0m"
sudo grep 'ro' "$GITHUB_WORKSPACE"/images/mi_ext/etc/build.prop | tee -a "$GITHUB_WORKSPACE"/images/product/etc/build.prop
## 添加性能等级支持
for odm_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/odm -type f -name "build.prop"); do
  sudo sed -i ''"$(sudo sed -n '/ro.odm.build.version.sdk/=' "$odm_build_prop")"'a ro.odm.build.media_performance_class=33' "$odm_build_prop"
done
# 修正机型名称
echo -e "\e[1;31m - 修正机型名称 \e[0m"
function update_prop {
    local prop=$1
    local newValue=$2
    local files=("${GITHUB_WORKSPACE}/${device}/odm/etc/marble_build.prop" "${GITHUB_WORKSPACE}/${device}/vendor/marble_build.prop")
    for file in "${files[@]}"; do
        sudo sed -i "s/\(${prop}=*\).*/\1${newValue}/" "$file"
    done
}

update_prop "ro.product.odm.marketname" "Redmi Note 12 Turbo"
update_prop "ro.product.odm.model" "${vendor_model}"
update_prop "ro.product.odm.cert" "${vendor_model}"
update_prop "ro.product.odm.name" "marble"
update_prop "ro.product.vendor.marketname" "Redmi Note 12 Turbo"
update_prop "ro.product.vendor.model" "${vendor_model}"
update_prop "ro.product.vendor.cert" "${vendor_model}"
update_prop "ro.product.vendor.name" "marble"
sudo sed -i 's/POCO/Redmi/g' "$GITHUB_WORKSPACE"/"${device}"/odm/etc/marble_build.prop
sudo sed -i 's/POCO/Redmi/g' "$GITHUB_WORKSPACE"/"${device}"/vendor/marble_build.prop
# 补全 NFC 小米钱包 选项
echo -e "\e[1;31m - 补全 NFC 小米钱包 选项 \e[0m"
sudo sed -i 's/\(ro.vendor.se.type=\).*$/\1HCE,UICC.eSE/' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
## 去除指纹位置指示
echo -e "\e[1;31m - 去除指纹位置指示 \e[0m"
sudo sed -i s/ro.hardware.fp.sideCap=true/ro.hardware.fp.sideCap=false/g "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
rom_security=$(sudo cat "$GITHUB_WORKSPACE"/images/system/system/build.prop | grep 'ro.build.version.security_patch=' | cut -d '=' -f 2)
sudo sed -i 's/ro.vendor.build.security_patch=[^*]*/ro.vendor.build.security_patch='"$rom_security"'/' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
rom_name=$(sudo cat "$GITHUB_WORKSPACE"/images/product/etc/build.prop | grep 'ro.product.product.name=' | cut -d '=' -f 2)
sudo sed -i 's/'"$rom_name"'/marble/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
# 替换小米 13 的部分震动效果
echo -e "\e[1;31m - 移植小米 13 的清理震动效果 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/vibrator_firmware.zip -d "$GITHUB_WORKSPACE"/"${device}"/vendor/firmware/
# 精简部分应用
echo -e "${Red}- 精简部分应用"
apps=( "MiHomeManager" "MIGalleryLockscreen" "MIUIDriveMode" "MIUIDuokanReader" "MIUIGameCenter" "MIUINewHome" "MIUIYoupin" "MIUIHuanJi" "MIUIMiDrive" "MIUIVirtualSim" "ThirdAppAssistant" "XMRemoteController" "MIUIVipAccount" "MiuiScanner" "Xinre" "SmartHome" "MiShop" "MiRadio" "MIUICompass" "MediaEditor" "BaiduIME" "iflytek.inputmethod" "MIService" "MIUIEmail" "MIUIVideo" "MIUIMusicT")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done
# 分辨率修改
echo -e "\e[1;31m - 分辨率修改 \e[0m"
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if [ $(grep -c "$FIND_STR" $FIND_FILE) -ne '0' ]; then
    Character_present=true
    echo -e "\e[1;33m - 找到指定字符: $2 \e[0m"
  else
    Character_present=false
    echo -e "\e[1;33m - !未找到指定字符: $2 \e[0m"
  fi
}
# 蓝牙编码使用adapt r2.2
echo -e "\e[1;31m - 蓝牙编码修改 \e[0m"
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if [ $(grep -c "$FIND_STR" $FIND_FILE) -ne '0' ]; then
    Character_present=true
    echo -e "\e[1;33m - 找到指定字符: $2 \e[0m"
  else
    Character_present=false
    echo -e "\e[1;33m - !未找到指定字符: $2 \e[0m"
  fi
}
Find_character "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=[^*]*/persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true/' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/persist.vendor.qcom.bluetooth.aptxadaptiver2_1_support/=' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop)"'a persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
fi
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop persist.miui.density_v2
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=440/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a persist.miui.density_v2=440' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
# Millet 修复
echo -e "\e[1;31m - Millet 修复 \e[0m"
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop ro.millet.netlink
if [[ $Character_present == true ]]; then
  sudo sed -i 's/ro.millet.netlink=[^*]*/ro.millet.netlink=30/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a ro.millet.netlink=30' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
# 替换相机标定
echo -e "\e[1;31m - 替换相机标定 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 部分机型指纹支付相关服务存在于 Product，需要清除
echo -e "\e[1;31m - 清除多余指纹支付服务 \e[0m"
for files in IFAAService MipayService SoterService TimeService; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*${files}*")
  if [[ $appsui != "" ]]; then
    echo -e "\e[1;33m - 找到服务目录: $appsui \e[0m"
    sudo rm -rf $appsui
  fi
done
# 替换完美图标
echo -e "\e[1;31m - 替换完美图标 \e[0m"
cd ${GITHUB_WORKSPACE}
git clone https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons --depth 1
for pkg in $(ls "$GITHUB_WORKSPACE"/images/product/media/theme/miui_mod_icons/dynamic/); do
  if [[ -d ${GITHUB_WORKSPACE}/icons/icons/$pkg ]]; then
    rm -rf ${GITHUB_WORKSPACE}/icons/icons/$pkg
  fi
done
rm -rf ${GITHUB_WORKSPACE}/icons/icons/com.xiaomi.scanner
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip
rm -rf "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
mkdir -p ${GITHUB_WORKSPACE}/icons/res
mv ${GITHUB_WORKSPACE}/icons/icons ${GITHUB_WORKSPACE}/icons/res/drawable-xxhdpi
cd ${GITHUB_WORKSPACE}/icons
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip res
cd ${GITHUB_WORKSPACE}/icons/themes/Hyper/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd ${GITHUB_WORKSPACE}/icons/themes/common/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
rm -rf ${GITHUB_WORKSPACE}/icons
cd ${GITHUB_WORKSPACE}
# 占位毒瘤和广告
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/AnalyticsCore.apk "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 常规修改
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
Apktool="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"
echo -e "\e[1;31m - 开始移除 Android 签名校验 \e[0m"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
echo -e "\e[1;33m - 开始反编译 \e[0m"
cd "$GITHUB_WORKSPACE"/apk
sudo $Apktool d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "\e[1;33m - ${i}  修改成功 \e[0m"
done
# 去除a14限制api低于23应用安装
echo -e "\e[1;31m - 去除a14限制api低于23应用安装 \e[0m"
find "$GITHUB_WORKSPACE"/apk/services/smali/ -type f -iname 'InstallPackageHelper.smali' -exec sed -i 's/,\ 0x17/,\ 0x0/g' {} +
# 回编译
echo -e "\e[1;33m - 反编译成功，开始回编译 \e[0m"
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $Apktool b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# 人脸修复
echo -e "\e[1;31m - 人脸修复 \e[0m"
for MiuiBiometric in $(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*MiuiBiometric*"); do
  sudo rm -rf $MiuiBiometric
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/face.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 替换 displayconfig 文件
echo -e "${Red}- 替换 displayconfig 文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/
# 替换回旧的 02 屏幕调色配置
echo -e "\e[1;31m - 替换回旧的 02 屏幕调色配置 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/display/qdcm_calib_data_xiaomi_36_02_0a_video_mode_dsc_dsi_panel.json
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/02_dsi_panel.zip -d "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/display/
# 修复机型为 POCO 时最近任务崩溃
echo -e "\e[1;31m - 修复机型为 POCO 时最近任务崩溃 \e[0m"
sudo sed -i 's/com.mi.android.globallauncher/com.miui.home/' "$GITHUB_WORKSPACE"/images/system_ext/etc/init/init.miui.ext.rc
# 补全apex文件
echo -e "\e[1;31m - 补全apex文件 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/apex.zip -d "$GITHUB_WORKSPACE"/images/system_ext/apex
echo -e "\e[1;33m - 补全完成 \e[0m"
# 修复manifest.xml
echo -e "\e[1;31m - 修复manifest.xml \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/manifest.zip -d "$GITHUB_WORKSPACE"/images/system_ext/etc/vintf
echo -e "\e[1;33m - 修复完成 \e[0m"
# NFC 修复
if [[ $android_version == "13" ]]; then
  echo -e "\e[1;31m - NFC 修复 \e[0m"
  for nfc_files in $(sudo find "$GITHUB_WORKSPACE"/images/product/pangu/system/ -iname "*nfc*"); do
    echo -e "\e[1;33m - 找到文件: $nfc_files \e[0m"
    sudo rm -rf "$nfc_files"
  done
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/nfc.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/
fi
# ext4_rw 修改
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  ## 移除 mi_ext 和 pangu (product)
  pangu="$GITHUB_WORKSPACE"/images/product/pangu/system
  sudo find "$pangu" -type d | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo find "$pangu" -type f | sed 's/\./\\./g' | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo cp -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/* "$GITHUB_WORKSPACE"/images/system/system/
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/*
fi
# 系统更新获取更新路径对齐
echo -e "\e[1;31m - 系统更新获取更新路径对齐 \e[0m"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sed 's/^\.\///' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=marble/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=marble_pre/' "$mod_device_build"
  fi
done
# 修正build.prop
echo -e "\e[1;31m - 修正build.prop \e[0m"
sudo sed -i "s/\(ro\.mi\.os\.version\.incremental=\).*/\1$port_os_version/" "$GITHUB_WORKSPACE"/images/product/etc/build.prop
# 替换更改文件/删除多余文件
echo -e "\e[1;31m - 替换更改文件/删除多余文件 \e[0m"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "\e[1;31m - 开始打包 IMAGE \e[0m"
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    echo -e "\e[1;31m - 正在生成: $i \e[0m"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
    Start_Time
    sudo "$GITHUB_WORKSPACE"/tools/mkfs.erofs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$i --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts "$GITHUB_WORKSPACE"/images/$i.img "$GITHUB_WORKSPACE"/images/$i
    End_Time 打包erofs
    eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  Start_Time
  "$GITHUB_WORKSPACE"/tools/lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  done
elif [[ "${IMAGE_TYPE}" == "ext4" ]]; then
  img_free() {
    size_free="$(tune2fs -l "$GITHUB_WORKSPACE"/images/${i}.img | awk '/Free blocks:/ { print $3 }')"
    size_free="$(echo "$size_free / 4096 * 1024 * 1024" | bc)"
    if [[ $size_free -ge 1073741824 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1073741824}")G
    elif [[ $size_free -ge 1048576 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1048576}")MB
    elif [[ $size_free -ge 1024 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1024}")kb
    elif [[ $size_free -le 1024 ]]; then
      File_Type=${size_free}b
    fi
    echo -e "\e[1;33m - ${i}.img 剩余空间: $File_Type \e[0m"
  }
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    eval "$i"_size_orig=$(sudo du -sb "$GITHUB_WORKSPACE"/images/$i | awk {'print $1'})
    if [[ "$(eval echo "$"$i"_size_orig")" -lt "104857600" ]]; then
      size=$(echo "$(eval echo "$"$i"_size_orig") * 15 / 10 / 4096 * 4096" | bc)
    elif [[ "$(eval echo "$"$i"_size_orig")" -lt "1073741824" ]]; then
      size=$(echo "$(eval echo "$"$i"_size_orig") * 108 / 100 / 4096 * 4096" | bc)
    else
      size=$(echo "$(eval echo "$"$i"_size_orig") * 103 / 100 / 4096 * 4096" | bc)
    fi
    eval "$i"_size=$(echo "$size * 4096 / 4096 / 4096" | bc)
  done
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    mkdir -p "$GITHUB_WORKSPACE"/images/$i/lost+found
    sudo touch -t 200901010000.00 "$GITHUB_WORKSPACE"/images/$i/lost+found
  done
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    echo -e "\e[1;31m - 正在生成: $i \e[0m"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
    eval "$i"_inode=$(sudo cat "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config | wc -l)
    eval "$i"_inode=$(echo "$(eval echo "$"$i"_inode") + 8" | bc)
    "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
    Start_Time
    if [[ "${EXT4_RW}" == "true" ]]; then
      sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
    else
      sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
    fi
    End_Time 打包"$i".img
    resize2fs -f -M "$GITHUB_WORKSPACE"/images/$i.img
    eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
    img_free
    if [[ $i == mi_ext ]]; then
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
      continue
    fi
    size_free=$(tune2fs -l "$GITHUB_WORKSPACE"/images/$i.img | awk '/Free blocks:/ { print $3}')
    # 第二次打包 (不预留空间)
    if [[ "$size_free" != 0 && "${EXT4_RW}" != "true" ]]; then
      size_free=$(echo "$size_free * 4096" | bc)
      eval "$i"_size=$(echo "$(eval echo "$"$i"_size") - $size_free" | bc)
      eval "$i"_size=$(echo "$(eval echo "$"$i"_size") * 4096 / 4096 / 4096" | bc)
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$i.img
      echo -e "\e[1;31m - 二次生成: $i \e[0m"
      "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
      Start_Time
      if [[ "${EXT4_RW}" == "true" ]]; then
        sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
      else
        sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
      fi
      End_Time 二次打包"$i".img
      resize2fs -f -M "$GITHUB_WORKSPACE"/images/$i.img
      eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
      img_free
    fi
    # 第二次打包 (除 mi_ext/vendor_dlkm 外各预留 100M 空间)
    if [[ "${EXT4_RW}" == "true" ]]; then
      if [[ $i != mi_ext && $i != vendor_dlkm ]]; then
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") + 52428800" | bc)
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") * 4096 / 4096 / 4096" | bc)
        sudo rm -rf "$GITHUB_WORKSPACE"/images/$i.img
        echo -e "\e[1;31m - 二次生成: $i \e[0m"
        "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
        Start_Time
        if [[ "${EXT4_RW}" == "true" ]]; then
          sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
        else
          sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
        fi
        End_Time 二次打包"$i".img
        eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
        img_free
      fi
    fi
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  sudo rm -rf "$GITHUB_WORKSPACE"/images/mi_ext
  Start_Time
  "$GITHUB_WORKSPACE"/tools/lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  done
fi
### 生成 super.img 结束

### 生成卡刷包
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -12 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
### 生成卡刷包结束

# 生成卡刷包
echo -e "${Red}- 生成卡刷包"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 压缩卡刷包

# 定制 ROM 包名
echo -e "${Red}- 定制 ROM 包名"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="miui_marble_${port_os_version}_${zip_md5}_${android_version}.0_Atri.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/miui_${device}_${port_os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
### 输出卡刷包结束
