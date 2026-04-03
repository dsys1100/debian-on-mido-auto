#!/bin/sh

sudo apt install binfmt-support qemu-user-static fakeroot mkbootimg bison flex gcc-aarch64-linux-gnu pkg-config libncurses-dev libssl-dev unzip git debootstrap android-sdk-libsparse-utils adb fastboot libssl-dev libdw-dev build-essential bc debhelper-compat rsync gcc-arm-none-eabi device-tree-compiler libfdt-dev -y

export krnver=6.19.5
export debver=trixie
export username=user
export userpass=000
export hostname=mido
export "chrootcomm=sudo chroot ./rootfs /bin/bash -c"

#git clone https://github.com/dsys1100/debian-on-mido-auto.git --depth 1 && cd debian-on-mido-auto
git clone https://github.com/msm8953-mainline/linux.git --depth=1 -b $krnver/main

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export CC=aarch64-linux-gnu-gcc

cd linux
cp ../config .config
make olddefconfig
echo Linux Kernel building started...
make -j$(nproc) -s
make -s DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders bindeb-pkg
cd ..

git clone https://github.com/msm8916-mainline/lk2nd.git --depth 1 ./lk2nd-ft
cd ./lk2nd-ft
sed -i 's/#define MAX_RAMDISK_SIZE.*/#define MAX_RAMDISK_SIZE\t\t(50 * 1024 * 1024)/' ./lk2nd/boot/extlinux.c
make lk2nd-msm8953 TOOLCHAIN_PREFIX=arm-none-eabi-
mv ./build-lk2nd-msm8953/lk2nd.img ../lk2nd-focaltech.img
cd ..

git clone https://github.com/msm8916-mainline/lk2nd.git --depth 1 ./lk2nd-gt
cd ./lk2nd-gt
sed -i 's/#define MAX_RAMDISK_SIZE.*/#define MAX_RAMDISK_SIZE\t\t(50 * 1024 * 1024)/' ./lk2nd/boot/extlinux.c
sed -i 's/touchscreen-compatible = "edt,edt-ft5406";/touchscreen-compatible = "goodix,gt917d";/g' ./lk2nd/device/dts/msm8953/msm8953-xiaomi-common.dts
make lk2nd-msm8953 TOOLCHAIN_PREFIX=arm-none-eabi-
mv ./build-lk2nd-msm8953/lk2nd.img ../lk2nd-goodix.img
cd ..

dd if=/dev/zero of=./rootfs.img bs=1G count=3
mkfs.ext4 -F ./rootfs.img
mkdir ./rootfs
sudo mount ./rootfs.img ./rootfs

sudo debootstrap --arch arm64 $debver ./rootfs https://deb.debian.org/debian/

dd if=/dev/zero of=./bootfs.img bs=1G count=1
mkfs.ext2 bootfs.img

sudo mount --bind /proc ./rootfs/proc
sudo mount --bind /dev ./rootfs/dev
sudo mount --bind /dev/pts ./rootfs/dev/pts
sudo mount --bind /sys ./rootfs/sys
sudo mount ./bootfs.img ./rootfs/boot

$chrootcomm "echo 'deb https://deb.debian.org/debian/ $debver main contrib non-free non-free-firmware' > /etc/apt/sources.list"
$chrootcomm "echo 'deb https://security.debian.org/debian-security $debver-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list"
$chrootcomm "apt update && apt full-upgrade -y && apt autoremove -y"

$chrootcomm "echo '$hostname' > /etc/hostname"
$chrootcomm "echo '127.0.0.1 $hostname' >> /etc/hosts"

$chrootcomm "/usr/bin/env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt install apt-transport-https ca-certificates locales locales-all man-db bash-completion vim network-manager openssh-server initramfs-tools systemd-timesyncd zstd python3 iptables rfkill usbutils sudo console-setup firmware-qcom-soc file alsa-ucm-conf bluez iio-sensor-proxy zram-tools curl wget -y"

$chrootcomm "echo 'root:$userpass' | chpasswd"
$chrootcomm "useradd -m -G sudo -s /bin/bash $username"
$chrootcomm "echo '$username ALL=(ALL:ALL) ALL' >> /etc/sudoers.d/$username"
$chrootcomm "chmod 0440 /etc/sudoers.d/$username"
$chrootcomm "echo '$username:$userpass' | chpasswd"
$chrootcomm "usermod -aG sudo $username"
$chrootcomm "usermod -aG audio $username"
$chrootcomm "usermod -aG video $username"
$chrootcomm "usermod -aG render $username"
$chrootcomm "usermod -aG input $username"
$chrootcomm "usermod -aG netdev $username"
$chrootcomm "usermod -aG plugdev $username"
$chrootcomm "usermod -aG bluetooth $username"

