#!/bin/sh
#
# EC2 disk provision script
#

DISK="$1"
POOL="$2"
if [ ! -e "/dev/${DISK}" ] ; then
	echo "Missing device /dev/${DISK}"
fi

if [ -z "$POOL" ] ; then
	echo "Missing POOL argument"
fi

if [ ! -d "vm-mnt" ] ; then
	mkdir vm-mnt
fi

gpart create -s gpt -f active ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

gpart add -t freebsd-boot -s 512 ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

gpart add -t freebsd-zfs ${DISK}
if [ $? -ne 0 ] ; then
	exit 1
fi

zpool create  -t ${POOL} -m none -R $(pwd)/vm-mnt zroot ${DISK}p2
if [ $? -ne 0 ] ; then
	exit 1
fi

zfs set compression=on ${POOL}
zfs create -o canmount=off ${POOL}/ROOT
zfs create -o canmount=on -o mountpoint=/ ${POOL}/ROOT/initial
zfs create -o canmount=on -o mountpoint=/root ${POOL}/root
zfs create -o canmount=on -o mountpoint=/tmp ${POOL}/tmp
zfs create -o canmount=off ${POOL}/usr
zfs create -o canmount=on -o mountpoint=/usr/home ${POOL}/usr/home
zfs create -o canmount=on -o mountpoint=/usr/jails ${POOL}/usr/jails
zfs create -o canmount=on -o mountpoint=/usr/obj ${POOL}/usr/obj
zfs create -o canmount=on -o mountpoint=/usr/ports ${POOL}/usr/ports
zfs create -o canmount=on -o mountpoint=/usr/src ${POOL}/usr/src
zfs create -o canmount=off ${POOL}/var
zfs create -o canmount=on -o mountpoint=/var/audit ${POOL}/var/audit
zfs create -o canmount=on -o mountpoint=/var/mail ${POOL}/var/mail
zfs create -o canmount=on -o mountpoint=/var/tmp ${POOL}/var/tmp
zpool set bootfs=${POOL}/ROOT/initial ${POOL}

# Disk provision done
