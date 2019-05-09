#!/bin/sh
#===============================
#  Functions for managing the ports tree
#  as part of an overlay system as needed
#===============================
# Written for Project Trident in 2018. 
# Migrated to TrueOS build in March of 2019
# Author: Ken Moore <ken@project-trident.org>
#===============================

# Primary Functions
#---------------------------------------------------
# apply_ports_overlay(ports_tree_path) + TRUEOS_MANIFEST
# checkout_gh_ports(ports_tree_path) + TRUEOS_MANIFEST

# Stand-alone functions used internally
# ---------------------------------------------------
#  validate_portcat_makefile(category_path)
#  validate_port_makefile(port_path, ports_tree_path)
#  register_ports_categories(category_list, ports_tree_path)
#  add_cat_to_ports(cat_name, cat_path, ports_tree_path)
#  add_port_to_ports(port_origin, port_path, ports_tree_path)



validate_portcat_makefile(){
  # Validate a port category makefile
  # This will re-assemble that Makefile to include all valid ports in the directory
  #Inputs:
  # $1 : category directory path

  origdir=`pwd`
  cd "$1"
  comment="`cat Makefile | grep 'COMMENT ='`"
  echo "# \$FreeBSD\$
#

$comment
" > Makefile.tmp

  for d in `ls`
  do
    if [ "$d" = ".." ]; then continue ; fi
    if [ "$d" = "." ]; then continue ; fi
    if [ "$d" = "Makefile" ]; then continue ; fi
    if [ ! -f "$d/Makefile" ]; then continue ; fi
    echo "    SUBDIR += $d" >> Makefile.tmp
  done
  echo "" >> Makefile.tmp
  echo ".include <bsd.port.subdir.mk>" >> Makefile.tmp
  mv Makefile.tmp Makefile
  #always return to the original directory
  cd "${origdir}"
}

validate_port_makefile(){
  # This will add a new category into the top-level makefile of the ports tree
  #Inputs:
  # $1 : makefile directory
  # $2 : local path to ports tree
  local PORTSDIR="$2"
  origdir=`pwd`
  cd "${PORTSDIR}"
  for d in $1
  do
    if [ "$d" = ".." ]; then continue ; fi
    if [ "$d" = "." ]; then continue ; fi
    if [ ! -f "$d/Makefile" ]; then continue ; fi
    grep -q "SUBDIR += ${d}" Makefile
    if [ $? -eq 0 ] ; then continue ; fi
    echo "SUBDIR += $d" >> Makefile.tmp
  done
  #Verify there is actually something to do
  if [ -e "Makefile.tmp" ] ; then
    #Now strip out the subdir info from the original Makefile
    cp Makefile Makefile.skel
    sed -i '' "s|SUBDIR += lang|%%TMP%%|g" Makefile.skel
    echo "SUBDIR += lang" >> Makefile.tmp #make sure we don't remove this cat
    #Insert the new subdir list into the skeleton file and replace the original
    awk '/%%TMP%%/{system("cat Makefile.tmp");next}1' Makefile.skel > Makefile
    #Now cleanup the temporary files
    rm Makefile.tmp Makefile.skel
  fi
  #Always return to the original directory
  cd "${origdir}"
}

register_ports_categories(){
  # This registers new categories as "valid" within bsd.port.mk
  # Inputs:
  # $1 : List of categories separated by spaces ("cat1 cat2 cat3")
  # $2 : local path to ports tree
  echo "[INFO] Registering Categories: ${1}"
  #echo " - Ports Dir: ${2}"
  local PORTSDIR="$2"
  local _conf="${PORTSDIR}/Mk/bsd.port.mk"
  if [ ! -e "${_conf}" ] ; then
    echo "[ERROR] Cannot find ${_conf}!!"
    return 1
  fi
  if [ -e "${_conf}.orig" ] ; then
    #Ports tree not re-extracted between builds - replace the original file and re-register (in case overlay changed)
    mv "${_conf}.orig" "${_conf}"
  fi
  cp "${_conf}" "${_conf}.orig" #save a copy of the original for later builds as needed
  sed -i '' "s|VALID_CATEGORIES+= |VALID_CATEGORIES+= ${1} |g" "${_conf}"
  return $?
}

