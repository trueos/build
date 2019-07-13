#!/bin/sh
#
# RPI3 disk provision script
#

DISK="$1"
if [ ! -e "/dev/${DISK}" ] ; then
	echo "Missing device /dev/${DISK}"
fi

if [ ! -d "img-mnt" ] ; then
	mkdir img-mnt
fi

gpart create -s MBR ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi
gpart add -t '!12' -a 512k -s 50m ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi
gpart set -a active -i 1 ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi
newfs_msdos -F 16 /dev/${DISK}s1
if [ $? -ne 0 ] ; then
	exit 1
fi
gpart add -t freebsd -a 4m ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi
gpart create -s BSD ${DISK}s2
if [ $? -ne 0 ] ; then
	exit 1
fi
gpart add -t freebsd-ufs ${DISK}s2
if [ $? -ne 0 ] ; then
	exit 1
fi
newfs -U ${DISK}s2a
if [ $? -ne 0 ] ; then
	exit 1
fi

mount /dev/${DISK}s2a img-mnt/
if [ $? -ne 0 ] ; then
	exit 1
fi

# Set up to mount at boot
mkdir -p img-mnt/boot/msdos
mkdir -p img-mnt/etc
cat << EOF > img-mnt/etc/fstab
/dev/mmcsd0s1   /boot/msdos     msdosfs rw,noatime      0 0
/dev/mmcsd0s2a  /               ufs rw,noatime          1 1
md              /tmp            mfs rw,noatime,-s30m    0 0
md              /var/log        mfs rw,noatime,-s15m    0 0
md              /var/tmp        mfs rw,noatime,-s5m     0 0
EOF

cat << EOF > img-mnt/etc/rc.conf
hostname="rpi3"
ifconfig_ue0="DHCP"
EOF

# Disk provision done
