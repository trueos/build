#!/bin/sh
#
# EC2 disk provision script
#

DISK="$1"
if [ ! -e "/dev/${DISK}" ] ; then
	echo "Missing device /dev/${DISK}"
fi

if [ ! -d "img-mnt" ] ; then
	mkdir img-mnt
fi

gpart create -s gpt -f active ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

gpart add -t freebsd-boot -s 512 ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

gpart add -t freebsd-ufs ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

newfs -U -J -L rootfs0 /dev/${DISK}p2
if [ $? -ne 0 ] ; then
	exit 1
fi

mount /dev/${DISK}p2 img-mnt/
if [ $? -ne 0 ] ; then
	exit 1
fi

# Set up to mount at boot
mkdir -p img-mnt/etc
echo "/dev/ufs/rootfs0	/	ufs	rw	1	1" > img-mnt/etc/fstab
if [ $? -ne 0 ] ; then
	exit 1
fi

# Disk provision done
