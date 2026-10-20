#!/bin/sh

sudo apt install binfmt-support qemu-user qemu-user-binfmt fakeroot mkbootimg bison flex gcc-aarch64-linux-gnu pkg-config \
     libncurses-dev libssl-dev unzip git debootstrap android-sdk-libsparse-utils adb fastboot libssl-dev libdw-dev \
     build-essential bc debhelper-compat rsync gcc-arm-none-eabi device-tree-compiler libfdt-dev -y

export krnver=7.1.3 debver=sid hostname=mido username=user userpass=000
export "chrootcomm=sudo chroot ./rootfs /bin/bash -c"
export CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 CC=aarch64-linux-gnu-gcc

#git clone https://github.com/dsys1100/debian-on-mido-auto.git --depth 1 && cd debian-on-mido-auto
git clone https://github.com/msm8953-mainline/linux.git --depth=1 -b $krnver/main && cd linux
wget https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/57cff102e1716bd87e7236146581d61dc8d76b23/device/community/linux-postmarketos-qcom-msm8953/config-postmarketos-qcom-msm8953.aarch64 -O .config
echo Linux Kernel building started...
make -s olddefconfig && make -j$(nproc) -s
make -j$(nproc) -s DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders bindeb-pkg
cd ..

git clone https://github.com/msm8916-mainline/lk2nd.git --depth 1 ./lk2nd-ft && cd ./lk2nd-ft
sed -i 's/#define MAX_RAMDISK_SIZE.*/#define MAX_RAMDISK_SIZE\t\t(50 * 1024 * 1024)/' ./lk2nd/boot/extlinux.c
echo Lk2nd-ft building started...
make -j$(nproc) --silent lk2nd-msm8953 TOOLCHAIN_PREFIX=arm-none-eabi-
mv ./build-lk2nd-msm8953/lk2nd.img ../lk2nd-focaltech.img
cd ..

git clone https://github.com/msm8916-mainline/lk2nd.git --depth 1 ./lk2nd-gt
cd ./lk2nd-gt
sed -i 's/#define MAX_RAMDISK_SIZE.*/#define MAX_RAMDISK_SIZE\t\t(50 * 1024 * 1024)/' ./lk2nd/boot/extlinux.c
sed -i 's/touchscreen-compatible = "edt,edt-ft5406";/touchscreen-compatible = "goodix,gt917d";/g' ./lk2nd/device/dts/msm8953/msm8953-xiaomi-common.dts
echo Lk2nd-gt building started...
make -j$(nproc) --silent lk2nd-msm8953 TOOLCHAIN_PREFIX=arm-none-eabi-
mv ./build-lk2nd-msm8953/lk2nd.img ../lk2nd-goodix.img
cd ..

git clone https://gitlab.com/postmarketOS/msm-firmware-loader.git --depth 1

dd if=/dev/zero of=./rootfs.img bs=1G count=3 && mkfs.ext4 -F ./rootfs.img
mkdir ./rootfs && sudo mount ./rootfs.img ./rootfs

sudo debootstrap --arch arm64 $debver ./rootfs https://deb.debian.org/debian/

dd if=/dev/zero of=./bootfs.img bs=1G count=1 && mkfs.ext2 bootfs.img

sudo mount --bind /proc ./rootfs/proc
sudo mount --bind /dev ./rootfs/dev
sudo mount --bind /dev/pts ./rootfs/dev/pts
sudo mount --bind /sys ./rootfs/sys
sudo mount ./bootfs.img ./rootfs/boot

