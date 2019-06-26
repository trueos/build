#!/bin/sh
#
# Copyright (c) 2019 Kris Moore
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$
#

export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

delete_tmp_manifest(){	
	if [ -e "${TRUEOS_MANIFEST}.orig" ] ; then	
		#Put the original manifest file back in place	
		mv "${TRUEOS_MANIFEST}.orig" "${TRUEOS_MANIFEST}"	
	fi	
}	


exit_err()
{
	echo "ERROR: $1"
	delete_tmp_manifest
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}

get_architecture()
{
	if jq -e -r '."arch"' $TRUEOS_MANIFEST 2>&1 >/dev/null ; then
		local arch="$(jq -r '."arch"."arch"' $TRUEOS_MANIFEST)"
		if jq -e -r '."arch"."platform"' $TRUEOS_MANIFEST 2>&1 >/dev/null ; then
			local platform="$(jq -r '."arch"."platform"' $TRUEOS_MANIFEST)"
		else
			local platform="${arch}"
		fi
	else
		local arch="native"
	fi 
	echo $platform.$arch
}

get_arch()
{
	get_architecture | cut -d'.' -f2
}

get_platform()
{
	get_architecture | cut -d'.' -f1
}


if [ -z "$TRUEOS_MANIFEST" ] ; then
	if [ -e ".config/manifest" ] ; then
		export TRUEOS_MANIFEST="$(pwd)/manifests/$(cat .config/manifest)"
	elif [ -e "$(pwd)/manifests/trueos-snapshot-builder.json" ] ; then
		export TRUEOS_MANIFEST="$(pwd)/manifests/trueos-snapshot-builder.json"
	fi
fi


if [ -z "$TRUEOS_MANIFEST" ] ; then
	exit_err "Unset TRUEOS_MANIFEST"
fi

#Perform any directory replacements in the manifest as needed
grep -q "%%PWD%%" "${TRUEOS_MANIFEST}"
if [ $? -eq 0 ] ; then
	echo "Replacing PWD paths in Build Manifest..."
	cp "${TRUEOS_MANIFEST}" "${TRUEOS_MANIFEST}.orig"
	sed -i '' "s|%%PWD%%|$(dirname ${TRUEOS_MANIFEST})|g" "${TRUEOS_MANIFEST}"
fi

CHECK=$(jq -r '."poudriere"."jailname"' $TRUEOS_MANIFEST)
if [ -n "$CHECK" -a "$CHECK" != "null" ] ; then
	POUDRIERE_BASE="$CHECK"
fi
CHECK=$(jq -r '."poudriere"."portsname"' $TRUEOS_MANIFEST)
if [ -n "$CHECK" -a "$CHECK" != "null" ] ; then
	POUDRIERE_PORTS="$CHECK"
fi

platform="$(get_platform)"


# Set our important defaults
POUDRIERE_BASEFS=${POUDRIERE_BASEFS:-/usr/local/poudriere}
POUDRIERE_BASE=${POUDRIERE_BASE:-trueos-mk-base%%ARCH%%}
#Using platform as it is should match or be more unique then arch
POUDRIERE_BASE=$( echo ${POUDRIERE_BASE} | sed "s|%%ARCH%%|${platform}|g" )
POUDRIERE_PORTS=${POUDRIERE_PORTS:-trueos-mk-ports}
PKG_CMD=${PKG_CMD:-pkg-static}

POUDRIERE_JAILDIR="${POUDRIERE_BASEFS}/jails/${POUDRIERE_BASE}"
POUDRIERE_PORTDIR="${POUDRIERE_BASEFS}/ports/${POUDRIERE_PORTS}"
POUDRIERE_PKGDIR="${POUDRIERE_BASEFS}/data/packages/${POUDRIERE_BASE}-${POUDRIERE_PORTS}"
POUDRIERE_LOGDIR="${POUDRIERE_BASEFS}/data/logs"
POUDRIERE_PKGLOGS="${POUDRIERE_LOGDIR}/bulk/${POUDRIERE_BASE}-${POUDRIERE_PORTS}"
POUDRIERED_DIR=/usr/local/etc/poudriere.d

# Temp location for ISO files
ISODIR="tmp/iso"

# Temp pool name to use for VM creation
VMPOOLNAME="${VMPOOLNAME:-vm-gen-pool}"

#Source the ports-interactions scripts
. "$(dirname $0)/ports-interactions.sh"
		
# Validate that we have a good TRUEOS_MANIFEST and sane build environment
env_check()
{
	echo "Using TRUEOS_MANIFEST: $TRUEOS_MANIFEST" >&2
	PORTS_TYPE=$(jq -r '."ports"."type"' $TRUEOS_MANIFEST)
	if [ $? -ne 0 ] ; then
	  exit_err "Unable to parse manifest: Check JSON syntax"
	fi
	PORTS_URL=$(jq -r '."ports"."url"' $TRUEOS_MANIFEST)
	PORTS_BRANCH=$(jq -r '."ports"."branch"' $TRUEOS_MANIFEST)

	if [ -z "${TRUEOS_VERSION}" ] ; then
		TRUEOS_VERSION=$(jq -r '."os_version"' $TRUEOS_MANIFEST)
	fi
	case $PORTS_TYPE in
		git) if [ -z "$PORTS_BRANCH" ] ; then
			exit_err "Empty ports.branch!"
		     fi ;;
		svn) ;;
		github-tar) ;;
		local) ;;
		tar) ;;
		*) exit_err "Unknown or unspecified ports.type!" ;;
	esac

	/usr/bin/which -s poudriere
	if [ $? -ne 0 ] ; then
		exit_err "poudriere does not appear to be installed!"
	fi
	if [ -z "$PORTS_URL" ] && [ "${PORTS_TYPE}" != "github-overlay" ] ; then
		exit_err "Empty ports.url!"
	fi

	if [ ! -d '/usr/ports/distfiles' ] ; then
		mkdir /usr/ports/distfiles
	fi
}

