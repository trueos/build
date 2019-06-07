#!/bin/sh
#
# Module: mkisoimages.sh
# Author: Jordan K Hubbard
# Date:   22 June 2001
#
# $FreeBSD$
#
# This script is used by release/Makefile to build the (optional) ISO images
# for a FreeBSD release.  It is considered architecture dependent since each
# platform has a slightly unique way of making bootable CDs.  This script
# is also allowed to generate any number of images since that is more of
# publishing decision than anything else.
#
# Usage:
#
# mkisoimages.sh [-b] image-label image-name base-bits-dir [extra-bits-dir]
#
# Where -b is passed if the ISO image should be made "bootable" by
# whatever standards this architecture supports (may be unsupported),
# image-label is the ISO image label, image-name is the filename of the
# resulting ISO image, base-bits-dir contains the image contents and
# extra-bits-dir, if provided, contains additional files to be merged
# into base-bits-dir as part of making the image.

PATH="${PATH}:/usr/local/bin:/usr/local/sbin"
export PATH

parse_overlay()
{
	OVERLAY="$(jq -r '."iso"."overlay"' $TRUEOS_MANIFEST)"
	if [ "$OVERLAY" = "null" ] ; then
		return
	fi
	OVERLAY_TYPE="$(jq -r '."iso"."overlay"."type"' $TRUEOS_MANIFEST)"
	OVERLAY_URL="$(jq -r '."iso"."overlay"."url"' $TRUEOS_MANIFEST)"
	OVERLAY_BRANCH="$(jq -r '."iso"."overlay"."branch"' $TRUEOS_MANIFEST)"
	export OVERLAY_DIR="tmp/iso-overlay"

	if [ -d "${OVERLAY_DIR}" ] ; then
		rm -rf ${OVERLAY_DIR}
	fi
	mkdir -p ${OVERLAY_DIR}
	if [ $? -ne 0 ] ; then exit 1; fi

	if [ "$OVERLAY_TYPE" = "git" ] ; then
		git clone --depth=1 -b ${OVERLAY_BRANCH} ${OVERLAY_URL} ${OVERLAY_DIR}
		if [ $? -ne 0 ] ; then exit 1; fi
	elif [ "$OVERLAY_TYPE" = "tar" ] ; then
		fetch -o tmp/iso-overlay.tar ${OVERLAY_URL}
		if [ $? -ne 0 ] ; then exit 1; fi
		tar xvpf tmp/iso-overlay.tar -C ${OVERLAY_DIR}
		if [ $? -ne 0 ] ; then exit 1; fi
	elif [ "$OVERLAY_TYPE" = "svn" ] ; then
		if [ -n "$OVERLAY_BRANCH" ] ; then
			SVNREV="@${OVERLAY_BRANCH}"
		fi
		svn checkout ${OVERLAY_URL}${SVNREV} ${OVERLAY_DIR}
		if [ $? -ne 0 ] ; then exit 1; fi
	elif [ "$OVERLAY_TYPE" = "local" ] ; then
		export OVERLAY_DIR="${OVERLAY_URL}"
	fi
}

. scripts/install-boot.sh

if [ -z $ETDUMP ]; then
	ETDUMP=etdump
fi

if [ -z $MAKEFS ]; then
	MAKEFS=makefs
fi

if [ -z $MKIMG ]; then
	MKIMG=mkimg
fi

if [ "$1" = "-b" ]; then
	BASEBITSDIR="$4"
	# This is highly x86-centric and will be used directly below.
	bootable="-o bootimage=i386;$BASEBITSDIR/boot/cdboot -o no-emul-boot"

	# Make EFI system partition (should be done with makefs in the future)
	# The ISO file is a special case, in that it only has a maximum of
	# 800 KB available for the boot code. So make an 800 KB ESP
	espfilename=$(mktemp /tmp/efiboot.XXXXXX)
	make_esp_file ${espfilename} 800 ${BASEBITSDIR}/boot/loader.efi
	bootable="$bootable -o bootimage=i386;${espfilename} -o no-emul-boot -o platformid=efi"

	shift
else
	BASEBITSDIR="$3"
	bootable=""
fi

if [ $# -lt 3 ]; then
	echo "Usage: $0 [-b] image-label image-name base-bits-dir [extra-bits-dir]"
	exit 1
fi

# If there is a TRUEOS_MANIFEST specified, lets include its install-overlay
if [ -n "$TRUEOS_MANIFEST" ] ; then
	parse_overlay
else
	echo "WARNING: TRUEOS_MANIFEST not set"
fi

LABEL=`echo "$1" | tr '[:lower:]' '[:upper:]'`; shift
NAME="$1"; shift

publisher="TrueOS -  https://www.TrueOS.org/"
echo "/dev/iso9660/$LABEL / cd9660 ro 0 0" > "$BASEBITSDIR/etc/fstab"
sync
tar cf - -C$OVERLAY_DIR . | tar xf - -C$BASEBITSDIR
$MAKEFS -t cd9660 $bootable -o rockridge -o label="$LABEL" -o publisher="$publisher" "$NAME" "$@"
rm -f ${espfilename}

if [ "$bootable" != "" ]; then
	# Look for the EFI System Partition image we dropped in the ISO image.
	for entry in `$ETDUMP --format shell $NAME`; do
		eval $entry
		if [ "$et_platform" = "efi" ]; then
			espstart=`expr $et_lba \* 2048`
			espsize=`expr $et_sectors \* 512`
			espparam="-p efi::$espsize:$espstart"
			break
		fi
	done

	# Create a GPT image containing the partitions we need for hybrid boot.
	imgsize=`stat -f %z "$NAME"`
	$MKIMG -s gpt \
	    --capacity $imgsize \
	    -b "$BASEBITSDIR/boot/pmbr" \
	    $espparam \
	    -p freebsd-boot:="$BASEBITSDIR/boot/isoboot" \
	    -o hybrid.img

	# Drop the PMBR, GPT, and boot code into the System Area of the ISO.
	dd if=hybrid.img of="$NAME" bs=32k count=1 conv=notrunc
	rm -f hybrid.img
fi