sudo rm -rf ./rootfs/etc/apt/sources.list && sudo rm -rf ./rootfs/etc/apt/sources.list.d/*
sudo mkdir -p ./rootfs/etc/apt/sources.list.d && sudo tee ./rootfs/etc/apt/sources.list.d/debian.sources > /dev/null <<EOF
Types: deb
URIs: https://deb.debian.org/debian/
Suites: $debver
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
#sudo tee /etc/apt/sources.list.d/debian-security.sources > /dev/null <<EOF
#Types: deb
#URIs: https://security.debian.org/debian-security/
#Suites: $debver-security
#Components: main contrib non-free non-free-firmware
#Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
#EOF
$chrootcomm "install -d -m 0755 /etc/apt/keyrings"
sudo curl -fsSL https://os.b1ack.net/deb/pubkey.asc -o ./rootfs/etc/apt/keyrings/b1ack-repo.asc
sudo chmod 0644 ./rootfs/etc/apt/keyrings/b1ack-repo.asc
sudo tee ./rootfs/etc/apt/sources.list.d/b1ack.sources > /dev/null <<EOF
Types: deb
URIs: https://os.b1ack.net/deb/
Suites: B1ackOS
Components: main contrib non-free non-free-firmware
Signed-By: /etc/apt/keyrings/b1ack-repo.asc
EOF
sudo mkdir -p ./rootfs/etc/apt/preferences.d
sudo tee ./rootfs/etc/apt/preferences.d/desktop-base > /dev/null <<EOF
Package: desktop-base
Pin: release n=B1ackOS
Pin-Priority: -1
EOF
sudo rm ./rootfs/var/lib/man-db/auto-update
$chrootcomm "apt update && apt-mark hold b1ack-base grub-theme-b1ack"

$chrootcomm "echo '$hostname' > /etc/hostname"
$chrootcomm "echo '127.0.0.1 $hostname' >> /etc/hosts"

$chrootcomm "/usr/bin/env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt install \
            apt-transport-https ca-certificates locales locales-all man-db bash-completion vim network-manager \
			openssh-server initramfs-tools systemd-timesyncd zstd python-is-python3 iptables rfkill usbutils sudo \
			console-setup firmware-qcom-soc file alsa-ucm-conf bluez iio-sensor-proxy modemmanager rmtfs qrtr-tools \
			tqftpserv libqmi-utils pipewire pipewire-pulse wireplumber alsa-utils zram-tools curl wget fastfetch -y"
$chrootcomm "apt-mark hold alsa-ucm-conf plymouth"
$chrootcomm "systemctl enable rmtfs.service tqftpserv.service ModemManager.service"

sudo install -Dm755 msm-firmware-loader/msm-firmware-loader.sh ./rootfs/usr/sbin/msm-firmware-loader.sh
sudo install -Dm644 msm-firmware-loader/msm-firmware-loader.service ./rootfs/etc/systemd/system/msm-firmware-loader.service
sudo install -Dm755 msm-firmware-loader/msm-firmware-loader-unpack.sh ./rootfs/usr/sbin/msm-firmware-loader-unpack.sh
$chrootcomm "systemctl enable msm-firmware-loader.service"

$chrootcomm "echo 'root:$userpass' | chpasswd"
$chrootcomm "useradd -m -G sudo -s /bin/bash $username"
$chrootcomm "echo '$username ALL=(ALL:ALL) ALL' >> /etc/sudoers.d/$username"
$chrootcomm "chmod 0440 /etc/sudoers.d/$username"
$chrootcomm "echo '$username:$userpass' | chpasswd"
$chrootcomm "usermod -aG sudo,audio,video,render,input,netdev,plugdev,bluetooth $username"

dtc -I dts -O dtb -o ./fastcharge.dtbo ./fastcharge.dts
sudo mkdir ./rootfs/boot/dtbo && sudo cp ./fastcharge.dtbo ./rootfs/boot/dtbo

sudo cp -r ./firmware/* ./rootfs/lib/firmware/
rm *-dbg_*.deb && sudo cp linux*deb ./rootfs/tmp/
$chrootcomm "apt install -y /tmp/*.deb" && sudo rm ./rootfs/tmp/*
sudo tee -a ./rootfs/etc/initramfs-tools/modules > /dev/null <<EOF
edt_ft5x06
goodix_ts
msm
panel_xiaomi_boe_ili9885
panel_xiaomi_ebbg_r63350
panel_xiaomi_nt35532
panel_xiaomi_otm1911
panel_xiaomi_tianma_nt35596
EOF
sudo tee ./rootfs/etc/initramfs-tools/hooks/mido-fw > /dev/null <<'EOF'
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
copy_file firmware /lib/firmware/qcom/a530_pm4.fw
copy_file firmware /lib/firmware/qcom/a530_pfp.fw
EOF
sudo chmod +x ./rootfs/etc/initramfs-tools/hooks/mido-fw
$chrootcomm "update-initramfs -u"
sudo mkdir ./rootfs/boot/extlinux
KREL=$(ls ./rootfs/lib/modules | sort -V | tail -1)
sudo tee ./rootfs/boot/extlinux/extlinux.conf > /dev/null <<EOF
timeout 0
default Debian
menu title boot prev kernel

label Debian
	kernel /vmlinuz-$KREL
	fdtdir /
	initrd /initrd.img-$KREL
	append console=tty0 root=UUID=$(blkid -o value -s UUID rootfs.img) rw loglevel=3
	fdtoverlays /dtbo/fastcharge.dtbo
EOF
sudo cp ./rootfs/usr/lib/linux-image-$KREL/qcom/*mido* ./rootfs/boot/
sudo sh -c "echo 'UUID=$(blkid -o value -s UUID bootfs.img) /boot ext2 defaults 0 2' > ./rootfs/etc/fstab"
sudo tee ./rootfs/etc/systemd/system/resizefs.service > /dev/null <<'EOF'
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
sudo tee ./rootfs/etc/systemd/system/serial-getty@ttyGS0.service > /dev/null <<EOF
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
sudo install -Dm755 ./uim-select ./rootfs/usr/local/sbin/uim-select
sudo mkdir -p ./rootfs/etc/systemd/system/ModemManager.service.d
sudo tee ./rootfs/etc/systemd/system/ModemManager.service.d/uim-selection.conf <<EOF
[Service]
ExecStartPre=/usr/local/sbin/uim-select
EOF
$chrootcomm "apt update && apt full-upgrade -y && apt autoremove -y && apt clean && apt autoclean"

sudo mkdir -p ./rootfs/etc/profile.d
sudo wget https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/6c1ac7813870a72011f3adda4d79178330e8c7c0/device/community/soc-qcom-msm8953/adreno-a506-quirks.sh -O ./rootfs/etc/profile.d/adreno-a506-quirks.sh
sudo mkdir -p ./rootfs/etc/systemd/system.conf.d
sudo tee ./rootfs/etc/systemd/system.conf.d/stop-timeout.conf >/dev/null <<EOF
[Manager]
DefaultTimeoutStopSec=15s
EOF
sudo sed -i 's/MODULES=most/MODULES=dep/g' ./rootfs/etc/initramfs-tools/initramfs.conf
sudo tee -a ./rootfs/etc/motd > /dev/null <<'EOF'

Connect to Wi-Fi:
sudo nmcli dev wifi connect "SSID" password "PASSWORD"

Setup font and size in TTY:
sudo dpkg-reconfigure console-setup

EOF

sudo umount ./rootfs/proc
sudo umount ./rootfs/dev/pts
sudo umount ./rootfs/dev
sudo umount ./rootfs/sys
sudo umount ./rootfs/boot
sudo umount ./rootfs

img2simg ./rootfs.img ./rootfs-$debver.img && rm ./rootfs.img
img2simg ./bootfs.img ./bootfs-$krnver.img && rm ./bootfs.img
zip -9 -v "Debian-$debver.$krnver.zip" rootfs-$debver.img bootfs-$krnver.img lk2nd-goodix.img lk2nd-focaltech.img
rm *.img

tee ./release_body.txt > /dev/null <<EOF
Kernel version: $krnver
Debian version: $debver
Username: $username
User and root password: $userpass
Hostname: $hostname
EOF
