#!/bin/sh

sudo apt install binfmt-support qemu-user-static fakeroot mkbootimg bison flex gcc-aarch64-linux-gnu pkg-config libncurses-dev libssl-dev unzip git debootstrap android-sdk-libsparse-utils adb fastboot libssl-dev libdw-dev build-essential bc debhelper-compat rsync gcc-arm-none-eabi device-tree-compiler libfdt-dev -y

#git clone https://github.com/dsys1100/debian-on-mido-auto.git --depth 1 && cd debian-on-mido-auto
git clone https://github.com/msm8953-mainline/linux.git --depth=1 -b 6.19.5/main

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export CC=aarch64-linux-gnu-gcc

cd linux
cp ../config .config
make olddefconfig
make -j$(nproc) -s
make -s DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders bindeb-pkg
cd ..

git clone https://github.com/msm8916-mainline/lk2nd.git --depth 1
cd lk2nd
sed -i 's/#define MAX_RAMDISK_SIZE.*/#define MAX_RAMDISK_SIZE\t\t(50 * 1024 * 1024)/' lk2nd/boot/extlinux.c
make lk2nd-msm8953 TOOLCHAIN_PREFIX=arm-none-eabi-
cd ..

dd if=/dev/zero of=rootfs.img bs=1G count=3
mkfs.ext4 -F rootfs.img
mkdir rootfs
sudo mount rootfs.img rootfs

sudo debootstrap --arch arm64 trixie ./rootfs https://deb.debian.org/debian/

dd if=/dev/zero of=bootfs.img bs=1G count=1
mkfs.ext2 bootfs.img

sudo mount --bind /proc ./rootfs/proc
sudo mount --bind /dev ./rootfs/dev
sudo mount --bind /dev/pts ./rootfs/dev/pts
sudo mount --bind /sys ./rootfs/sys
sudo mount bootfs.img ./rootfs/boot

sudo chroot rootfs /bin/bash -c "echo 'deb https://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware' > /etc/apt/sources.list"
sudo chroot rootfs /bin/bash -c "echo 'deb https://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list"
sudo chroot rootfs /bin/bash -c "apt update && apt full-upgrade -y && apt autoremove -y"

sudo chroot rootfs /bin/bash -c "echo 'mido' > /etc/hostname"
sudo chroot rootfs /bin/bash -c "echo '127.0.0.1 mido' >> /etc/hosts"

sudo chroot rootfs /bin/bash -c "/usr/bin/env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt install apt-transport-https ca-certificates locales locales-all man-db bash-completion vim network-manager openssh-server initramfs-tools systemd-timesyncd zstd python3 iptables rfkill usbutils sudo console-setup firmware-qcom-soc file alsa-ucm-conf -y"

sudo chroot rootfs /bin/bash -c "echo 'root:000' | chpasswd"
sudo chroot rootfs /bin/bash -c "useradd -m -G sudo -s /bin/bash user"
sudo chroot rootfs /bin/bash -c "echo 'user ALL=(ALL:ALL) ALL' >> /etc/sudoers.d/user"
sudo chroot rootfs /bin/bash -c "chmod 0440 /etc/sudoers.d/user"
sudo chroot rootfs /bin/bash -c "echo 'user:000' | chpasswd"

sudo cp -r ./firmware/* ./rootfs/lib/firmware/
rm *-dbg_*.deb
sudo cp linux*deb ./rootfs/tmp/
sudo chroot rootfs /bin/bash -c "apt install -y /tmp/*.deb"
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
sudo chroot rootfs /bin/bash -c "update-initramfs -u"
sudo mkdir ./rootfs/boot/extlinux
sudo tee ./rootfs/boot/extlinux/extlinux.conf <<EOF
timeout 0
default Debian
menu title boot prev kernel

label Debian
	kernel /vmlinuz-6.19.5-calicocat-msm8953+
	fdtdir /
	initrd /initrd.img-6.19.5-calicocat-msm8953+
	append console=tty0 root=UUID=$(blkid -o value -s UUID rootfs.img) rw loglevel=3 splash
EOF
sudo cp ./rootfs/usr/lib/linux-image-6.19.5-calicocat-msm8953+/qcom/*mido* ./rootfs/boot/
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
sudo chroot rootfs /bin/bash -c "systemctl enable resizefs.service"
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
sudo chroot rootfs /bin/bash -c "systemctl enable serial-getty@ttyGS0.service"
sudo sh -c "echo g_serial >> ./rootfs/etc/modules"
git clone https://github.com/msm8953-mainline/alsa-ucm-conf.git --depth 1
sudo cp -r alsa-ucm-conf/ucm2/* ./rootfs/usr/share/alsa/ucm2/

sudo chroot rootfs /bin/bash -c "apt clean && apt autoclean"

sudo tee -a ./rootfs/etc/motd <<'EOF'
Connect to Wi-Fi:
sudo nmcli dev wifi connect "SSID" password "PASSWORD"
EOF

sudo umount ./rootfs/proc
sudo umount ./rootfs/dev/pts
sudo umount ./rootfs/dev
sudo umount ./rootfs/sys
sudo umount ./rootfs/boot
sudo umount ./rootfs

img2simg rootfs.img rootfs-simg.img
rm rootfs.img
img2simg bootfs.img bootfs-simg.img
rm bootfs.img
mv ./lk2nd/build-lk2nd-msm8953/lk2nd.img ./lk2nd.img

ls -a
