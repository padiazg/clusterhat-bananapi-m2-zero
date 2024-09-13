#!/bin/bash -x

#echo "Press CTRL+C to proceed."
#trap "pkill -f 'sleep 1h'" INT
#trap "set +x ; sleep 1h ; set -x" DEBUG

source ./config.sh

if [ $# -ne 1 ]; then
 echo "Usage: $0 <origin>"
 echo " Where origin the origin image"
 echo " SOURCE=$SOURCE (see config.sh)"
 echo " DEST=$DEST"
 echo ""
 exit
fi

# Check directories exist
if [ ! -d "$MNT" ] ;then
 echo "\$MNT directory does not exist."
 exit
fi

if [ $WIPE_TMP_FOLDERS -eq 1 ]; then
    rm -rf dest/* 
    rm -rf mnt/*
fi 

# Should we use qemu to modify the images
# On Ubuntu this can be used after running
# "apt install qemu-user kpartx qemu-user-static"
QEMU=0
MACHINE=`uname -m`
if ! [ "$MACHINE" = "armv7l" -o "$MACHINE" = "aarch64" ] ;then
    if [ -f "/usr/bin/qemu-arm-static" ];then
        QEMU=1
    else 
        echo 'Unable to run as we're not running on ARM and we don't have "/usr/bin/qemu-arm-static"'
        exit
    fi
fi

# Make sure we have zerofree
which zerofree >/dev/null 2>&1
if [ $? -eq 1 ];then
    echo "Installing zerofree"
    apt install -y zerofree
fi

# Clean env variables
export LC_ALL=C
unset LANGUAGE
unset LC_MESSAGES
unset LANG

SOURCEFILENAME="$1.img"
DESTFILENAME="$1-upd.img"
VARNAME="LITE"


if [ -f  "$SOURCE/$DESTFILENAME"]; then
    echo "Deleting $SOURCE/$DESTFILENAME"
    rm -f $SOURCE/$DESTFILENAME
fi

echo "Building $DESTFILENAME"
echo " Copying source image"
cp "$SOURCE/$SOURCEFILENAME" "$SOURCE/$DESTFILENAME"

# Do we need to grow the image (second partition)?
GROW="GROW$VARNAME" # Build variable name to check
if [ ! ${!GROW} = "0" ];then
    # Get PTUUID
    export $(blkid -o export "$SOURCE/$DESTFILENAME")
    truncate "$SOURCE/$DESTFILENAME" --size=+${!GROW}
    parted --script "$SOURCE/$DESTFILENAME" resizepart 1 100%
    # Set PTUUID
    fdisk "$SOURCE/$DESTFILENAME" <<EOF > /dev/null
p
x
i
0x$PTUUID
r
p
w
EOF
fi

LOOP=`losetup -fP --show $SOURCE/$DESTFILENAME`
sleep $SLEEP

# If the image has been grown resize the filesystem
if [ ! ${!GROW} = "0" ]; then
    e2fsck -fp ${LOOP}p1
    resize2fs -p ${LOOP}p1
fi

mount -o noatime,nodiratime ${LOOP}p1 $MNT
mount -o bind /proc $MNT/proc
mount -o bind /dev $MNT/dev
mount -o bind /dev/pts $MNT/dev/pts

if [ $QEMU -eq 1 ]; then
    cp /usr/bin/qemu-arm-static $MNT/usr/bin/qemu-arm-static
    sed -i "s/\(.*\)/#\1/" $MNT/etc/ld.so.conf
    sed -i "s/\(.*\)/#\1/" $MNT/etc/ld.so.cache
fi

chroot $MNT apt -y purge network-manager iperf3 # docker-ce docker-ce-cli vim vim-runtime vim-common iw

# Get any updates / install and remove pacakges
chroot $MNT apt update -y
chroot $MNT /bin/bash -c 'APT_LISTCHANGES_FRONTEND=none apt -y dist-upgrade'

INSTALL="bridge-utils screen minicom git libusb-1.0-0-dev nfs-kernel-server busybox"
INSTALL+=" initramfs-tools-core python3-smbus python3-usb python3-usb1 python3-libusb1 python3-libgpiod ifmetric" # extras
INSTALL+=" gpiod libgpiod2" # needed by clusterctrl

chroot $MNT /bin/bash -c "APT_LISTCHANGES_FRONTEND=none apt -y install $INSTALL"

chroot $MNT apt -y autoremove --purge
chroot $MNT apt clean

if [ $QEMU -eq 1 ];then
    rm $MNT/usr/bin/qemu-arm-static
    sed -i "s/^#//" $MNT/etc/ld.so.conf
    sed -i "s/^#//" $MNT/etc/ld.so.cache
fi

sync
sleep $SLEEP
umount $MNT/dev/pts
umount $MNT/dev
umount $MNT/proc
umount $MNT

zerofree -v ${LOOP}p1
sleep $SLEEP

losetup -d $LOOP