add_cat_to_ports(){
  # Add a new category to the ports tree
  #Inputs:
  # $1 : category name
  # $2 : local path to dir
  # $3 : local path to ports tree
  local PORTSDIR="$3"

  echo "[INFO] Adding overlay category to ports tree: ${1}"
  #Copy the dir to the ports tree
  if [ -e "${PORTSDIR}/${1}" ] ; then
    rm -rf "${PORTSDIR}/${1}"
  fi
  cp -R "$2" "${PORTSDIR}/${1}"
  #Verify that the Makefile for the new category is accurate
  validate_portcat_makefile "${PORTSDIR}/${1}"
  #Enable the directory in the top-level Makefile
  validate_port_makefile "${1}" "${PORTSDIR}"
}

add_port_to_ports(){
  #Inputs:
  # $1 : port (category/origin)
  # $2 : local path to dir
  # $3 : local path to ports tree
  local PORTSDIR="$3"
  echo "[INFO] Adding overlay port to ports tree: ${1}"
  #Copy the dir to the ports tree
  if [ -e "${PORTSDIR}/${1}" ] ; then
    rm -rf "${PORTSDIR}/${1}"
  fi
  cp -R "$2" "${PORTSDIR}/${1}"
  #Verify that the Makefile for the category includes the port
  validate_portcat_makefile "${PORTSDIR}/${1}/.."
}

apply_ports_overlay(){
  #Inputs:
  # $1 : ports tree path
  # TRUEOS_MANIFEST variable must be set!

  local _ports="$1"

  num=`jq -r '."ports"."overlay" | length' "${TRUEOS_MANIFEST}"`
  if [ "${num}" = "null" ] || [ -z "${num}" ] ; then
    #nothing to do
    return 0
  fi
  i=0
  local _reg_cats=""
  while [ ${i} -lt ${num} ]
  do
    _type=`jq -r '."ports"."overlay"['${i}'].type' "${TRUEOS_MANIFEST}"`
    _name=`jq -r '."ports"."overlay"['${i}'].name' "${TRUEOS_MANIFEST}"`
    _path=`jq -r '."ports"."overlay"['${i}'].local_path' "${TRUEOS_MANIFEST}"`
    if [ ! -e "${_path}" ] ; then
      # See if this is a relative path from the manifest location instead
      local CURDIR=$(dirname "${TRUEOS_MANIFEST}")
      _path="${CURDIR}/${_path}" #try to make it an absolute path
    fi
    if [ -e "${_path}" ] ; then 
      if [ "${_type}" = "category" ] ; then
        add_cat_to_ports "${_name}" "${_path}" "${_ports}"
        _reg_cats="${_reg_cats} ${_name}"
      elif [ "${_type}" = "port" ] ; then
        add_port_to_ports "${_name}" "${_path}" "${_ports}"
      else
        echo "[WARNING] Unknown port overlay type: ${_type} (${_name})"
      fi
    fi
    i=`expr ${i} + 1`
  done
  # Register any new categories as needed
  if [ -n "${_reg_cats}" ] ; then
    register_ports_categories "${_reg_cats}" "${_ports}"
  fi
  return 0
}

check_github_tag(){
  #Inputs: 1: github tag to check
  LC_ALL="C" #Need C locale to get the right lower-case matching
  local _tag="${1}"
  #First do a quick check for non-valid characters in the tag name
  echo "${_tag}" | grep -qE '^[0-9a-z]+$'
  if [ $? -ne 0 ] ; then return 1; fi
  #Now check the length of the tag
  local _length=`echo "${_tag}" | wc -m | tr -d '[:space:]'`
  #echo "[INFO] Checking Github Tag Length: ${_tag} ${_length}"
  if [ ${_length} -eq 41 ] ; then
    #right length for a GitHub commit tag (40 characters + null)
    return 0
  fi
  return 1
}

compare_tar_files(){
  #INPUTS:
  # 1: path to file 1
  # 2: path to file 2
  local oldsha=`sha512 -q "${1}"`
  local newsha=`sha512 -q "${2}"`
  if [ "$oldsha" = "$newsha" ] ; then
    return 0
  fi
  return 1
}

