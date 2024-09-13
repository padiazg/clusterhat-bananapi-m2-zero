#!/bin/bash -x

#echo "Press CTRL+C to proceed."
#trap "pkill -f 'sleep 1h'" INT
#trap "set +x ; sleep 1h ; set -x" DEBUG

source ./config.sh

if [ $# -ne 1 ]; then
 echo "Usage: $0 <version>"
 echo " Where version is Armbian_23.05.0 in Armbian_23.05.0-trunk_Bananapip2zero_bookworm_current_6.1.24.img"
 echo " Builds lite & desktop images for controller"
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

# Get version from command line
VER=$1

# Detect which source files we have (lite/desktop/full)
# Build array of Raspbian images (lite/std/full) to build
# SOURCES[] = "<Source filename>|<Dest filename>|<Variable name>|<Release>|<Firmware folder>"
# Firmware folder: for /boot leave empty, for /boot/firmware set /firmware

CNT=0

# Check for Armbian Jammy Pi OS 64-bit
# Armbian_22.05.0-trunk_Bananapim2zero_jammy_current_5.15.43_minimal.img
if [ -f "$SOURCE/${VER}-trunk_Bananapim2zero_jammy_current_5.15.43_minimal.img" ];then
    SOURCES[$CNT]="${VER}-trunk_Bananapim2zero_jammy_current_5.15.43_minimal.img|$VER-$REV-trunk_Bananapim2zero_jammy_current_5.15.43_minimal-ClusterCTRL|LITE|ARMBIAN64JAMMY|"
    let CNT=$CNT+1
fi

# Check for Armbian Bullseye Pi OS 64-bit
# Armbian_22.08.0-trunk_Bananapim2zero_bullseye_current_5.15.43.img
if [ -f "$SOURCE/${VER}-trunk_Bananapim2zero_bullseye_current_5.15.43.img" ];then
    SOURCES[$CNT]="${VER}-trunk_Bananapim2zero_bullseye_current_5.15.43.img|$VER-$REV-trunk_Bananapim2zero_bullseye_current_5.15.43-ClusterCTRL|LITE|ARMBIAN64BULLSEYE|"
    let CNT=$CNT+1
fi

# Check for Armbian Bullseye Pi OS 64-bit
# Armbian_22.11.0-trunk_Bananapim2zero_bullseye_edge_6.0.9.img
if [ -f "$SOURCE/${VER}-trunk_Bananapim2zero_bullseye_edge_6.0.9.img" ];then
    SOURCES[$CNT]="${VER}-trunk_Bananapim2zero_bullseye_edge_6.0.9.img|$VER-$REV-trunk_Bananapim2zero_bullseye_edge_6.0.9-ClusterCTRL|LITE|ARMBIAN64BULLSEYE|"
    let CNT=$CNT+1
fi


# Check for Armbian Bookwork Pi OS 64-bit
# Armbian_24.11.0-trunk_Bananapim2zero_bookworm_6.6.44.img
if [ -f "$SOURCE/${VER}-trunk_Bananapim2zero_bookworm_6.6.44.img" ];then
    SOURCES[$CNT]="${VER}-trunk_Bananapim2zero_bookworm_6.6.44.img|$VER-$REV-trunk_Bananapim2zero_bookworm_6.6.44-ClusterCTRL|LITE|ARMBIAN64BOOKWORM|"
    let CNT=$CNT+1
fi

# # Check for Armbian Bookworm Pi OS 64-bit
# if [ -f "$SOURCE/${VER}-trunk_Bananapip2zero_bookworm_current_6.1.24.img" ];then
#  SOURCES[$CNT]="${VER}-trunk_Bananapip2zero_bookworm_current_6.1.24.img|$VER-$REV-trunk_Bananapip2zero_bookworm_current_6.1.24-ClusterCTRL|LITE|BOOKWORM|KERNEL6"
#  let CNT=$CNT+1
# fi

if [ $CNT -eq 0 ];then
 echo "No source file(s) found"
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

# Loop each image type
for BUILD in "${SOURCES[@]}"; do

    # Extract '|' separated variables
    IFS='|' read -ra IMAGE <<< "$BUILD"
    SOURCEFILENAME=${IMAGE[0]}
    DESTFILENAME=${IMAGE[1]}
    VARNAME=${IMAGE[2]}
    RELEASE=${IMAGE[3]}
    FIRMWAREFOLDER=${IMAGE[4]}

    # if [ $FIRMWAREFOLDER = "F" ];then
    #     FW="boot/firmware"
    # else
    #     FW="boot"
    # fi

    FW="boot$FIRMWAREFOLDER"

    if [ -f "$DEST/$DESTFILENAME-CBRIDGE.img" ];then
        echo "Skipping $TYPENAME build"
        echo " $DEST/$DESTFILENAME-CBRIDGE.img exists"
    else
        echo "Building $TYPENAME"
        echo " Copying source image"
        cp "$SOURCE/$SOURCEFILENAME" "$DEST/$DESTFILENAME-CBRIDGE.img"

        # Do we need to grow the image (second partition)?
        GROW="GROW$VARNAME" # Build variable name to check
        if [ ! ${!GROW} = "0" ];then
            # Get PTUUID
            export $(blkid -o export "$DEST/$DESTFILENAME-CBRIDGE.img")
            truncate "$DEST/$DESTFILENAME-CBRIDGE.img" --size=+${!GROW}
            parted --script "$DEST/$DESTFILENAME-CBRIDGE.img" resizepart 1 100%
            # Set PTUUID
            fdisk "$DEST/$DESTFILENAME-CBRIDGE.img" <<EOF > /dev/null
p
x
i
0x$PTUUID
r
p
w
EOF
        fi

        LOOP=`losetup -fP --show $DEST/$DESTFILENAME-CBRIDGE.img`
        sleep $SLEEP

        # If the image has been grown resize the filesystem
        if [ ! ${!GROW} = "0" ];then
            e2fsck -fp ${LOOP}p1
            resize2fs -p ${LOOP}p1
        fi

        mount -o noatime,nodiratime ${LOOP}p1 $MNT
        mount -o bind /proc $MNT/proc
        mount -o bind /dev $MNT/dev
        mount -o bind /dev/pts $MNT/dev/pts

        if [ $QEMU -eq 1 ];then
            cp /usr/bin/qemu-arm-static $MNT/usr/bin/qemu-arm-static
            sed -i "s/\(.*\)/#\1/" $MNT/etc/ld.so.conf
            sed -i "s/\(.*\)/#\1/" $MNT/etc/ld.so.cache
        fi

        if [ $RELEASE = "ARMBIAN64BOOKWORM" -o $RELEASE = "ARMBIAN64BULLSEYE"]; then
            chroot $MNT systemctl disable network-manager
            chroot $MNT systemctl stop network-manager

            chroot $MNT systemctl enable systemd-networkd
            chroot $MNT systemctl start systemd-networkd

            chroot $MNT systemctl stop systemd-resolved
            chroot $MNT systemctl disable systemd-resolved
            # ln -s $MNT/run/systemd/resolve/resolv.conf $MNT/etc/resolv.conf
            
            mv $MNT/etc/resolv.conf $MNT/etc/resolv.conf.disabled
            echo "nameserver 8.8.8.8" > $MNT/etc/resolv.conf
        fi

        chroot $MNT apt -y purge network-manager iperf3 

        # Get any updates / install and remove pacakges
        chroot $MNT apt update -y
        if [ $UPGRADE = "1" ]; then
            chroot $MNT /bin/bash -c 'APT_LISTCHANGES_FRONTEND=none apt -y dist-upgrade'
        fi

        # Setup ready for iptables for NAT for NAT/WiFi use
        # Preseed answers for iptables-persistent install
        chroot $MNT /bin/bash -c "echo 'iptables-persistent iptables-persistent/autosave_v4 boolean false' | debconf-set-selections"
        chroot $MNT /bin/bash -c "echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections"


        INSTALL="bridge-utils initramfs-tools-core screen git nfs-kernel-server busybox gpiod"
        INSTALL+=" libusb-1.0-0-dev libgpiod2" # libs
        INSTALL+=" python3-smbus python3-usb python3-usb1 python3-libusb1 python3-libgpiod" # needed by clusterctrl
        INSTALL+=" netfilter-persistent iptables-persistent" 


        if [ $RELEASE =  "ARMBIAN64BOOKWORM" ]; then
            INSTALL+=" armbian-config"
        fi

        chroot $MNT /bin/bash -c "APT_LISTCHANGES_FRONTEND=none apt -y install $INSTALL"
        
        # Remove ModemManager
        # chroot $MNT systemctl disable ModemManager.service
        # ERROR: Failed to disable unit, unit ModemManager.service does not exist.
        chroot $MNT apt -y purge modemmanager
        chroot $MNT apt-mark hold modemmanager

        # Add more resolvers
        echo -e "nameserver 8.8.4.4\nnameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844" >> $MNT/etc/resolv.conf

        echo '#net.ipv4.ip_forward=1 # ClusterCTRL' >> $MNT/etc/sysctl.conf
        cat << EOF >> $MNT/etc/iptables/rules.v4
# Generated by iptables-save v1.6.0 on Fri Mar 13 00:00:00 2018
*filter
:INPUT ACCEPT [7:1365]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -i br0 ! -o br0 -j ACCEPT
-A FORWARD -o br0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
# Completed on Fri Mar 13 00:00:00 2018
# Generated by iptables-save v1.6.0 on Fri Mar 13 00:00:00 2018
*nat
:PREROUTING ACCEPT [8:1421]
:INPUT ACCEPT [7:1226]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.19.181.0/24 ! -o br0 -j MASQUERADE
COMMIT
# Completed on Fri Mar 13 00:00:00 2018
EOF

        # Set custom password
        if [ ! -z $PASSWORD ];then
            if [ ! -z $USERNAME ];then
                PASSWORDE=$(echo "$PASSWORD" | openssl passwd -6 -stdin)
                chroot $MNT useradd $USERNAME --password $PASSWORDE --create-home --groups tty,disk,dialout,sudo,audio,video,plugdev,games,users,systemd-journal,input,netdev
            else
                chroot $MNT /bin/bash -c "echo 'pi:$PASSWORD' | chpasswd"
            fi
        fi

        # disable new user prompt
        chroot $MNT rm -f /root/.not_logged_in_yet
        chroot $MNT /bin/bash -c "echo 'root:$PASSWORD' | chpasswd"


        # Should we enable SSH?
        if [ $ENABLESSH = "1" ];then
            chroot $MNT systemctl enable ssh
            chroot $MNT systemctl start ssh
        fi

        # Should we update with rpi-update?
        # NOTE: although the binary is there I'm not sure if this works on Banana pi boards
        if [ ! -z $RPIUPDATE ];then
            export ROOT_PATH=$MNT
            export BOOT_PATH=$MNT/$FW
            export SKIP_WARNING=1
            export SKIP_BACKUP=1
            rpi-update "$RPIUPDATE"
        fi

        # Disable APIPA addresses on ethpiX and set fallback IPs

        # We give this an "unconfigured" IP of 172.19.181.253
        # Pi Zeros should be reconfigured to 172.19.181.X where X is the P number
        # NAT Controller is on 172.19.181.254
        # A USB network (usb0) device plugged into the controller will have fallback IP of 172.19.181.253

        if [ $RELEASE = "ARMBIAN64BOOKWORM" -o $RELEASE = "JAMMY" ];then
            cat << EOF >> $MNT/etc/dhcp/dhclient.conf
# START ClusterCTRL config
timeout 10;
initial-interval 2;
lease { # Px
  interface "usb0";
  fixed-address 172.19.181.253; # ClusterCTRL Px
  option subnet-mask 255.255.255.0;
  option routers 172.19.181.254;
  option domain-name-servers 8.8.8.8;
  renew never;
  rebind never;
  expire never;
}

lease { # Controller
  interface "br0";
  fixed-address 172.19.181.254;
  option subnet-mask 255.255.255.0;
  option domain-name-servers 8.8.8.8;
  renew never;
  rebind never;
  expire never;
}
# END ClusterCTRL config
EOF
        else 
            cat << EOF >> $MNT/etc/dhcpcd.conf
# ClusterCTRL
reboot 15
denyinterfaces ethpi* ethupi* ethupi*.10 brint eth0 usb0.10

profile clusterctrl_fallback_usb0
static ip_address=172.19.181.253/24 #ClusterCTRL
static routers=172.19.181.254
static domain_name_servers=8.8.8.8 208.67.222.222

profile clusterctrl_fallback_br0
static ip_address=172.19.181.254/24

interface usb0
fallback clusterctrl_fallback_usb0

interface br0
fallback clusterctrl_fallback_br0
EOF
        fi

        # Enable uart with login
        # TODO
        # SERIALCONSOLE=$(grep -c "^enable_uart=1" $MNT/$FW/config.txt)
        # if [ $SERIALCONSOLE -eq 0 ]; then
        #     echo "enable_uart=1" >>  $MNT/$FW/config.txt
        # fi

        # Enable I2C (used for I/O expander on Cluster HAT v2.x)
        # we don't need it now as we are creating this image for Px images
        # echo "overlays=i2c2-m1" >> $MNT/$FW/armbianEnv.txt

        # Change the hostname to "cbridge"
        sed -i "s#^127.0.1.1.*#127.0.1.1\tcbridge#g" $MNT/etc/hosts
        echo "cbridge" > $MNT/etc/hostname

        echo -e "mountd: 172.19.180.\nrpcbind: 172.19.180.\n" >> $MNT/etc/hosts.allow
        echo -e "mountd: ALL\nrpcbind: ALL\n" >> $MNT/etc/hosts.deny    

        # Enable console on UART
        if [ "$SERIALAUTOLOGIN" = "1" ];then
            if [ $RELEASE = "ARMBIAN64BULLSEYE" -o $RELEASE = "ARMBIAN64BOOKWORM" -o $RELEASE = "JAMMY" ];then
                mkdir -p $MNT/etc/systemd/system/serial-getty@ttyS0.service.d/
                cat > $MNT/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
EOF
            fi
        fi

        # Extract files
        (tar --exclude=.git -cC ../files/ -f - .) | (chroot $MNT tar -xvC /)

        # Disable the auto filesystem resize and convert to bridged controller
        if grep -q "^extraargs=" "$file"; then
            sed -i 's/^extraargs=\(.*\)/extraargs=\1 init=\/usr\/sbin\/reconfig-clusterctrl cbridge/' $MNT/$FW/armbianEnv.txt
        else
            echo "extraargs=init=/usr/sbin/reconfig-clusterctrl cbridge">> $MNT/$FW/armbianEnv.txt
        fi

        # Setup directories for rpiboot
        mkdir -p $MNT/var/lib/clusterctrl/boot
        mkdir $MNT/var/lib/clusterctrl/nfs
        if [ -z $BOOTCODE ];then
            ln -fs /$FW/bootcode.bin $MNT/var/lib/clusterctrl/boot/
        elif [ ! $BOOTCODE = "none" ];then
            wget -O $MNT/var/lib/clusterctrl/$FW/bootcode.bin $BOOTCODE
        fi

        # Enable clusterctrl init
        chroot $MNT systemctl enable clusterctrl-init

        # Enable rpiboot for booting without SD cards
        chroot $MNT systemctl enable clusterctrl-rpiboot
        # Disable nfs server (rely on clusterctrl-rpiboot to start it if needed)
        chroot $MNT systemctl disable nfs-kernel-server

        # Setup NFS exports for NFSROOT
        for ((P=1;P<=252;P++));do
            echo "/var/lib/clusterctrl/nfs/p$P 172.19.180.$P(rw,sync,no_subtree_check,no_root_squash)" >> $MNT/etc/exports
            mkdir "$MNT/var/lib/clusterctrl/nfs/p$P"
        done

        # Setup config.txt file
        # TODO: this is especific to RPI, wont work on OPI
        # C=`grep -c "dtoverlay=dwc2,dr_mode=peripheral" $MNT/$FW/config.txt`

        # if [ $C -eq 0  ];then
        #     echo -e "# Load overlay to allow USB Gadget devices\n#dtoverlay=dwc2,dr_mode=peripheral" >> $MNT/$FW/config.txt
        #     echo -e "# Use XHCI USB 2 Controller for Cluster HAT Controllers\n[pi4]\notg_mode=1 # Controller only\n[cm4]\notg_mode=0 # Unless CM4\n[all]\n" >> $MNT/$FW/config.txt
        # fi

        # if [ $RELEASE = "ARMBIAN64BULLSEYE" ] && [ ! -f "$MNT/$FW/bcm2710-rpi-zero-2.dtb" ];then
        #     cp $MNT/$FW/bcm2710-rpi-3-b.dtb $MNT/$FW/bcm2710-rpi-zero-2.dtb
        # fi

        if [ $USERSYSLOG -eq 1 ];then
            chroot $MNT apt -y install rsyslog
        fi

        rm -f $MNT/etc/ssh/*key*
        chroot $MNT apt -y autoremove --purge
        chroot $MNT apt clean

        if [ $QEMU -eq 1 ];then
            rm $MNT/usr/bin/qemu-arm-static
            sed -i "s/^#//" $MNT/etc/ld.so.conf
            sed -i "s/^#//" $MNT/etc/ld.so.cache
        fi

        sync
        sleep $SLEEP
        umount -f $MNT/dev/pts
        umount -f $MNT/dev
        umount -f $MNT/proc
        umount $MNT

        zerofree -v ${LOOP}p1
        sleep $SLEEP

        losetup -d $LOOP

        if [ "$FINALISEIMG" != "" ];then
            "$FINALISEIMG" "$FINALISEIMGOPT" "$DEST/$DESTFILENAME-CBRIDGE.img"
            LOOP=`losetup -fP --show $DEST/$DESTFILENAME-CBRIDGE.img`
            zerofree -v ${LOOP}p1
            losetup -d $LOOP
        fi
    fi

    # Build the usbboot image if required
    
    MAXP="MAXP$VARNAME" # Build variable name to check
    if [ ${!MAXP} -gt 0 ] && [ ${!MAXP} -lt 253 ] && [ -f $DEST/$DESTFILENAME-CBRIDGE.img ];then
        for ((P=1;P<=${!MAXP};P++));do
            if [ -f $DEST/$DESTFILENAME-p$P.img ];then
                echo "Skipping $VARNAME P$P (file exists)"
            else
                echo "Creating $VARNAME P$P"
                cp $DEST/$DESTFILENAME-CBRIDGE.img $DEST/$DESTFILENAME-p$P.img
                LOOP=`losetup -fP --show $DEST/$DESTFILENAME-p$P.img`
                sleep $SLEEP

                mount ${LOOP}p1 $MNT
                sed -i "s/^extraargs=\(.*\)/extraargs=\1 init=\/usr\/sbin\/reconfig-clusterctrl p$P/" $MNT/$FW/armbianEnv.txt
                
                echo -e "libcomposite\nsunxi\ng_ether\nusb_f_acm\nu_ether\nusb_f_rndis" > $MNT/etc/modules
                mkdir -p $MNT/etc/modprobe.d
                cat << EOF >> $MNT/etc/modprobe.d/blacklist.conf
blacklist usb_f_eem
blacklist brcmfmac
EOF

                sleep $SLEEP
                sync
                umount $MNT
                
                sleep $SLEEP
                losetup -d $LOOP
            fi
        done
    fi
done