setup_poudriere_conf()
{
	echo "Creating poudriere configuration"

	# Check if a default ZPOOL has been setup in poudriere.conf and use that
	DEFAULT_ZPOOL=$(grep "^ZPOOL=" /usr/local/etc/poudriere.conf | cut -d '=' -f 2)
	if [ -n "${DEFAULT_ZPOOL}" ] ; then
		ZPOOL="${DEFAULT_ZPOOL}"
	else
		ZPOOL=$(mount | grep 'on / ' | cut -d '/' -f 1)
	fi
	DEFAULT_DISTFILES="/usr/ports/distfiles"
	DISTFILES=$(grep "^DISTFILES_CACHE=" /usr/local/etc/poudriere.conf | head -n 1 | cut -d '=' -f 2)
	if [ -z "${DISTFILES}" ] ; then
		DISTFILES="${DEFAULT_DISTFILES}"
	fi
	_pdconf="${POUDRIERED_DIR}/${POUDRIERE_PORTS}-poudriere.conf"
	_pdconf2="${POUDRIERED_DIR}/${POUDRIERE_BASE}-poudriere.conf"

	if [ ! -d "${POUDRIERED_DIR}" ] ; then
		mkdir -p ${POUDRIERED_DIR}
	fi

	# Setup the zpool on the default poudriere.conf if necessary
	# This is so the user can run regular poudriere commands on these
	# builds for testing and development
	grep -q "^ZPOOL=" /usr/local/etc/poudriere.conf
	if [ $? -ne 0 ] ; then
		echo "ZPOOL=$ZPOOL" >> /usr/local/etc/poudriere.conf
	fi
	#Ensure that the basefs variable is setup as well - needed for iterative builds.
	grep -q "^BASEFS=" /usr/local/etc/poudriere.conf
	if [ $? -ne 0 ] ; then
		echo "BASEFS=$POUDRIERE_BASEFS" >> /usr/local/etc/poudriere.conf
	fi

	# Copy the systems poudriere.conf over
	cat /usr/local/etc/poudriere.conf.sample \
		| grep -v "ZPOOL=" \
		| grep -v "FREEBSD_HOST=" \
		| grep -v "GIT_PORTSURL=" \
		| grep -v "USE_TMPFS=" \
		| grep -v "BASEFS=" \
		> ${_pdconf}
	echo "Using zpool: $ZPOOL"
	echo "ZPOOL=$ZPOOL" >> ${_pdconf}
	echo "Using Ports Tree: ${POUDRIERE_PORTS}"
	echo "USE_TMPFS=yes" >> ${_pdconf}
	echo "BASEFS=$POUDRIERE_BASEFS" >> ${_pdconf}
	echo "ATOMIC_PACKAGE_REPOSITORY=no" >> ${_pdconf}
	echo "DISTFILES_CACHE=${DISTFILES}" >> ${_pdconf}
	#echo "PKG_REPO_FROM_HOST=yes" >> ${_pdconf}
	echo "ALLOW_MAKE_JOBS_PACKAGES=\"chromium* iridium* aws-sdk* gcc* webkit* llvm* clang* firefox* ruby* cmake* rust* qt5-web* phantomjs* swift* perl5* py*\"" >> ${_pdconf}
	echo "PRIORITY_BOOST=\"pypy* openoffice* iridium* chromium* aws-sdk* libreoffice*\"" >> ${_pdconf}

	# Set all the make config variables from our build
	if [ "$(jq -r '."poudriere-conf" | length' ${TRUEOS_MANIFEST})" != "0" ] ; then
		jq -r '."poudriere-conf" | join("\n")' ${TRUEOS_MANIFEST} >> ${_pdconf}
	fi

	# Do we have a signing key to use?
	if [ -n "${SIGNING_KEY}" ] ; then
	       echo "PKG_REPO_SIGNING_KEY=${SIGNING_KEY}" >> ${_pdconf}
	fi

	# If there is a custom poudriere.conf.release file in /etc we will also
	# include it. This can be used to set different tmpfs or JOBS on a per system
	# basis
	if [ -e "/etc/poudriere.conf.release" ] ; then
		cat /etc/poudriere.conf.release >> ${_pdconf}
	fi
	cp ${_pdconf} ${_pdconf2} 2>/dev/null

	# Set the TRUEOS_MANIFEST location for os/* build ports
	echo "TRUEOS_MANIFEST=${TRUEOS_MANIFEST}" > ${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf

	# Save kernel/world flags as well
	get_world_flags | sed 's|^ ||g' | tr -s ' ' '\n' >> ${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf
	get_kernel_flags | sed 's|^ ||g' | tr -s ' ' '\n' >> ${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf
}

# We don't need to store poudriere data in our checked out location
# This is to ensure we can use poudriere testport and other commands
# directly in development
#
# Instead lets create some symlinks to important output directories
create_release_links()
{
	rm release/packages >/dev/null 2>/dev/null
	ln -fs ${POUDRIERE_PKGDIR} release/packages
	rm release/src-logs >/dev/null 2>/dev/null
	ln -fs ${POUDRIERE_LOGDIR}/base-ports release/src-logs
	rm release/port-logs >/dev/null 2>/dev/null
	ln -fs ${POUDRIERE_PKGLOGS} release/port-logs
}

assemble_file_manifest(){
	# Assemble a manifest.json file containing references to all the files in this directory.
	# INPUTS
	# $1 : Directory to scan and place the manifest
	local dir="$1"
	local mfile="${dir}/manifest.json"
	echo "Assemble file manifest: ${mfile}"
	local manifest
	local var
	for file in `ls "${dir}"` ; do
		name="$(basename ${file})"
		var=""
		case "${name}" in
			*.iso)
				var="\"iso_file\" : \"${name}\", \"iso_size\" : \"$(ls -lh ${dir}/${name} | cut -w -f 5)\""
				;;
			*.img)
				var="\"img_file\" : \"${name}\", \"img_size\" : \"$(ls -lh ${dir}/${name} | cut -w -f 5)\""
				;;
			*.sig.*)
				var="\"signature_file\" : \"${name}\""
				;;
			*.md5)
				var="\"md5_file\" : \"${name}\", \"md5\" : \"$(cat ${dir}/${name})\""
				;;
			*.sha256)
				var="\"sha256_file\" : \"${name}\", \"sha256\" : \"$(cat ${dir}/${name})\""
				;;
		esac
		if [ -n "${var}" ] ; then
			if [ -n "${manifest}" ] ; then
				#Next item in the object
				manifest="${manifest}, ${var}"
			else
				#First item
				manifest="${var}"
			fi
		fi
	done
	if [ -n "${manifest}" ] ; then
		# Also inject the date/time of the current build here
		local _date=`date -ju "+%Y_%m_%d %H:%M %Z"`
		local _date_secs=`date -j +%s`
		manifest="${manifest}, \"build_date\" : \"${_date}\", \"build_date_time_t\" : \"${_date_secs}\", \"version\" : \"${TRUEOS_VERSION}\""
		echo "{ ${manifest} }" > "${mfile}"
		return 0
	else
		# No files? Return an error
		echo " [ERROR] Could not assemble file manifest: ${mfile}"
		return 1
	fi
}

is_ports_dirty()
{
	# Does ports tree already exist?
	echo "Scanning for existing ports tree: ${POUDRIERE_PORTS}"
	poudriere ports -l 2>/dev/null | grep -q -w ${POUDRIERE_PORTS}
	if [ $? -ne 0 ]; then
		echo "Ports tree does not exist yet: ${POUDRIERE_PORTS}"
		return 1
	fi

	PDIR="$(poudriere ports -l 2>/dev/null | grep -w ${POUDRIERE_PORTS} | cut -w -f5)"
	CURBRANCH=$(cd ${PDIR} 2>/dev/null && git branch | awk '{print $2}')
	if [ -z "$CURBRANCH" ] ; then
		echo "Unable to detect branch, checking out ports fresh"
		echo -e "y\n" | poudriere ports -d -p ${POUDRIERE_PORTS}
		return 1
	fi

	# Have we changed branches?
	if [ "$CURBRANCH" != "${PORTS_BRANCH}" ] ; then
		echo "Branch change detected, checking out ports fresh"
		echo -e "y\n" | poudriere ports -d -p ${POUDRIERE_PORTS}
		return 1
	fi

	# Need to make sure ports is clean before updating, poudriere won't return non-0
	# if it fails
	(cd ${PDIR} && git reset --hard)

	# Looks like we are safe to try an in-place upgrade
	echo "Updating previous poudriere ports tree"
	poudriere ports -u -p ${POUDRIERE_PORTS}
	if [ $? -ne 0 ] ; then
		echo "Failed updating, checking out ports fresh"
		echo -e "y\n" | poudriere ports -d -p ${POUDRIERE_PORTS}
		return 1
	fi
	return 0
}

