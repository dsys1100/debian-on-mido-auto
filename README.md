# fork Readme WIP
It is a base image; no tweaks are included for now.  
Original readme translated to English:

-----

# Porting Debian Linux to mido

An attempt to port Debian Linux to the Qualcomm version of the Xiaomi Redmi Note 4X (mido).

This phone is supported by Nura (ex postmarketOS). The port is based on the Nura kernel and draws on existing tutorials available online.

This device comes with multiple hardware variants, and some components are not fully supported by available drivers. Therefore, full functionality is not guaranteed. For information about hardware vendor support, see [Nura Wiki](https://wiki.nura.eco/wiki/Xiaomi_Redmi_Note_4_(xiaomi-mido)).

According to the Nura Wiki, devices equipped with a Goodix touchscreen may experience touch input issues. Fixing this requires modifying the DTS and recompiling lk2nd. A modified version is provided here, but I cannot test it because I do not have such a device.

If you want to use a prebuilt system image, download it from [Releases](https://github.com/dsys1100/debian-on-mido-auto/releases) and skip directly to the [Flashing](https://github.com/dsys1100/debian-on-mido-auto/tree/main#flashing) section.

Note: Starting with the 20250915 release, prebuilt system images use the new extlinux boot method instead of the androidboot method. With extlinux, the kernel, initramfs, and other files are stored on a writable filesystem rather than being packaged into a read-only boot.img. This means that kernel updates, `update-initramfs`, and boot parameter changes will take effect. However, the flashing procedure is different.

## Building the kernel

### Preparation

Install the required packages on the host system (the list may be incomplete):

```bash
sudo apt install binfmt-support qemu-user-static fakeroot mkbootimg bison flex gcc-aarch64-linux-gnu pkg-config libncurses-dev libssl-dev unzip git debootstrap android-sdk-libsparse-utils adb fastboot libssl-dev libdw-dev
```

Clone this repository:

```bash
git clone https://github.com/dsys1100/debian-on-mido-auto.git
cd debian-on-mido-auto
```

Clone the kernel source:

```bash
git clone https://github.com/msm8953-mainline/linux.git --depth=1 -b 7.1.3/main
```

The `7.1.3/main` branch was the latest available when this guide was written. Change the branch if necessary.

Build the kernel with [Nura MSM8953 kernel configuration](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/57cff102e1716bd87e7236146581d61dc8d76b23/device/community/linux-postmarketos-qcom-msm8953/config-postmarketos-qcom-msm8953.aarch64), recommended to use a config of the same version as the kernel.

### Building

```bash
cd linux
export CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 CC=aarch64-linux-gnu-gcc
wget https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/57cff102e1716bd87e7236146581d61dc8d76b23/device/community/linux-postmarketos-qcom-msm8953/config-postmarketos-qcom-msm8953.aarch64 -O .config
make olddefconfig
```

Save the configuration once, then build:

```bash
make -j$(nproc)
make -j$(nproc) DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders bindeb-pkg
cd ..
```

(Note: Due to changes introduced in Linux 6.12, building kernel headers now requires `libssl-dev:arm64`. To avoid this issue, this guide skips building `linux-headers`. For details, see [this kernel commit](https://github.com/msm8953-mainline/linux/commit/e2c318225ac13083cdcb4780cdf5b90edaa8644d).)

(Note 2: on Debian you can build kernel with headers by adding arm64 arch and installing gcc-aarch64-linux-gnu + libssl-dev:arm64 - `make -j$(nproc) bindeb-pkg`)

The generated `.deb` files can be found in the parent directory.

### Preparing firmware

This repository already includes a prepared firmware directory, so the following steps are not necessary. They are documented here for reference only.

```bash
git clone https://github.com/Kiciuk/proprietary_firmware_mido.git
mkdir -p firmware/qcom/msm8953/xiaomi/mido/
cp -r proprietary_firmware_mido/apnhlos/* firmware/
cp -r proprietary_firmware_mido/firmware/wlan firmware/
cp -r proprietary_firmware_mido/modem/* firmware/
mv firmware/a506* firmware/qcom/msm8953/xiaomi/mido/
```

Additional Qualcomm firmware required by the system will be installed later through the `firmware-qcom-soc` package.

Now used [msm-firmware-loader](https://gitlab.postmarketos.org/postmarketOS/msm-firmware-loader) to retrieve and load firmware directly from the original device partitions, but I don't rule out the possibility that THESE firmware files might be needed in addition to the ones extracted from the phone itself.

## Modifying and building lk2nd

By default, lk2nd only supports initramfs images smaller than 16 MB when using extlinux boot. Installing a desktop environment introduces Plymouth, which significantly increases the initramfs size and can cause boot failure. Therefore, lk2nd must be modified and rebuilt.

Devices equipped with a Goodix touchscreen also require a modification to the lk2nd DTS; otherwise, touch input will not work. This repo builds lk2nd for both variants - flash corresponding.

Plymouth is currently disabled via `apt-mark hold`, and attempts are being made to merge the rootfs and bootfs.

### Preparation

Install the required build dependencies:

```bash
sudo apt install gcc-arm-none-eabi device-tree-compiler libfdt-dev
```

Clone the lk2nd source:

```bash
git clone https://github.com/msm8916-mainline/lk2nd.git
cd lk2nd
```

### Modifications

Edit `lk2nd/boot/extlinux.c`. At line 481, change:

`#define MAX_RAMDISK_SIZE        (16 * 1024 * 1024)`

to:

`#define MAX_RAMDISK_SIZE        (50 * 1024 * 1024)`

Note: Do not increase this value arbitrarily. According to the lk2nd developers, the MSM8953 platform reserves a maximum of 90 MB of memory in total for the kernel, DTB, and initramfs. By default, the kernel can use up to 32 MB and the DTB up to 2 MB, leaving a maximum initramfs size of 56 MB.

If your device has a Goodix touchscreen, you must also edit `lk2nd/device/dts/msm8953/msm8953-xiaomi-common.dts`. Replace every occurrence of:

`touchscreen-compatible = "edt,edt-ft5406";`

with:

`touchscreen-compatible = "goodix,gt917d";`

This fixes the touchscreen input issue.

### Building

```bash
make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8953
```

The resulting `lk2nd.img` can be found in the `build-lk2nd-msm8953` directory.

## Creating the system - WIP, old info, needs update

### Creating filesystem images

Create `rootfs.img`, format it, mount it, and use debootstrap to install the base system.

```bash
sudo su
dd if=/dev/zero of=rootfs.img bs=1G count=3
mkfs.ext4 rootfs.img
mkdir test
mount rootfs.img test

debootstrap --arch arm64 trixie ./test https://mirrors.tuna.tsinghua.edu.cn/debian/
# Alternatively, use the function provided in env.sh

sudo su
source env.sh
make_rootfs_img
```

Create `bootfs.img` to serve as the boot partition.

```bash
sudo su
dd if=/dev/zero of=bootfs.img bs=1G count=1
mkfs.ext2 bootfs.img

# Alternatively, use the function provided in env.sh

sudo su
source env.sh
make_bootfs_img
```

Mount the root filesystem:

```bash
sudo su
mount --bind /proc ./test/proc
mount --bind /dev ./test/dev
mount --bind /dev/pts ./test/dev/pts
mount --bind /sys ./test/sys
mount bootfs.img ./test/boot

# Alternatively, use the function provided in env.sh

sudo su
source env.sh
mount_rootfs
```

Enter the chroot environment:

```bash
chroot ./test
```

### Basic system configuration

Some of the following commands must be executed inside the chroot environment, while others must be run on the host system. Pay attention to the descriptions preceding each code block.

Inside the chroot, configure the APT repositories by following the [Tsinghua Debian mirror instructions](https://mirrors.tuna.tsinghua.edu.cn/help/debian/). Make sure to enable the `non-free-firmware` repository component.

Inside the chroot, set the root password and hostname, then install the required packages:

```bash
passwd root
echo 'xiaomi-mido' > /etc/hostname
echo '127.0.0.1 xiaomi-mido' >> /etc/hosts
apt update
apt install apt-transport-https ca-certificates micro locales locales-all man man-db bash-completion vim tmux network-manager openssh-server initramfs-tools systemd-timesyncd zstd python3 iptables rfkill usbutils sudo console-setup firmware-qcom-soc file alsa-ucm-conf -y
```

Copy the firmware into the chroot. Run the following commands on the host system:

```bash
sudo su
cp -r firmware/* ./test/lib/firmware/
```

Copy the generated kernel `.deb` files into the chroot. Run the following commands on the host system:

```bash
sudo su
cp linux*deb ./test/tmp/
```

Inside the chroot, install the kernel packages using `dpkg -i`. Do not install the `.deb` file whose name contains `dbg`.

Edit `/etc/initramfs-tools/modules` inside the chroot and add the following entries:

```text
edt_ft5x06
goodix_ts
msm
panel_xiaomi_boe_ili9885
panel_xiaomi_ebbg_r63350
panel_xiaomi_nt35532
panel_xiaomi_otm1911
panel_xiaomi_tianma_nt35596
```

Inside the chroot, create `/etc/initramfs-tools/hooks/mido-fw` and make it executable. Use the following contents:

```bash
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
```

Then run:

```bash
update-initramfs -u
```

### Boot partition configuration

Configure the boot partition by creating `/boot/extlinux/extlinux.conf` inside the chroot with the following contents:

```text
timeout 1
default Debian
menu title boot prev kernel

label Debian
	kernel /vmlinuz-6.16.3-calicocat-msm8953+
	fdtdir /
	initrd /initrd.img-6.16.3-calicocat-msm8953+
	append console=tty0 root=UUID=350b96c5-23d6-419f-a377-d2e446190c14 rw loglevel=3 splash
```

Note: The `kernel`, `initrd`, and `root=UUID` values must match the actual filenames in the chroot's `/boot` directory and the UUID of `rootfs.img`. You can obtain the UUID using `file rootfs.img`. Do not copy these example values verbatim. The kernel and initrd filenames may also change after a kernel package update, so remember to update this configuration when necessary.

TODO: Use an automated script to update `extlinux.conf` and DTB files automatically.

Copy the DTB files to `/boot`. Run the following command inside the chroot:

```bash
cp /usr/lib/linux-image-6.16.3-calicocat-msm8953+/qcom/*mido* /boot
```

This command must be repeated after every kernel update.

Configure automatic mounting of the boot partition by appending the following line to `/etc/fstab` inside the chroot:

```text
UUID=f29c8d16-64af-42a3-bdb6-8f2d3b68d374 /boot ext2 defaults 0 2
```

The UUID here belongs to `bootfs.img`. You can obtain it using `file bootfs.img`.

### Additional optimizations

Configure the root filesystem to expand automatically at boot. Run the following commands inside the chroot:

```bash
cat > /etc/systemd/system/resizefs.service << 'EOF'
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
systemctl enable resizefs.service
```

Enable USB serial console access. Run the following commands inside the chroot:

```bash
cat > /etc/systemd/system/serial-getty@ttyGS0.service << EOF
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
systemctl enable serial-getty@ttyGS0.service
# If serial console login stops working, the g_serial module may not have loaded
echo g_serial >> /etc/modules
```

Install the ALSA configuration files on the host system:

```bash
git clone https://github.com/msm8953-mainline/alsa-ucm-conf.git
cp -r alsa-ucm-conf/ucm2/* ./test/usr/share/alsa/ucm2/
```

### Finishing the system image

Clean up the chroot environment. Run the following commands inside the chroot:

```bash
apt clean
rm -rf /tmp/*
exit
```

Exit the chroot and unmount the filesystems on the host system:

```bash
sudo su
umount ./test/proc
umount ./test/dev/pts
umount ./test/dev
umount ./test/sys
umount ./test/boot
umount ./test

# Alternatively, use the function provided in env.sh

sudo su
source env.sh
umount_rootfs
```

Convert the images to the format required for flashing:

```bash
img2simg rootfs.img rootfs-simg.img
img2simg bootfs.img bootfs-simg.img
```

You should now have `bootfs-simg.img` and `rootfs-simg.img`, ready to be flashed.

## Flashing

It is recommended to flash a custom recovery first. TWRP or OrangeFox is recommended.

Boot into recovery and perform a full wipe of the three relevant partitions.

Reboot into fastboot mode.

```bash
fastboot erase boot
fastboot erase system
fastboot erase userdata
```

Flash port:

```bash
fastboot flash boot lk2nd.img
fastboot flash system bootfs-simg.img
fastboot flash userdata rootfs-simg.img
```

Finally, run `fastboot reboot` to complete the flashing process.

## After booting the system - remove this later

`g_serial` is enabled by default, allowing you to access the system through a USB serial connection at 115200 baud.

### Bluetooth and accelerometer

Bluetooth requires the `bluez` package. Device discovery works, but connecting to devices has not been tested.

The accelerometer and ambient light sensor require `iio-sensor-proxy`.

```bash
apt install bluez iio-sensor-proxy
```

You can then test the sensors using the `monitor-sensor` command.

### Configuring the language, time zone, and TTY font

```bash
dpkg-reconfigure locales
dpkg-reconfigure tzdata
dpkg-reconfigure console-setup
```

VGA or Terminus fonts are recommended, as they offer larger font sizes.

### Creating a new user

```bash
adduser user
usermod -aG sudo,audio,video,render,input,netdev,plugdev,bluetooth user
```

### Enabling zram

Zram compresses a portion of RAM and uses it as swap space.

```bash
sudo apt install zram-tools
```

Edit `/etc/default/zramswap` and change `ALGO=lz4` to `ALGO=zstd`.

### Installing a desktop environment

Several desktop environments and interfaces are available:

- Phosh is optimized for phones and touchscreens (`sudo apt update && sudo apt install phosh phosh-phone gdm3 -y` and select `gdm3` for Display Manager).
- Plasma Mobile is optimized for phones and touchscreens, but slightly laggy (`sudo apt update && sudo apt install plasma-mobile` and maybe sddm, i forget).
- Xfce4 provides a traditional desktop experience and is suitable for use with a keyboard and mouse or stylus.
- BuffyBoard is not strictly a desktop environment; it simply adds a virtual keyboard to the default TTY.

### (Optional) Enabling fast charging

The default charging current is limited to 1 A in the DTB, resulting in relatively slow charging. The charging current can be increased by modifying the DTS.

Since lk2nd supports device tree overlays with extlinux, this guide uses a DTBO to override the relevant device tree node without modifying the original DTS.

Install the device tree compiler:

```bash
sudo apt install device-tree-compiler
```

Create `fastcharge.dts`. The example below increases the charging current to 1.6 A:

```dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/battery";
        __overlay__ {
            constant-charge-current-max-microamp = <1600000>;
        };
    };
};
```

Compile it into a DTBO:

```bash
dtc -I dts -O dtb -o fastcharge.dtbo fastcharge.dts
```

Copy the file to `/boot/dtbo`:

```bash
sudo su
mkdir -p /boot/dtbo
cp fastcharge.dtbo /boot/dtbo
```

Edit `/boot/extlinux/extlinux.conf` and append the following line at the end:

```text
	fdtoverlays /dtbo/fastcharge.dtbo
```

After editing, `extlinux.conf` should look like this:

```text
timeout 1
default Debian
menu title boot prev kernel

label Debian
	kernel /vmlinuz-6.16.3-calicocat-msm8953+
	fdtdir /
	initrd /initrd.img-6.16.3-calicocat-msm8953+
	append console=tty0 root=UUID=350b96c5-23d6-419f-a377-d2e446190c14 rw loglevel=3 splash
	fdtoverlays /dtbo/fastcharge.dtbo
```

Reboot the device. Running the following command should now return `1600000`:

```bash
cat /sys/class/power_supply/qcom-smbchg-usb/constant_charge_current_max
```

A USB power meter should also show an increase in charging current.

And this already included in my builds.

## Untested features and known issues

- Suspend may not work - phone not wakeup after suspend.
- SIM card functionality has been tested - it works, but only one SIM, needs rework or port sim selector from Nura.
- OTG Works, old text: Loading `g_serial` by default makes USB OTG unavailable. To use OTG, comment out `g_serial` in `/etc/modules`, or connect the OTG device before booting.
- Bluetooth device discovery works, but actual functionality has not been confirmed.
- Charging while powered off is not supported; connecting a charger automatically powers on the device.
- Battery status and charging status are reported separately. Connecting a charger does not always trigger a charging notification, even though charging is actually taking place. The AC power connection may only become visible after opening the power manager. This behavior is inconsistent.
- Due to the two issues above, the device cannot remain powered on when the battery is critically low. It triggers an automatic low-battery shutdown, then powers on again when connected to a charger, creating a continuous reboot cycle. The currently recommended workaround is to charge the device in recovery/fastboot mode when the battery is critically low.
- ~~Sometimes the battery is not detected. In this case, the device must be fully powered off and then turned on again; a normal reboot does not seem to help. Charging and discharging behavior can also be unstable.~~
- Charging may stop working correctly after suspend. More precisely, if the device was charging before being suspended, the `upower` service may malfunction after resume, causing Xfce Power Manager to freeze. The battery status then stops updating, making it impossible to determine whether the device is charging. Shutdown or reboot may also hang while terminating the `upower` process. This issue only occurs when the charger is connected before suspending; suspending without charging does not trigger it, and charging remains unaffected after resume in that case. Further testing is needed.
- The infrared transmitter has not been tested.
- GPS has not been tested.

## References and acknowledgments

- Nura (ex postmarketOS)
- calico-cat-3333

Aomura_Umeko (Bilibili):

- [Build guide](https://gitee.com/meiziyang2023/hm2-ubuntu-ports/blob/master/%E7%BC%96%E8%AF%91%E6%95%99%E7%A8%8B.md)
- [Ubuntu ports for Xiaomi Snapdragon 625 phones](https://gitee.com/meiziyang2023/ubuntu-ports-xiaomi-625-phones)
- [KlipperPhonesLinux](https://github.com/umeiko/KlipperPhonesLinux)

holdmyhand (博客园):

- [Original article](https://www.cnblogs.com/holdmyhand/articles/18048158)