dtc -I dts -O dtb -o ./fastcharge.dtbo ./fastcharge.dts
sudo mkdir ./rootfs/boot/dtbo
sudo cp ./fastcharge.dtbo ./rootfs/boot/dtbo

sudo cp -r ./firmware/* ./rootfs/lib/firmware/
rm *-dbg_*.deb
sudo cp linux*deb ./rootfs/tmp/
$chrootcomm "apt install -y /tmp/*.deb"
sudo rm ./rootfs/tmp/*
sudo tee -a ./rootfs/etc/initramfs-tools/modules <<EOF
edt_ft5x06
goodix_ts
msm
panel_xiaomi_boe_ili9885
panel_xiaomi_ebbg_r63350
panel_xiaomi_nt35532
panel_xiaomi_otm1911
panel_xiaomi_tianma_nt35596
EOF
sudo tee ./rootfs/etc/initramfs-tools/hooks/mido-fw <<'EOF'
#!/bin/sh
PREREQ=""
prereqs()
{
	echo "$PREREQ"
}
case $1 in
prereqs)
	prereqs
	exit 0
	;;
esac
. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line
add_firmware qcom/msm8953/xiaomi/mido/a506_zap.mdt
add_firmware qcom/msm8953/xiaomi/mido/a506_zap.elf
add_firmware qcom/msm8953/xiaomi/mido/a506_zap.b00
add_firmware qcom/msm8953/xiaomi/mido/a506_zap.b01
add_firmware qcom/msm8953/xiaomi/mido/a506_zap.b02
EOF
$chrootcomm "update-initramfs -u"
sudo mkdir ./rootfs/boot/extlinux
sudo tee ./rootfs/boot/extlinux/extlinux.conf <<EOF
timeout 0
default Debian
menu title boot prev kernel

label Debian
	kernel /vmlinuz-$krnver-calicocat-msm8953+
	fdtdir /
	initrd /initrd.img-$krnver-calicocat-msm8953+
	append console=tty0 root=UUID=$(blkid -o value -s UUID rootfs.img) rw loglevel=3 splash
	fdtoverlays /dtbo/fastcharge.dtbo
EOF
sudo cp ./rootfs/usr/lib/linux-image-$krnver-calicocat-msm8953+/qcom/*mido* ./rootfs/boot/
sudo sh -c "echo 'UUID=$(blkid -o value -s UUID bootfs.img) /boot ext2 defaults 0 2' > ./rootfs/etc/fstab"
sudo tee ./rootfs/etc/systemd/system/resizefs.service <<'EOF'
[Unit]
Description=Expand root filesystem to fill partition
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'exec /usr/sbin/resize2fs $(findmnt -nvo SOURCE /)'
ExecStartPost=/usr/bin/systemctl disable resizefs.service
RemainAfterExit=true

[Install]
WantedBy=default.target
EOF
$chrootcomm "systemctl enable resizefs.service"
sudo tee ./rootfs/etc/systemd/system/serial-getty@ttyGS0.service <<EOF
[Unit]
Description=Serial Console Service on ttyGS0

[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyGS0 xterm+256color
Type=idle
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
EOF
$chrootcomm "systemctl enable serial-getty@ttyGS0.service"
sudo sh -c "echo g_serial >> ./rootfs/etc/modules"
git clone https://github.com/msm8953-mainline/alsa-ucm-conf.git --depth 1
sudo cp -r ./alsa-ucm-conf/ucm2/* ./rootfs/usr/share/alsa/ucm2/
sudo tee ./rootfs/etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=75
PRIORITY=100
EOF
$chrootcomm "apt clean && apt autoclean"

sudo tee -a ./rootfs/etc/motd <<'EOF'

Connect to Wi-Fi:
sudo nmcli dev wifi connect "SSID" password "PASSWORD"

Setup font and size in TTY:
dpkg-reconfigure console-setup

EOF

sudo umount ./rootfs/proc
sudo umount ./rootfs/dev/pts
sudo umount ./rootfs/dev
sudo umount ./rootfs/sys
sudo umount ./rootfs/boot
sudo umount ./rootfs

img2simg ./rootfs.img ./rootfs-$debver.img
rm ./rootfs.img
img2simg ./bootfs.img ./bootfs-$krnver.img
rm ./bootfs.img

tee ./release_body.txt <<EOF
Kernel version: $krnver
Debian version: $debver
Username: $username
User and root password: $userpass
Hostname: $hostname
EOF