checkout_gh_ports(){
  # Fetch a source tree (base or ports) from GitHub and apply an overlay as needed
  # Note: This fetches the source tree *without* using git - it fetches a tarball instead
  # Inputs:
  # $1 :  Path to directory where the source tree should be placed

  local SRCDIR="${1}"
  local GH_BASE_ORG=`jq -r '."ports"."github-org"' "${TRUEOS_MANIFEST}"`
  local GH_BASE_REPO=`jq -r '."ports"."github-repo"' "${TRUEOS_MANIFEST}"`
  local GH_BASE_TAG=`jq -r '."ports"."github-tag"' "${TRUEOS_MANIFEST}"`
  if [ -z "${GH_BASE_ORG}" ] || [ "null" = "${GH_BASE_ORG}" ] ; then
    return 1
  fi
  echo "[INFO] Check out ports repository"
  #If a branch name was specified
  local GH_BASE_BRANCH="${GH_BASE_TAG}"
  check_github_tag "${GH_BASE_TAG}"
  if [ $? -ne 0 ] && [ -e "/usr/local/bin/git" ] ; then
    # Get the latest commit on this branch and use that as the commit tag (prevents constantly downloading a branch to check checksums)  
    GH_BASE_TAG=`git ls-remote "https://github.com/${GH_BASE_ORG}/${GH_BASE_REPO}" "${GH_BASE_TAG}" | cut -w -f 1`
  fi
  local BASE_CACHE_DIR="/tmp/$(basename -s .json ${TRUEOS_MANIFEST})"
  local BASE_TAR="${BASE_CACHE_DIR}/${GH_BASE_ORG}_${GH_BASE_REPO}_${GH_BASE_TAG}.tgz"
  local _skip=1
  if [ -d "${BASE_CACHE_DIR}" ] ; then
    if [ -e "${BASE_TAR}" ] ; then
      # This tag was previously fetched
      # If a commit tag - just re-use it (nothing changed)
      #  if is it a branch name, need to re-download and check for differences
      check_github_tag "${GH_BASE_TAG}"
      if [ $? -ne 0 ] ; then
        #Got a branch name - need to re-download the tarball to check
        # Note: This is only a fallback for when "git" is not installed on the build server
        #   if git is installed the branch names were turned into tags earlier
        mv "${BASE_TAR}" "${BASE_TAR}.prev"
      else
        #Got a commit tag - skip re-downloading/extracting it
        _skip=0
      fi
    else
      #Got a different tag - clear the old files from the cache
      rm -f ${BASE_CACHE_DIR}/${GH_BASE_ORG}_${GH_BASE_REPO}_*.tgz
    fi
  else
    mkdir -p "${BASE_CACHE_DIR}"
  fi
  local BASE_URL="https://github.com/${GH_BASE_ORG}/${GH_BASE_REPO}/tarball/${GH_BASE_BRANCH}"
  if [ ${_skip} -ne 0 ] ; then
    echo "[INFO] Downloading Repo..."
    fetch --retry -o "${BASE_TAR}" "${BASE_URL}"
    if [ $? -ne 0 ] ; then
      echo "[ERROR] Could not download repository: ${BASE_URL}"
      return 1
    fi
  fi
  # Now that we have the tarball, lets extract it to the base dir
  if [ -e "${BASE_TAR}.prev" ] ; then
    compare_tar_files "${BASE_TAR}" "${BASE_TAR}.prev"
    if [ $? -eq 0 ] ; then
      _skip=0
    fi
    rm "${BASE_TAR}.prev"
  fi
  if [ -d "${SRCDIR}" ] && [ 0 -ne "${_skip}" ] ; then
    # Upstream changed - need to delete and re-checkout repo
    rm -rf "${SRCDIR}"
  fi
  if [ ! -d "${SRCDIR}" ] ; then
    mkdir -p "${SRCDIR}"
    #Note: GitHub archives always have things inside a single subdirectory in the archive (org-repo-tag)
    #  - need to ignore that dir path when extracting
    if [ -e "${BASE_TAR}" ] ; then
      echo "[INFO] Extracting ${1} repo..."
      tar -xf "${BASE_TAR}" -C "${SRCDIR}" --strip-components 1
      echo "[INFO] Done: ${SRCDIR}"
    else
      echo "[ERROR] Could not find source repo tarfile: ${BASE_TAR}"
      return 1
    fi
  else
    echo "[INFO] Re-using existing source tree: ${SRCDIR}"
  fi
  # =====
  # Ports Tree Overlay
  # =====
  apply_ports_overlay "${SRCDIR}"
}