# Called to import the ports tree into poudriere specified in MANIFEST
setup_poudriere_ports()
{
	is_ports_dirty
	if [ $? -ne 0 ] ; then
		create_poudriere_ports
	fi

	# Do we have any locally checked out sources to copy into poudirere jail?
	LOCAL_SOURCE_DIR=${LOCAL_SOURCE_DIR:-source}
	if [ -n "$LOCAL_SOURCE_DIR" -a -d "${LOCAL_SOURCE_DIR}" ] ; then
		if [ ! -d "${POUDRIERE_PORTDIR}" ] ; then
			mkdir -p ${POUDRIERE_PORTDIR}
		fi
		rm -rf ${POUDRIERE_PORTDIR}/local_source 2>/dev/null
		cp -a ${LOCAL_SOURCE_DIR} ${POUDRIERE_PORTDIR}/local_source
		if [ $? -ne 0 ] ; then
			exit_err "Failed copying ${LOCAL_SOURCE_DIR} -> ${POUDRIERE_PORTDIR}/local_source"
		fi
	fi

	# If TRUEOS_MANIFEST is set, copy to ports for later os/manifest to ingest
	if [ -n "$TRUEOS_MANIFEST" ] ; then
		echo "Copying build manifest into ports tree"
		if [ ! -d "${POUDRIERE_PORTDIR}/local_source" ] ; then
			mkdir -p ${POUDRIERE_PORTDIR}/local_source
		fi
		cp ${TRUEOS_MANIFEST} ${POUDRIERE_PORTDIR}/local_source/trueos-manifest.json
		if [ $? -ne 0 ] ; then
			exit_err "Failed copying manifest into ports -> ${POUDRIERE_PORTDIR}/local_source"
		fi

		# Copy manifest for buildworld port
		if [ -d "${POUDRIERE_PORTDIR}/os/buildworld" ] ; then
			if [ ! -d "${POUDRIERE_PORTDIR}/os/buildworld/files" ] ; then
				mkdir -p ${POUDRIERE_PORTDIR}/os/buildworld/files
			fi
			cp ${TRUEOS_MANIFEST} ${POUDRIERE_PORTDIR}/os/buildworld/files/trueos-manifest.json
			if [ $? -ne 0 ] ; then
				exit_err "Failed copying manifest into ports -> ${POUDRIERE_PORTDIR}/os/buildworld/files/"
			fi
		fi
	fi

	# Add any list of files to strip from port plists
	# Verify we have anything to strip in our MANIFEST
	if [ "$(jq -r '."base-packages"."strip-plist" | length' $TRUEOS_MANIFEST)" != "0" ] ; then
		jq -r '."base-packages"."strip-plist" | join("\n")' $TRUEOS_MANIFEST > ${POUDRIERE_PORTDIR}/strip-plist-ports
	else
		rm ${POUDRIERE_PORTDIR}/strip-plist-ports >/dev/null 2>/dev/null
	fi


	for c in $(jq -r '."ports"."make.conf" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		jq -r '."ports"."make.conf"."'$c'" | join("\n")' ${TRUEOS_MANIFEST} >>${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf
	done

	# Set the BUILD_EPOCH_TIME for ports that ingest, such as freenas
	echo "BUILD_EPOCH_TIME=${BUILD_EPOCH_TIME}" >>${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf

	# Setup the OS sources for build
	checkout_os_sources
}

create_poudriere_ports()
{
	# Create the new ports tree
	echo "Creating poudriere ports tree"
	if [ "$PORTS_TYPE" = "git" ] ; then
		poudriere ports -c -p $POUDRIERE_PORTS -m git -U "${PORTS_URL}" -B $PORTS_BRANCH
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports - GIT"
		fi

	elif [ "$PORTS_TYPE" = "svn" ] ; then
		poudriere ports -c -p $POUDRIERE_PORTS -m svn -U "${PORTS_URL}" -B $PORTS_BRANCH
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports - SVN"
		fi

	elif [ "$PORTS_TYPE" = "tar" ] ; then
		echo "Fetching ports tarball"
		fetch -o tmp/ports.tar ${PORTS_URL}
		if [ $? -ne 0 ] ; then
			exit_err "Failed fetching poudriere ports - TARBALL"
		fi

		rm -rf tmp/ports-tree
		mkdir -p tmp/ports-tree

		echo "Extracting ports tarball"
		tar xvf tmp/ports.tar -C tmp/ports-tree 2>/dev/null
		if [ $? -ne 0 ] ; then
			exit_err "Failed extracting poudriere ports"
		fi

		# Apply any ports overlay
		apply_ports_overlay "tmp/ports-tree"

		poudriere ports -c -p $POUDRIERE_PORTS -m null -M tmp/ports-tree
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports"
		fi

	elif [ "${PORTS_TYPE}" = "github-tar" ] ; then
		#Now checkout the ports tree and apply the overlay
		local portsdir=$(pwd)/tmp/$(basename -s ".json" "${TRUEOS_MANIFEST}")
		checkout_gh_ports "${portsdir}"
		if [ $? -ne 0 ] ; then
			exit_err "Failed fetching poudriere ports: github-tar"
		fi
		# Now do the nullfs mount into poudriere
		poudriere ports -c -p $POUDRIERE_PORTS -m null -M "${portsdir}"
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports"
		fi
		# Also fix the internal variable pointing to the location of the ports tree on disk
		# This is used for checking essential packages later
		POUDRIERE_PORTDIR=${portsdir}
		
	else
		# LOCAL TYPE
		# Apply any ports overlay
		apply_ports_overlay "${PORTS_URL}"
		# Doing a nullfs mount of existing directory
		poudriere ports -c -p $POUDRIERE_PORTS -m null -M ${PORTS_URL}
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports - NULLFS"
		fi
		# Also fix the internal variable pointing to the location of the ports tree on disk
		# This is used for checking essential packages later
		POUDRIERE_PORTDIR=${PORTS_URL}
	fi
}

checkout_os_sources()
{

	# Checkout sources
	GITREPO=$(jq -r '."base-packages"."repo"' ${TRUEOS_MANIFEST} 2>/dev/null)
	GITBRANCH=$(jq -r '."base-packages"."branch"' ${TRUEOS_MANIFEST} 2>/dev/null)
	if [ -z "${GITREPO}" -o -z "${GITBRANCH}" ] ; then
		exit_err "Missing base-packages repo/branch"
	fi

	rm -rf tmp/os
	git clone --depth=1 -b ${GITBRANCH} ${GITREPO} tmp/os
	if [ $? -ne 0 ] ; then
		exit_err "Failed checking out OS sources"
	fi

	if [ ! -e "tmp/os/sys/conf/package-version" ] ; then
		# Get the date of these git sources for hard-coding OS version / timestamp
		OSDATE=$(git -C tmp/os log -1 --date=format:'%Y%m%d%H%M%S' | grep "Date:" | awk '{print $2}')
		echo "${OSDATE}" > tmp/os/sys/conf/package-version
	fi

	export BASEPKG_SRCDIR=$(pwd)/tmp/os
}

is_jail_dirty()
{
	poudriere jail -l | grep -q -w "${POUDRIERE_BASE}"
	if [ $? -ne 0 ] ; then
		return 1
	fi

	echo "Checking existing jail"

	# Check if we need to build the jail - skip if existing pkg is updated
	pkgName=$(make -C ${POUDRIERE_PORTDIR}/os/src -V PKGNAME PORTSDIR=${POUDRIERE_PORTDIR} __MAKE_CONF=${OBJDIR}/poudriere.d/${POUDRIERE_BASE}-make.conf)
	echo "Looking for ${POUDRIERE_PKGDIR}/All/${pkgName}.txz"
	if [ ! -e "${POUDRIERE_PKGDIR}/All/${pkgName}.txz" ] ; then
		echo "Different os/src detected for ${POUDRIERE_BASE} jail"
		return 1
	fi

	# Do our options files exist?
	if [ ! -e "${POUDRIERE_PKGDIR}/buildworld.options" ] ; then
		return 1
	fi
	if [ ! -e "${POUDRIERE_PKGDIR}/buildkernel.options" ] ; then
		return 1
	fi

	# Have the world options changed?
	newOpt=$(get_world_flags | tr -d ' ' | md5)
	oldOpt=$(cat ${POUDRIERE_PKGDIR}/buildworld.options | md5)
	if [ "${newOpt}" != "${oldOpt}" ] ;then
		echo "New world flags detected!"
		return 1
	fi
	# Have the kernel options changed?
	newOpt=$(get_kernel_flags | tr -d ' ' | md5)
	oldOpt=$(cat ${POUDRIERE_PKGDIR}/buildkernel.options | md5)
	if [ "${newOpt}" != "${oldOpt}" ] ;then
		echo "New kernel flags detected!"
		return 1
	fi

	# Have the os port options changed?
	newOpt=$(get_os_port_flags | tr -d ' ' | md5)
	oldOpt=$(cat ${POUDRIERE_PKGDIR}/osport.options | md5)
	if [ "${newOpt}" != "${oldOpt}" ] ;then
		echo "New os_ options detected!"
		return 1
	fi

	# Jail is sane!
	return 0
}

remove_basepkg_srcdir()
{
	unset BASEPKG_SRCDIR
}

# Checks if we have a new base ports jail to build, if so we will rebuild it
setup_poudriere_jail()
{
	is_jail_dirty
	if [ $? -eq 0 ] ; then
		# Jail is updated, we can skip build
		return 0
	fi

	poudriere jail -l | grep -q -w "${POUDRIERE_BASE}"
	if [ $? -eq 0 ] ; then
		# Remove old version
		echo -e "y\n" | poudriere jail -d -j ${POUDRIERE_BASE}
	fi

	echo "Rebuilding ${POUDRIERE_BASE} jail"

	# Clean out old logs
	rm ${POUDRIERE_LOGDIR}/base-ports/*

	# Make sure local port options are gone for os/buildworld and os/buildkernel
	# These conflict with options passed in via __MAKE_CONF
	if [ -d "/var/db/ports/os_buildworld" ] ; then
		rm -rf /var/db/ports/os_buildworld
	fi
	if [ -d "/var/db/ports/os_buildkernel" ] ; then
		rm -rf /var/db/ports/os_buildkernel
	fi

	echo "Using source make.conf"
	echo "----------------------------"
	cat ${POUDRIERED_DIR}/${POUDRIERE_BASE}-make.conf

	# Set alternative source location
	sed -i '' "s|/usr/src|${BASEPKG_SRCDIR}|g" ${POUDRIERE_PORTDIR}/os/Makefile.common

	export KERNEL_MAKE_FLAGS="$(get_kernel_flags)"
	export WORLD_MAKE_FLAGS="$(get_world_flags)"
	architecture="$(get_architecture)"
	if [ $architecture == ".native" ] ; then
		poudriere jail -c -j $POUDRIERE_BASE -m ports=${POUDRIERE_PORTS} -v ${TRUEOS_VERSION}
	else
		poudriere jail -c -j $POUDRIERE_BASE -m ports=${POUDRIERE_PORTS} -v ${TRUEOS_VERSION} -a ${architecture}
	fi
	if [ $? -ne 0 ] ; then
		exit 1
	fi
	sed -i '' "s|${BASEPKG_SRCDIR}|/usr/src|g" ${POUDRIERE_PORTDIR}/os/Makefile.common

	# Get ABI of the new jail
	NEWABI=$(cat ${POUDRIERE_JAILDIR}/usr/include/sys/param.h | grep '#define __FreeBSD_version' | awk '{print $3}')

	# Nuke old packages if the ABI has changed
	if [ -d "${POUDRIERE_PKGDIR}" -a "${POUDRIERE_PKGDIR}" != "/" ] ; then
		if [ "$(cat ${POUDRIERE_PKGDIR}/os.abi 2>/dev/null)" != "${NEWABI}" ] ; then
			rm -r ${POUDRIERE_PKGDIR}/*
		fi
	fi

	# Make sure pkg directory exists
	if [ ! -d "${POUDRIERE_PKGDIR}" ] ; then
		mkdir -p ${POUDRIERE_PKGDIR}
	fi

	# Save the new ABI
	echo "$NEWABI" > ${POUDRIERE_PKGDIR}/os.abi

	# Save the options used for this build
	get_kernel_flags | tr -d ' ' > ${POUDRIERE_PKGDIR}/buildkernel.options
	get_world_flags | tr -d ' ' > ${POUDRIERE_PKGDIR}/buildworld.options
	get_os_port_flags | tr -d ' ' > ${POUDRIERE_PKGDIR}/osport.options
}

# Scrape the MANIFEST for list of packages to build
get_pkg_build_list()
{
	# Check for any conditional packages to build in ports
	for c in $(jq -r '."ports"."build" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		echo "Getting packages in JSON ports.build -> $c"
		# We have a conditional set of packages to include, lets do it
		jq -r '."ports"."build"."'$c'" | join("\n")' ${TRUEOS_MANIFEST} >> ${1} 2>/dev/null
	done

	# Check for any conditional packages to build in iso
	for pkgstring in iso-packages dist-packages auto-install-packages
	do
		for c in $(jq -r '."iso"."'$pkgstring'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

			echo "Getting packages in JSON iso.$pkgstring -> $c"
			# We have a conditional set of packages to include, lets do it
			jq -r '."iso"."'$pkgstring'"."'$c'" | join("\n")' ${TRUEOS_MANIFEST} >> ${1} 2>/dev/null
		done
	done

	# Sort and remove dups
	cat ${1} | sort -r | uniq > ${1}.new
	mv ${1}.new ${1}
}

# Start the poudriere build jobs
build_poudriere()
{
	# Check if we want to do a bulk build of everything
	if [ $(jq -r '."ports"."build-all"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		# Start the build
		echo "Starting poudriere FULL build"
		poudriere bulk -a -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}
		# Do not exit if non-zero : poudriere report non-zero return if *any* ports fail to build
		#   and a bulk/full build is almost guaranteed to have some failures.
		#if [ $? -ne 0 ] ; then
		#	exit_err "Failed poudriere build"
		#fi
		check_essential_pkgs
		if [ $? -ne 0 ] ; then
			exit_err "Failed building all essential packages.."
		fi
	else
		rm tmp/trueos-mk-bulk-list 2>/dev/null
		echo "Starting poudriere SELECTIVE build"
		get_pkg_build_list tmp/trueos-mk-bulk-list

		echo "Starting poudriere to build:"
		echo "------------------------------------"
		cat tmp/trueos-mk-bulk-list

		# Start the build
		echo "Starting: poudriere bulk -f $(pwd)/trueos-mk-bulk-list -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}"
		echo "------------------------------------"
		poudriere bulk -f $(pwd)/tmp/trueos-mk-bulk-list -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}
		if [ $? -ne 0 ] ; then
			exit_err "Failed poudriere build"
		fi
	fi
	# Assemble the package manifests as needed
	if [ $(jq -r '."ports"."generate-manifests"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		#Cleanup the output directory first
		local mandir="release/pkg-manifests"
		if [ -d "${mandir}" ] ; then
			rm ${mandir}/*
		else
			mkdir -p "${mandir}"
		fi
		echo "Generating Package Manifests in ${pwd}/${mandir}"
		# Copy over the relevant files from the ports tree
		cp "$(find ${POUDRIERE_PORTDIR} -maxdepth 3 -name MOVED)" ${mandir}/MOVED
		cp "$(find ${POUDRIERE_PORTDIR} -maxdepth 3 -name UPDATING)" ${mandir}/UPDATING
		cp "$(find ${POUDRIERE_PORTDIR} -maxdepth 3 -name CHANGES)" ${mandir}/CHANGES
		# Assemble a quick list of all the ports/packages that are available in the repo
		mk_repo_config
		pkg-static -R tmp/repo-config rquery -a "%o : %n : %v" > "${mandir}/pkg.list"
	fi
	return 0
}

clean_poudriere()
{
	# Make sure the pkgdir exists
	if [ ! -d "${POUDRIERE_PKGDIR}" ] ; then
		mkdir -p "${POUDRIERE_PKGDIR}/All"
	fi

	# Delete previous ports tree
	echo -e "y\n" | poudriere ports -d -p ${POUDRIERE_PORTS}

	# Delete previous jail
	echo -e "y\n" | poudriere jail -d -j ${POUDRIERE_BASE}
}

super_clean_poudriere()
{
	#Look for any leftover mountpoints/directories and remove them too
	for i in `ls ${POUDRIERED_DIR}/*-make.conf 2>/dev/null`
	do
		name=`basename "${i}" | sed 's|-make.conf||g'`
		if [ ! -d "${POUDRIERED_DIR}/jails/${name}" ]  && [ -d "${POUDRIERE_BASEFS}/jails/${name}" ] ; then
			#Jail configs missing, but jail mountpoint still exists
			#Need to completely destroy the old jail dataset/dir
			_stale_dataset=$(mount | grep 'on ${POUDRIERE_BASEFS}/jails/${name} ' | cut -w -f 1)
			if [ -n "${_stale_dataset}" ] ; then
				#Found a stale mountpoint/dataset
				umount ${POUDRIERE_BASEFS}/jails/${name}
				rmdir ${POUDRIERE_BASEFS}/jails/${name}
				#Verify that it is a valid ZFS dataset
				zfs list "${_stale_dataset}"
				if [ 0 -eq $? ] ; then
					zfs destroy -r ${_stale_dataset}
				fi
			fi
		fi
	done
}

# If we did a bulk -a of poudriere, ensure we have everything mentioned in the MANIFEST
check_essential_pkgs()
{
	echo "Checking essential-packages..."
	local haveWarn=0

	ESSENTIAL="os/userland os/kernel"

	# Check for any conditional packages to build in ports
	for c in $(jq -r '."ports"."build" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		ESSENTIAL="$ESSENTIAL $(jq -r '."ports"."build"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})"
	done

	#Check any other iso lists for essential packages
	local _checklist="iso-packages auto-install-packages dist-packages"
	# Check for any conditional packages to build in iso
	for ptype in ${_checklist}
	do
		for c in $(jq -r '."iso"."'$ptype'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

			# We have a conditional set of packages to include, lets do it
			ESSENTIAL="$ESSENTIAL $(jq -r '."iso"."'$ptype'"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})"
		done
	done

	# Cleanup whitespace
	ESSENTIAL=$(echo $ESSENTIAL | awk '{$1=$1;print}')

	if [ -z "$ESSENTIAL" ] ; then
		echo "No essential-packages defined. Skipping..."
		return 0
	fi

	local _missingpkglist=""
	for i in $ESSENTIAL
	do
		if [ ! -d "${POUDRIERE_PORTDIR}/${i}" ] ; then
			echo "WARNING: Invalid PORT: $i"
			_missingpkglist="${_missingpkglist} ${i}"
			haveWarn=1
		fi

		# Get the pkgname
		unset pkgName
		pkgName=$(make -C ${POUDRIERE_PORTDIR}/${i} -V PKGNAME PORTSDIR=${POUDRIERE_PORTDIR} __MAKE_CONF=${OBJDIR}/poudriere.d/${POUDRIERE_BASE}}-make.conf)
		if [ -z "${pkgName}" ] ; then
			echo "WARNING: Could not get PKGNAME for ${i}"
			_missingpkglist="${_missingpkglist} ${i}"
			haveWarn=1
		fi

		if [ ! -e "${POUDRIERE_PKGDIR}/All/${pkgName}.txz" ] ; then
			echo "Checked: ${POUDRIERE_PKGDIR}/All/${pkgName}.txz"
			echo "WARNING: Missing package ${pkgName} for port ${i}"
			_missingpkglist="${_missingpkglist} ${pkgName}"
			haveWarn=1
		else
			echo "Verified: ${pkgName}"
		fi
	done
	if [ $haveWarn -eq 1 ] ; then
		echo "WARNING: Essential Packages Missing: ${_missingpkglist}"
	fi
	return $haveWarn
}

clean_jails()
{
	clean_poudriere
	super_clean_poudriere
}

run_poudriere()
{
	setup_poudriere_conf
	setup_poudriere_ports
	setup_poudriere_jail
	build_poudriere
}

mk_repo_config()
{
	rm -rf tmp/repo-config
	mkdir -p tmp/repo-config

	cat >tmp/repo-config/repo.conf <<EOF
base: {
  url: "file://${POUDRIERE_PKGDIR}",
  signature_type: "none",
  enabled: yes,
}
EOF

}

sign_file(){
	# Sign a file with openssl
	local file="$1"

	if [ -z "${SIGNING_KEY}" ] ; then
		echo "No signing key provided - skipping signing of file: ${file}"
		return 0
	fi
	echo "Signing file: ${file}"
	openssl dgst -sha512 -sign "${SIGNING_KEY}" -out "${file}.sig.sha512" "${file}"
	if [ $? -ne 0 ] ; then
		echo "ERROR signing file!"
		return 1
	fi
	echo " - Generating pubkey for signature verification"
	# Need an actual file for the pubkey
	local keyfile
	if [ -e "${SIGNING_KEY}" ] ; then
		keyfile="${SIGNING_KEY}"
	else
		keyfile="_internal_priv.key"
		echo "${SIGNING_KEY}" > "${keyfile}"
	fi
	openssl rsa -in "${keyfile}" -pubout -out $(dirname "${file}")/pubkey.pem
	#Make sure we delete any temporary private key file
	if [ "${keyfile}" = "_internal_priv.key" ] ; then
		rm "${keyfile}"
	fi
	return 0
}

clean_iso_dir()
{
	if [ ! -d "${ISODIR}" ] ; then
		return 0
	fi
	rm -rf ${ISODIR} >/dev/null 2>/dev/null
	chflags -R noschg ${ISODIR} >/dev/null 2>/dev/null
	rm -rf ${ISODIR}
}

create_iso_dir()
{
	clean_iso_dir

	mk_repo_config

	ABI=$(pkg-static -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh config ABI)
	PKG_DISTDIR="${ISODIR}/dist/${ABI}/latest"
	mkdir -p "${PKG_DISTDIR}"

	mkdir -p ${ISODIR}/tmp
	mkdir -p ${ISODIR}/var/db/pkg
	cp -r tmp/repo-config ${ISODIR}/tmp/repo-config

	export PKG_DBDIR="tmp/pkgdb"

	# Check for conditionals packages to install
	for c in $(jq -r '."iso"."iso-base-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		for i in $(jq -r '."iso"."iso-base-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			BASE_PACKAGES="${BASE_PACKAGES} ${i}"
		done
	done

	if [ -z "$BASE_PACKAGES" ] ; then
		# No custom base packages specified, lets roll with the defaults
		BASE_PACKAGES="os/userland os/kernel ports-mgmt/pkg"
	else
		# We always need pkg itself
		BASE_PACKAGES="${BASE_PACKAGES} ports-mgmt/pkg"
	fi

	# Install the base packages into iso dir
	for pkg in ${BASE_PACKAGES}
	do
		pkg-static -r ${ISODIR} -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
			-R tmp/repo-config \
			install -y ${pkg}
		if [ $? -ne 0 ] ; then
			exit_err "Failed installing base packages to ISO directory..."
		fi

	done

	# Copy over the base system packages into the distdir
	for pkg in ${BASE_PACKAGES}
	do
		pkg-static -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
			-R tmp/repo-config \
			fetch -y -d -o ${PKG_DISTDIR} ${pkg}
		if [ $? -ne 0 ] ; then
			exit_err "Failed copying base packages to ISO..."
		fi
	done

	rm tmp/disc1/root/auto-dist-install 2>/dev/null

	# Check if we have dist-packages to include on the ISO
	local _missingpkgs=""
	# Note: Make sure that "prune-dist-packages" is always last in this list!!
	for ptype in dist-packages auto-install-packages optional-dist-packages prune-dist-packages dist-packages-glob
	do
		for c in $(jq -r '."iso"."'${ptype}'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
			for i in $(jq -r '."iso"."'${ptype}'"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
			do
				if [ -z "${i}" ] ; then continue; fi
				if [ "${ptype}" = "prune-dist-packages" ] ; then
					echo "Scanning for packages to prune: ${i}"
					for prune in `ls ${PKG_DISTDIR} | grep -E "${i}"`
					do
						echo "Pruning image dist-file: $prune"
						rm "${PKG_DISTDIR}/${prune}"
					done
				elif [ "${ptype}" = "dist-packages-glob" ] ; then
					echo "Fetching image dist-files for: $i"
					pkg-static -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
						-R tmp/repo-config \
						fetch -y -d -o ${PKG_DISTDIR} -g $i\*
					if [ $? -ne 0 ] ; then
						exit_err "Failed copying dist-package $i to ISO..."
					fi
				else
					echo "Fetching image dist-files for: $i"
					pkg-static -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
						-R tmp/repo-config \
						fetch -y -d -o ${PKG_DISTDIR} $i
					if [ $? -ne 0 ] ; then
						if [ "${ptype}" = "optional-dist-packages" ] ; then
							echo "WARNING: Optional dist package missing: $i"
							_missingpkgs="${_missingpkgs} $i"
						else
							exit_err "Failed copying dist-package $i to ISO..."
						fi
					fi
				fi
			done
			if [ "$ptype" = "auto-install-packages" ] ; then
				echo "Saving package list to auto-install from: $c"
				jq -r '."iso"."auto-install-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST} \
				>>${ISODIR}/root/auto-dist-install
			fi
		done
	done
	if [ -n "${_missingpkgs}" ] ; then
	  echo "WARNING: Optional Packages not available for ISO: ${_missingpkgs}"
	fi

	# Cleanup and move the updated pkgdb
	unset PKG_DBDIR
	mv ${VMDIR}/tmp/pkgdb/* ${VMDIR}/var/db/pkg/
	rmdir ${VMDIR}/tmp/pkgdb

	# Create the repo DB
	echo "Creating installer pkg repo"
	pkg-static repo ${PKG_DISTDIR} ${SIGNING_KEY}
}

create_offline_update()
{
	local NAME="system-update.img"
	if [ -d "release/update" ] ; then
		#Remove old build artifacts
		rm -r "release/update"
	fi
	mkdir -p release/update
	echo "Creating ${NAME}..."
	makefs release/update/${NAME} ${PKG_DISTDIR}
	if [ $? -ne 0 ] ; then
		exit_err "Failed creating system-update.img"
	fi

	if [ -z "${TRUEOS_VERSION}" ] ; then
		TRUEOS_VERSION=$(jq -r '."os_version"' $TRUEOS_MANIFEST)
	fi
	if [ -d "${POUDRIERE_PORTDIR}/.git" ] ; then
		GITHASH=$(git -C ${POUDRIERE_PORTDIR} log -1 --pretty=format:%h)
	else
		GITHASH="unknown"
	fi
	FILE_RENAME="$(jq -r '."iso"."file-name"' $TRUEOS_MANIFEST)"
	if [ -n "$FILE_RENAME" -a "$FILE_RENAME" != "null" ] ; then
		DATE="$(date +%Y%m%d)"
		FILE_RENAME=$(echo $FILE_RENAME | sed "s|%%DATE%%|$DATE|g" | sed "s|%%GITHASH%%|$GITHASH|g" | sed "s|%%TRUEOS_VERSION%%|$TRUEOS_VERSION|g")
		echo "Renaming ${NAME} -> ${FILE_RENAME}.img"
		mv release/update/${NAME} release/update/${FILE_RENAME}.img
		NAME="${FILE_RENAME}.img"
	fi
	sha256 -q release/update/${NAME} > release/update/${NAME}.sha256
	md5 -q release/update/${NAME} > release/update/${NAME}.md5

	if [ $(jq -r '."iso"."generate-update-manifest"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		assemble_file_manifest "release/update"
	fi
}

setup_iso_post() {

	# Check if we have any post install commands to run
	if [ "$(jq -r '."iso"."post-install-commands" | length' ${TRUEOS_MANIFEST})" != "0" ] ; then
		echo "Saving post-install commands"
		jq -r '."iso"."post-install-commands"' ${TRUEOS_MANIFEST} \
			 >${ISODIR}/root/post-install-commands.json
	fi

	# Create the install repo DB config
	mkdir -p ${ISODIR}/etc/pkg
	cat >${ISODIR}/etc/pkg/TrueOS.conf <<EOF
install-repo: {
  url: "file:///install-pkg",
  signature_type: "none",
  enabled: yes
}
EOF
	mkdir -p ${ISODIR}/install-pkg
	mkdir -p ${ISODIR}/usr/home
	mount_nullfs ${POUDRIERE_PKGDIR} ${ISODIR}/install-pkg
	if [ $? -ne 0 ] ; then
		exit_err "Failed mounting nullfs to ${ISODIR}/install-pkg"
	fi
	mount -t devfs devfs ${ISODIR}/dev
	if [ $? -ne 0 ] ; then
		exit_err "Failed mounting devfs to ${ISODIR}/dev"
	fi

	# Prep the new ISO environment
	chroot ${ISODIR} pwd_mkdb /etc/master.passwd
	chroot ${ISODIR} cap_mkdb /etc/login.conf
	touch ${ISODIR}/etc/fstab

	cp ${TRUEOS_MANIFEST} ${ISODIR}/root/trueos-manifest.json
	cp ${TRUEOS_MANIFEST} ${ISODIR}/var/db/trueos-manifest.json

	# If we are using OpenRC, prep the ISO image
	if [ -e "${ISODIR}/sbin/openrc" ] ; then
		echo "Using OpenRC boot method for ISO"
		cp iso-files/openrc ${ISODIR}/etc/rc
		cp iso-files/rc.install ${ISODIR}/etc/

		# Cleanup default runlevels
		rm ${ISODIR}/etc/runlevels/boot/*
		rm ${ISODIR}/etc/runlevels/default/*
		for i in abi ldconfig localmount
		do
			ln -fs /etc/init.d/${i} ${ISODIR}/etc/runlevels/boot/${i}
		done
		for i in local
		do
			ln -fs /etc/init.d/${i} ${ISODIR}/etc/runlevels/default/${i}
		done
	else
		echo "Using rc.d boot method for ISO"
		cp iso-files/rc.install ${ISODIR}/etc/rc.local
	fi

	# Check for conditionals packages to install
	for c in $(jq -r '."iso"."iso-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		for i in $(jq -r '."iso"."iso-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			pkg-static -R /etc/pkg \
				-c ${ISODIR} \
				install -y $i
				if [ $? -ne 0 ] ; then
					exit_err "Failed installing package $i to ISO..."
				fi
		done
	done

	# Cleanup the ISO install packages
	umount -f ${ISODIR}/dev
	umount -f ${ISODIR}/install-pkg
	rmdir ${ISODIR}/install-pkg
	rm ${ISODIR}/etc/pkg/*

	# Create the local repo DB config
	LDIST=$(echo $PKG_DISTDIR | sed "s|$ISODIR||g")
	cat >${ISODIR}/etc/pkg/TrueOS.conf <<EOF
install-repo: {
  url: "file://${LDIST}"
  signature_type: "none",
  enabled: yes
}
EOF

	# Prune specified files
	prune_iso

}

prune_iso()
{
	# Nuke /rescue on image, its huge
	rm -rf "${ISODIR}/rescue"
	rm ${ISODIR}/usr/lib/*.a
	rm ${ISODIR}/usr/local/lib/*.a

	# User-specified pruning
	# Check if we have paths to prune from the ISO before build
	for c in $(jq -r '."iso"."prune" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."iso"."prune"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			echo "Pruning from ISO: ${i}"
			rm -rf "${ISODIR}/${i}"
		done
	done
}

apply_iso_config()
{

	# Check for a custom install script
	_jsins=$(jq -r '."iso"."install-script"' ${TRUEOS_MANIFEST})
	if [ "$_jsins" != "null" -a -n "$_jsins" ] ; then
		echo "Setting custom install script"
		jq -r '."iso"."install-script"' ${TRUEOS_MANIFEST} \
			 >${ISODIR}/etc/trueos-custom-install
	fi

	# Check for auto-install script
	_jsauto=$(jq -r '."iso"."auto-install-script"' ${TRUEOS_MANIFEST})
	if [ "$_jsauto" != "null" -a -n "$_jsauto" ] ; then
		echo "Setting auto install script"
		cp $(jq -r '."iso"."auto-install-script"' ${TRUEOS_MANIFEST}) \
			 ${ISODIR}/etc/installerconfig
	fi

}

mk_iso_file()
{
	if [ -d "release/iso" ] ; then
		rm -rf release/iso
	fi
	mkdir -p release/iso
	NAME="release/iso/install.iso"
	sh scripts/mkisoimages.sh -b INSTALLER ${NAME} ${ISODIR} || exit_err "Unable to create ISO"

	TRUEOS_VERSION=$(jq -r '."os_version"' $TRUEOS_MANIFEST)
	FILE_RENAME="$(jq -r '."iso"."file-name"' $TRUEOS_MANIFEST)"
	if [ -d "${POUDRIERE_PORTDIR}/.git" ] ; then
		GITHASH=$(git -C ${POUDRIERE_PORTDIR} log -1 --pretty=format:%h)
	else
		GITHASH="unknown"
	fi
	if [ -n "$FILE_RENAME" -a "$FILE_RENAME" != "null" ] ; then
		DATE="$(date +%Y%m%d)"
		FILE_RENAME=$(echo $FILE_RENAME | sed "s|%%DATE%%|$DATE|g" | sed "s|%%GITHASH%%|$GITHASH|g" | sed "s|%%TRUEOS_VERSION%%|$TRUEOS_VERSION|g")
		echo "Renaming ${NAME} -> release/iso/${FILE_RENAME}.iso"
		mv ${NAME} release/iso/${FILE_RENAME}.iso
		NAME="${FILE_RENAME}.iso"
	fi
	sha256 -q release/iso/${NAME} > release/iso/${NAME}.sha256
	md5 -q release/iso/${NAME} > release/iso/${NAME}.md5
	sign_file release/iso/${NAME}
	if [ $(jq -r '."iso"."generate-manifest"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		assemble_file_manifest "release/iso"
	fi
}

check_version()
{
	TMVER=$(jq -r '."version"' ${TRUEOS_MANIFEST} 2>/dev/null)
	if [ "$TMVER" != "1.1" ] ; then
		exit_err "Invalid version of MANIFEST specified"
	fi
}

check_build_environment()
{
	for cmd in poudriere jq
	do
		which -s $cmd
		if [ $? -ne 0 ] ; then
			echo "ERROR: Missing \"$cmd\" command. Please install first." >&2
			exit 1
		fi
	done

	cpp --version >/dev/null 2>/dev/null
	if [ $? -ne 0 ] ; then
		echo "Missing compiler! Please install llvm first."
		exit 1
	fi
}

get_os_port_flags()
{
	# Check if we have any port-flags to pass back
	for c in $(jq -r '."ports"."make.conf" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."ports"."make.conf"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			# Skip any non os_ flags
			echo "$i" | grep -q "^os_"
			if [ $? -ne 0 ] ; then
				continue
			fi
			WF="$WF ${i}"
		done
	done
	echo "$WF"
}

get_world_flags()
{
	# Check if we have any world-flags to pass back
	for c in $(jq -r '."base-packages"."world-flags" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."base-packages"."world-flags"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			WF="$WF ${i}"
		done
	done
	arch="$(get_arch)"
	if [ "${arch}" != "native" ]; then
		WF="$WF TARGET_ARCH=${arch}"
		WF="$WF TARGET=$(get_platform)"
	fi
	echo "$WF"
}

get_kernel_flags()
{
	# Check if we have any kernel-flags to pass back
	for c in $(jq -r '."base-packages"."kernel-flags" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."base-packages"."kernel-flags"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			KF="$KF ${i}"
		done
	done
	arch="$(get_arch)"
	if [ "${arch}" != "native" ]; then
		KF="$KF TARGET_ARCH=${arch}"
		KF="$KF TARGET=$(get_platform)"
	fi
	echo "$KF"
}

select_manifest()
{
	# TODO - Replace this with "dialog" time permitting
	echo "Please select a default MANIFEST:"
	COUNT=0
	for i in $(ls manifests/ | grep ".json")
	do
		echo "$COUNT) $i"
		COUNT=$(expr $COUNT + 1)
	done
	echo -e ">\c"
	read tmp
	expr $tmp + 1 >/dev/null 2>/dev/null
	if [ $? -ne 0 ] ; then
		exit_err "Invalid option!"
	fi
	COUNT=0
	for i in $(ls manifests/ | grep ".json")
	do
		if [ $COUNT -eq $tmp ] ; then
			MANIFEST=$i
		fi
		COUNT=$(expr $COUNT + 1)
	done
	if [ -z "$MANIFEST" ] ; then
		exit_err "Invalid option!"
	fi
	if [ ! -d ".config" ] ; then
		mkdir .config
	fi
	echo "$MANIFEST" > .config/manifest
	echo "New Default Manifest: ${MANIFEST}"
}

load_vm_settings() {
	# Load our VM settings
	VMTYPE=$(jq -r '."vm"."type"' ${TRUEOS_MANIFEST} 2>/dev/null)
	VMSIZE=$(jq -r '."vm"."size"' ${TRUEOS_MANIFEST} 2>/dev/null)
	VMCFG=$(jq -r '."vm"."disk-config"' ${TRUEOS_MANIFEST} 2>/dev/null)
	if [ ! -e "vm-diskcfg/${VMCFG}.sh" ] ; then
		exit_err "Missing cfg: vm-diskcfg/${VMCFG}.sh"
	fi
	VMBOOT=$(jq -r '."vm"."boot"' ${TRUEOS_MANIFEST} 2>/dev/null)
	case $VMBOOT in
		ufs) ;;
		zfs) ;;
		*) exit_err "Unknown vm.boot option!" ;;
	esac
}

cleanup_md() {
	if [ ! -e "/dev/${MDDEV}" ] ; then
		return 0
	fi
	if [ "${VMBOOT}" = "zfs" ] ; then
		zpool export ${VMPOOLNAME}
	else
		umount -f $VMDIR
	fi
	mdconfig -d -u ${MDDEV}
}

# Build a VM disk image based upon specifications in JSON manifest
create_vm_disk() {

	truncate -s $VMSIZE vm-dir/vm-disk.img
	if [ $? -ne 0 ] ; then
		exit_err "Failed truncating vm disk image"
	fi

	export MDDEV=$(mdconfig -a -t vnode -f vm-dir/vm-disk.img)
	if [ ! -e "/dev/${MDDEV}" ] ; then
		exit_err "Failed mdconfig of vm-disk.img"
	fi

	trap cleanup_md SIGPIPE
	trap cleanup_md SIGINT
	trap cleanup_md SIGTERM
	trap cleanup_md EXIT

	sh vm-diskcfg/${VMCFG}.sh ${MDDEV} ${VMPOOLNAME}
	if [ $? -ne 0 ] ; then
		cleanup_md
		exit_err "Failed setting up disk for VM image"
	fi
}

clean_vm_dir() {

	if [ -d "release/vm-logs" ] ; then
		rm -rf release/vm-logs
	fi
	mkdir -p release/vm-logs

	if [ -d "vm-dir" ] ; then
		rm -rf vm-dir
	fi
	mkdir -p vm-dir
}

create_vm_dir()
{
	ABI=$(pkg-static -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh config ABI)

	mk_repo_config

	# Check for conditionals packages to install
	for c in $(jq -r '."vm"."vm-base-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		for i in $(jq -r '."iso"."vm-base-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			BASE_PACKAGES="${BASE_PACKAGES} ${i}"
		done
	done

	if [ -z "$BASE_PACKAGES" ] ; then
		# No custom base packages specified, lets roll with the defaults
		BASE_PACKAGES="os/userland os/kernel ports-mgmt/pkg"
	else
		# We always need pkg itself
		BASE_PACKAGES="${BASE_PACKAGES} ports-mgmt/pkg"
	fi

	mkdir -p ${VMDIR}/tmp
	mkdir -p ${VMDIR}/var/db/pkg
	cp -r tmp/repo-config ${VMDIR}/tmp/repo-config

	export PKG_DBDIR="tmp/pkgdb"

	# Install the base packages into vm dir
	for pkg in ${BASE_PACKAGES}
	do
		pkg-static -r ${VMDIR} -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
			-R tmp/repo-config \
			install -y ${pkg}
		if [ $? -ne 0 ] ; then
			exit_err "Failed installing base packages to VM directory..."
		fi

	done

	# Install the packages from JSON manifest
	# - get whether to use the "iso" or "vm" parent object
	local pobj="vm"
	jq -e '."vm"."auto-install-packages"' ${TRUEOS_MANIFEST} 2>/dev/null
	if [ $? -ne 0 ] ; then
		pobj="iso"
	fi
	# - Now loop through the list
	for ptype in auto-install-packages auto-install-packages-glob
	do
		for c in $(jq -r '."'${pobj}'"."'${ptype}'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
			for i in $(jq -r '."'${pobj}'"."'${ptype}'"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
			do
				if [ -z "${i}" ] ; then continue; fi
				echo "Installing: $i"
				pkg-static -r ${VMDIR} -o ABI_FILE=${POUDRIERE_JAILDIR}/bin/sh \
					-R tmp/repo-config \
					install -y ${i}
				if [ $? -ne 0 ] ; then
					exit_err "Failed installing $i to VM..."
				fi
			done
		done
	done
	unset PKG_DBDIR
	mv ${VMDIR}/tmp/pkgdb/* ${VMDIR}/var/db/pkg/
	rmdir ${VMDIR}/tmp/pkgdb
}

run_vm_post_install() {
	# Stamp the boot-loader
	case ${VMBOOT} in
		ufs)
			echo "Stamping UFS boot-loader"
			echo "gpart bootcode -b ${VMDIR}/boot/pmbr -p ${VMDIR}/boot/gptboot -i 1 ${MDDEV}"
			gpart bootcode -b ${VMDIR}/boot/pmbr -p ${VMDIR}/boot/gptboot -i 1 ${MDDEV} || exit_err "failed stamping boot!"
			;;
		zfs) 
			echo "Stamping ZFS boot-loader"
			echo "gpart bootcode -b ${VMDIR}/boot/pmbr -p ${VMDIR}/boot/gptzfsboot -i 1 ${MDDEV}"
			gpart bootcode -b ${VMDIR}/boot/pmbr -p ${VMDIR}/boot/gptzfsboot -i 1 ${MDDEV} || exit_err "failed stamping boot!"
			touch ${VMDIR}/boot/loader.conf
			if [ -e "${VMDIR}/boot/modules/openzfs.ko" ] ; then
				sysrc -f ${VMDIR}/boot/loader.conf openzfs_load=YES
			else
				sysrc -f ${VMDIR}/boot/loader.conf zfs_load=YES
			fi
			;;
	esac

	case ${VMTYPE} in
		ec2)
			run_ec2_setup
			;;
		*)
			echo "vm.type unset, ignoring!"
			;;
	esac

}

run_ec2_setup() {
	# Touch a couple common files first
	touch ${VMDIR}/etc/rc.conf
	touch ${VMDIR}/boot/loader.conf

	# Enable EC2 scripts
	ln -s /usr/local/etc/init.d/ec2_configinit ${VMDIR}/etc/runlevels/default/ec2_configinit
	ln -s /usr/local/etc/init.d/ec2_fetchkey ${VMDIR}/etc/runlevels/default/ec2_fetchkey
	ln -s /usr/local/etc/init.d/ec2_loghostkey ${VMDIR}/etc/runlevels/default/ec2_loghostkey

	# Enable service to grow boot volume
	ln -s /etc/init.d/growzfs ${VMDIR}/etc/runlevels/default/growzfs
	ln -s /etc/init.d/growfs ${VMDIR}/etc/runlevels/default/growfs

	# General EC2 setup
	sysrc -f ${VMDIR}/etc/rc.conf ec2_fetchkey_user=root
	sysrc -f ${VMDIR}/etc/rc.conf ifconfig_DEFAULT=ALL
	sysrc -f ${VMDIR}/etc/rc.conf synchronous_dhclient=YES
	sysrc -f ${VMDIR}/boot/loader.conf if_ena_load=YES
	sysrc -f ${VMDIR}/boot/loader.conf autoboot_delay="-1"
	sysrc -f ${VMDIR}/boot/loader.conf beastie_disable=YES
	sysrc -f ${VMDIR}/boot/loader.conf boot_multicons=YES

	# Disable keyboard / mouse
	echo "hint.atkbd.0.disabled=1" >> ${VMDIR}/boot/loader.conf
	echo "hint.atkbdc.0.disabled=1" >> ${VMDIR}/boot/loader.conf

	# Setup EC2 NTP server
	sed -i '' -e 's/^pool/#pool/' -e 's/^#server.*/server 169.254.169.123 iburst/' ${VMDIR}/etc/ntp.conf
	ln -s /etc/init.d/ntpd ${VMDIR}/etc/runlevels/default/ntpd

	# Disable SSH PAM auth and enable root login
	echo "PasswordAuthentication no" >>${VMDIR}/etc/ssh/sshd_config
	echo "ChallengeResponseAuthentication no" >>${VMDIR}/etc/ssh/sshd_config
	echo "PermitRootLogin yes" >>${VMDIR}/etc/ssh/sshd_config
}

do_vm_create() {
	VMDIR="vm-mnt"

	clean_vm_dir

	load_vm_settings

	echo "Creating vm disk image"
	create_vm_disk

	echo "Installing VM packages"
	create_vm_dir

	echo "Running post-install commands"
	run_vm_post_install

	echo "Packaging disk image"

	# Unmount and cleanup
	cleanup_md

	# Rename and create checksums of files
	NAME="vm-disk.img"
	rm -rf release/vm
	mkdir -p release/vm
	mv vm-dir/${NAME} release/vm/${NAME}
	if [ -d "${POUDRIERE_PORTDIR}/.git" ] ; then
		GITHASH=$(git -C ${POUDRIERE_PORTDIR} log -1 --pretty=format:%h)
	else
		GITHASH="unknown"
	fi
	FILE_RENAME="$(jq -r '."vm"."file-name"' $TRUEOS_MANIFEST)"
	if [ -n "$FILE_RENAME" -a "$FILE_RENAME" != "null" ] ; then
		DATE="$(date +%Y%m%d)"
		FILE_RENAME=$(echo $FILE_RENAME | sed "s|%%DATE%%|$DATE|g" | sed "s|%%GITHASH%%|$GITHASH|g" | sed "s|%%TRUEOS_VERSION%%|$TRUEOS_VERSION|g")
		echo "Renaming ${NAME} -> ${FILE_RENAME}.img"
		mv release/vm/${NAME} release/vm/${FILE_RENAME}.img
		NAME="${FILE_RENAME}.img"
	fi
	echo "Creating checksums"
	sha256 -q release/vm/${NAME} > release/vm/${NAME}.sha256
	md5 -q release/vm/${NAME} > release/vm/${NAME}.md5
	sign_file release/vm/${NAME}
	if [ $(jq -r '."vm"."generate-manifest"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		assemble_file_manifest "release/vm"
	fi
}

do_iso_create() {
	if [ -d "release/iso-logs" ] ; then
		rm -rf release/iso-logs
	fi
	mkdir -p release/iso-logs

	echo "Creating ISO directory"
	create_iso_dir >release/iso-logs/01_iso_dir.log 2>&1
	if [ "$(jq -r '."iso"."offline-update"' ${TRUEOS_MANIFEST})" = "true" ] ; then
		echo "Creating offline update"
		create_offline_update >release/iso-logs/01_offline_update.log 2>&1
	fi
	echo "Preparing ISO directory"
	setup_iso_post >release/iso-logs/02_iso_post.log 2>&1
	apply_iso_config >release/iso-logs/03_iso_config.log 2>&1
	echo "Packaging ISO file"
	mk_iso_file >release/iso-logs/04_mk_iso_fil.log 2>&1
}

# Set a time stamp at start that can be used elsewhere
export BUILD_EPOCH_TIME=$(date '+%s')

for d in tmp release
do
	if [ ! -d "${d}" ] ; then
		mkdir ${d}
		if [ $? -ne 0 ] ; then
			echo "Error creating ${d}"
			exit 1
		fi
	fi
done

if [ "$(id -u )" != "0" ] ; then
	echo "Must be run as root!"
	exit 1
fi

case $1 in
	clean) env_check
	       clean_jails
	       clean_iso_dir
	       clean_vm_dir
	       exit 0
	       ;;
	poudriere) env_check
		   create_release_links
		   run_poudriere
		   ;;
	iso) env_check
	     do_iso_create
	     clean_iso_dir
	     ;;
	 vm) env_check
	     do_vm_create
	     ;;
	check)  env_check
		check_build_environment
		check_version ;;
	config) select_manifest 
		;;
	*) echo "Unknown option selected" ;;
esac

delete_tmp_manifest

exit 0
