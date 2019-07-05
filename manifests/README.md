# The Manifest File:
--------------

TrueOS includes several manifest files in this directory which may be referenced for examples of usable build manifests.
which can be customized with the following JSON settings:

### version
The JSON manifest has a version control string which must be set. 

This document corresponds to version "1.1", so any manifest using this specification needs to have the following field in the top-level object of the manifest:

`"version" : "1.1"`

### Distribution Branding
There are a couple options which may be set in the manifest in order to "brand" the distribution of TrueOS.

* **os_name** (string) : Branding name for the distribution.
   * Default Value: "TrueOS"
   * Will change the branding in pc-installdialog, and the distro branding in the bootloader as well.
* **os_version** (string) : Custom version tag for the build. 
   * At build time this will become the "TRUEOS_VERSION" environment variable which can be used in filename expansions and such later (if that environment variable is not already set).

### base-packages
The "base-packages" target allows the configuration of the OS packages itself. This can involve the naming scheme, build flags, extra dependencies, and more.


#### Base Packages Options
* **kernel-flags** and **world-flags** (JSON object) : These are objects containing extra builds flags that will be used for the kernel/world build stages. 
   * **default** (JSON array of strings) : Default list of build flags (required if the object is defined)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
   * ***WARNING:*** The only kernel flag that should be optionally set here is the "KERNCONF" setting for selecting a custom kernel configuration. All other world/kernel options are exposed via port options on the "buildworld" and "buildkernel" ports and should be modified in the "ports -> make.conf" section of the manifest.
* **strip-plist** (JSON array of strings) :  List of directories or files that need to be removed from the base-packages.
* **trueos-branch** (string) : Supply a branch name from the trueos/trueos github repository to use for the OS branch.
   * This will ensure that all the base packages use the version of the OS that comes from this branch.
   * If unset, the build will use whichever version of the base packages are currently set in the ports tree.

#### Base Packages Example
```
"base-packages" : {
  "world-flags": {
    "default": [
      "WITH_FOO=1",
      "WITH_BAR=2"
    ],
    "ENV_VARIABLE_FOOBAR": [
      "WITH_FOOBAR=1",
      "WITHOUT_FOOBAR2=1"
    ]
  },
  "kernel-flags": {
    "default": [
      "WITH_FOO=1",
      "WITH_BAR=2"
    ],
    "ENV_VARIABLE_FOOBAR": [
      "WITH_FOOBAR=1",
      "WITHOUT_FOOBAR2=1"
    ]
  },
  "strip-plist":[
	  "/usr/share/examples/pc",
	  "/usr/share/examples/ppp"
  ]
}
```

### iso
The "iso" target within the manifest controls all the options specific to creation/setup of the ISO image. This can involve setting a custom install script, choosing packages which need to be installed or available for installation on the ISO, and more.

#### ISO Options
* **file-name** (string): Template for the generation of the ISO filename. There are a few format options which can be auto-populated:
   * "%%TRUEOS_VERSION%%" : Replace this field with the value of the TRUEOS_VERSION environment variable.
   * "%%GITHASH%%" : (Requires sources to be cloned with git) Replace this field with the hash of the latest git commit.
   * "%%DATE%%" : Replace this field with the date that the ISO was generated (YYYYMMDD)'
* **install-script** (string): Tool to automatically launch when booting the ISO (default: `pc-sysinstaller`)
* **auto-install-script** (string): Path to config file for `pc-sysinstall` to perform an unattended installation.
* **post-install-commands** (JSON array of objects) : Additional commands to run after an installation with pc-sysinstaller (not used for custom install scripts).
   * **chroot** (boolean) : Run command within the newly-installed system (true) or on the ISO itself (false)
   * **command** (string) : Command to run
* **prune** (JSON object) : Lists of files or directories to remove from the ISO
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **dist-packages** (JSON object) : Lists of packages (by port origin) to have available in .txz form on the ISO
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **offline-update** (boolean) : If set to true will generate a system-update.img file containing ISOs dist files
* **generate-manifest** (boolean) : If set to true, will generate a "manifest.json" file containing references or contents of all the files in the ISO output directory.
* **generate-update-manifest** (boolean) : If set to true, will generate a "manifest.json" file containing references or contents of all the files in the offline-update output directory.
* **optional-dist-packages** (JSON object) : Lists of packages (by port origin) to have available in .txz form on the ISO. These ones are considered "optional" and may or may not be included depending on whether the package built successfully.
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **os-flavors** (JSON object)
   * **FLAVOR_NAME** (JSON Object) Name of flavor to allow installation of, description string should be included
* **pool** (JSON object) : Settings for boot pool
 * **name** (string) : Default name of ZFS boot pool
* **prune-dist-packages** (JSON object) : Lists of *regular expressions* to use to find and remove dist packages. This is useful for forcibly removing particular types of base packages.
   * Note: The regular expression support is shell based (grep -E "expression"). Lookahead and look
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **iso-packages** (JSON object) : Lists of packages (by port origin) to install into the ISO (when booting the ISO, these packages will be available to use)
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **auto-install-packages** (JSON object) : Lists of packages (by port origin) to automatically install when using the default TrueOS installer.
   * **NOTE:** These packages will automatically get added to the "dist-packages" available on the ISO as well.
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **overlay** (JSON object) : Overlay files or directories to be inserted into the ISO
   * **type** (string) : One of the following options: [git, svn, tar, local]
   * **branch** (string) : Branch of the repository to fetch (svn/git).
   * **url** (string) : Url to the repository (svn/git), URL to fetch tar file (tar), or path to the directory (local)
* **install-dialog** (JSON object) : Custom options for pc-installdialog (if a custom installer is not desired)
   * **pages** (JSON Array of strings) : List of pages (in order) to show during installation procedure.
      * Available Pages: "os_flavor", "root_pw","create_user", "disk", "pool_name", and "networking"
      * Default Pages: ["os_flavor", "disk", "root_pw", "create_user", "networking"]
   
#### ISO Example
```
"iso" : {
  "file-name": "TrueOS-x64-%%TRUEOS_VERSION%%-%%GITHASH%%-%%DATE%%",
  "install-script" : "/usr/local/bin/my-installer",
  "auto-install-script" : "",
  "post-install-commands": [
      {
        "chroot": true,
        "command": "touch /root/inside-chroot"
      },
      {
        "chroot": false,
        "command": "touch /root/outside-chroot"
      },
      {
        "chroot": true,
        "command": "rm /root/outside-chroot"
      },
      {
        "chroot": false,
        "command": "rm /root/inside-chroot"
      }
  ],
  "os-flavors": {
     "generic": {
        "description":"Default TrueOS world / kernel"
     },
     "minimal":{
        "description":"Minimal world with less optional features."
     },
     "zol":{
        "description":"TrueOS using ZFS on Linux for base file-system."
     }
  },
  "prune": {
    "ENV_VARIABLE": [
      "/usr/share/examples",
      "/usr/include"
    ],
    "default": [
      "/usr/local/share/examples",
      "/usr/local/include"
    ]
  },
  "iso-packages": {
    "default": [
      "sysutils/ipmitool",
      "sysutils/dmidecode",
      "sysutils/tmux"
    ],
    "ENV_VARIABLE": [
      "archivers/cabextract"
    ]
  },
  "dist-packages": {
    "default": [
      "sysutils/ipmitool",
      "sysutils/dmidecode",
      "sysutils/tmux"
    ],
    "ENV_VARIABLE": [
      "archivers/cabextract"
    ]
  },
  "auto-install-packages": {
    "default": [
      "sysutils/ipmitool",
      "sysutils/dmidecode",
      "sysutils/tmux"
    ],
    "ENV_VARIABLE": [
      "archivers/cabextract"
    ]
  },
  "overlay": {
    "type": "git",
    "branch": "master",
    "url": "https://github.com/trueos/iso-overlay"
  }
}
```

### vm
The "vm" target is used to provide custom settings when assembling a VM image with the `make vm` command.

#### VM Options
* **file-name** (string): Template for the generation of the IMG filename. There are a few format options which can be auto-populated:
   * "%%TRUEOS_VERSION%%" : Replace this field with the value of the TRUEOS_VERSION environment variable.
   * "%%GITHASH%%" : (Requires sources to be cloned with git) Replace this field with the hash of the latest git commit.
   * "%%DATE%%" : Replace this field with the date that the image was generated (YYYYMMDD)'
* **type** (string) : Custom type of VM to be used for additional setup procedures
   * "ec2" : Ensure the VM is compatible with the Amazon EC2 specification.
   * All other types are currently valid but do not trigger any custom configuration routines.
* **size** (string) : Truncate the VM image file according to this option.
   * This string is used as an argument to the "truncate -s [size] ...." command. 
   * Please view the manual page for the "truncate" utility for additional information (`man truncate`).
* **disk-config** (string) : Name of the disk configuration script to use from the [vm-diskcfg directory](https://github.com/trueos/build/master/vm-diskconfig).
   * Example: a value of "zfs-noswap" will use the "vm-diskcfg/zfs-noswap.sh" disk configuration script to setup the VM.
* **boot** (string) : Either "zfs" or "ufs". Use this filesystem for the VM image.
* **auto-install-packages** (JSON object) : Lists of packages (by port origin) to automatically install into the VM image.
   * **NOTE:** If this field is missing, it will use the "iso" version of the "auto-install-packages" field as a fallback list.
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name exists.
* **generate-manifest** (boolean) : If set to true, will generate a "manifest.json" file containing references or contents of all the files in the VM output directory.

#### VM Example
```
"vm" : {
  "file-name" : "my-distro-EC2-%%TRUEOS_VERSION%%-%%DATE%%",
  "type" : "ec2",
  "size" : "3G",
  "disk-config" : "zfs-noswap",
  "boot" : "zfs"
}
```

### ports
The "ports" target allows for configuring the build targets and options for the ports system. That can include changing the default version for particular packages, selecting a subset of packages to build, and more.

#### Ports Options
* **type** (string) : One of the following: [git, github-tar, svn, tar, local]. Where to look for the ports tree.
* **branch** (string) : Branch of the repository to use (svn/git only)
* **url** (string) : URL to the repository (svn/git), where to fetch the tar file (tar), or path to directory (local)
* **github-org** (string) : (github-tar type only) Organization to fetch from on GitHub
* **github-repo** (string) : (github-tar type only) Repository to fetch from the GitHub organization
* **github-tag** (string) : (github-tar type only) Either a branch name or a commit tag from the default branch.
   * If a branch name is supplied, then every time the build is run it will check to see if the upstream repo/branch has changed, and update itself as needed
   * If a commit tag is supplied, the it will grab the version of the *default branch* at the designated commit.
* **overlay** (JSON array of objects) : Entries to apply various overlay(s) to the ports tree after it has been checked out.
   * **WARNING** Ports overlay can only be used with the "tar","github-tar", and "local"  ports types.
   * Syntax for objects within the array:
      * "type" : (string) Either "category" (adding a new category to the ports tree) or "port" (adding a single port to the tree)
      * "name" : (string) Category name ("mydistro") or port origin ("devel/myport") depending on the type of overlay.
      * "local_path" : (string) path to the local directory which will be used as the overlay.
* **local_source** (string) : Path to a local directory where the ports tree should be placed (used for reproducible builds). This directory name will be visible in the output of `uname` on installed systems.
* **build-all** (boolean) : Build the entire ports collection (true/false)
* **generate-manifests** (boolean) : Assemble the "pkg-manifests" directory of repo-management files. (true/false)
* **build** (JSON object) : Lists of packages (by port origin) to build. If "build-all" is true, then this list will be treated as "essential" packages and if any of them fail to build properly then the entire build will be flagged as a failure.
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name is set
* **make.conf** (JSON object) : Lists of build flags for use when building the ports.
   * **default** (JSON array of strings) : Default list (required)
   * **ENV_VARIABLE** (JSON array of strings) : Additional list to be added to the "default" list **if** an environment variable with the same name is set
* **strip-plist** (JSON array of strings) : List of files or directories to remove from any packages that try to use them.
* **blacklist** (JSON array of strings) : List of port origins to ignore during the build.

#### Ports Example
```
"ports" : {
  "type" : "git",
  "branch" : "trueos-master",
  "url" : "https://github.com/trueos/trueos-ports",
  "local_source" : "/usr/ports",
  "build-all" : false,
  "generate-manifests" : false,
  "build" : {
    "default" : [
      "sysutils/tmux",
      "shells/zsh",
      "shells/fish"
    ],
    "ENV_VARIABLE" : [
      "shells/bash"
    ]
  },
  "make.conf" : {
    "default" : [
      "shells_zsh_SET=STATIC",
      "shells_zsh_UNSET=EXAMPLES"
    ],
    "ENV_VARIABLE" : [
      "shells_bash_SET=STATIC"
    ]
  },
  "strip-plist":[
	  "/usr/local/share/doc/tmux",
	  "/usr/local/share/examples/tmux"
  ]
}
```

Example of how to use the "github-overlay" type of ports. All the options unrelated to the type are still valid - just not shown in this example.
```
"ports" : {
  "type" : "github-overlay",
  "github-org" : "trueos",
  "github-repo" : "trueos-ports",
  "github-tag" : "trueos-master",
  "github-overlay" : [
    {
      "type" : "category",
      "name" : "mydistro",
      "local_path" : "overlay/mydistro"
    },
    {
      "type" : "port",
      "name" : "devel/myport",
      "local_path" : "overlay/devel/myport"
    }
  ]
}
```

### poudriere
The "poudriere" object allows the configuration of the poudriere build system for individual build manifests, allowing many different builds to be performed on the same system without conflicting with each other.

#### Poudriere Options
* **jailname** (string) : Use this name internally for the jail which is used for the builds.
   * If not provided, the "trueos-mk-base" name will be used.
* **portsname** (string) : Use this name internally for the ports tree used by the build.
   * If not provided, the "trueos-mk-ports" name will be used.

#### Poudriere Example
```
"poudriere" : {
  "jailname" : "my-distro-edge",
  "portsname" : "edge"
}
```

### poudriere-conf
This field contains a list of options to use to configure the poudriere instance that will build the packages. The configuration of poudriere is automatically performed to ensure an optimal result for most build systems, but it is possible to further customize these settings as needed.

#### Poudriere-conf Options
* **poudriere-conf** (JSON array of strings) : List of configuration options for poudriere
* */etc/poudriere.conf.release* - If this file exists on the system, it will be appended as a whole to the auto-generated config.

Common options to configure:

* "NOHANG_TIME=[number]" : Number of seconds a port build can be "silent" before poudriere stops the build.
* "PREPARE_PARALLEL_JOBS=[number]" : Number of CPUs to use when setting up poudriere (typical setting: Number of CPU's - 1)
* "PARALLEL_JOBS=[number]" : Number of ports to build at any given time.
* "ALLOW_MAKE_JOBS=[yes/no]" : Allow ports to build with more than one CPU. 
   * *WARNING:* Make sure to set the "MAKE_JOBS_NUMBER_LIMIT=[number]" in the builds -> make.conf settings to restrict ports to a particular number of CPUs as well.
* USE_TMPFS=[all, yes, wrkdir, data, localbase, no]" : Set how much of the port builds should be performed in memory.

#### Poudriere-conf Example
```
"poudriere-conf": [
	"NOHANG_TIME=14400",
	"PREPARE_PARALLEL_JOBS=15",
	"PARALLEL_JOBS=3",
	"USE_TMPFS='yes'",
	"ALLOW_MAKE_JOBS=yes"
]
```

An example of the automatically-generated config file is included below for reference (if nothing is supplied via the JSON manifest):
```
# Base Poudriere setup for build environment
ZPOOL=${ZPOOL}
FREEBSD_HOST=file://${DIST_DIR}
GIT_URL=${GH_PORTS}
BASEFS=${POUDRIERE_BASEFS}
# Change a couple poudriere defaults to integrate with an automated build
USE_TMPFS=data
ATOMIC_PACKAGE_REPOSITORY=no
PKG_REPO_FROM_HOST=yes
# Optimize the building of known "large" ports (if selected for build)
ALLOW_MAKE_JOBS_PACKAGES="chomium* iridium* gcc* webkit* llvm* clang* firefox* ruby* cmake* rust*"
PRIORITY_BOOST="pypy* openoffice* iridium* chromium*"
```

### pkg-repo
This section determines the default package repository configuration for the installed system.

#### pkg-repo Options
* **pkg-repo-name** (string) : Short-name for the package repository (default: "TrueOS")
* **pkg-train-name** (string) : Name for the package repository train used by sysutils/sysup (default: "TrueOS")
* **pkg-repo** (JSON Object) : Settings for the package repository
   * **url** (string) : Public URL where the repository can be found. (Distro creators will need to setup access for this URL and copy the pkg repo files as needed to make them available at the given location).
   * **pubKey** (JSON Array of strings) : SSL public key to use when verifying integrity of downloaded packages (one line of test per item in the array). This is basically just the plain-text of the SSL public key file converted into an array of strings. 
      * **WARNING** Make sure that this public key is the complement to the private key which is used to sign the packages!!
   
#### pkg-repo Example

```
"pkg-repo-name" : "TrueOS",
"pkg-train-name" : "snapshot",
"pkg-repo" : {
  "url" : "http://pkg.trueos.org/pkg/release/${ABI}/latest",
  "pubKey : [
    "-----BEGIN PUBLIC KEY-----",
    "sdigosbhdgiub+asdgilpubLIUYASVBfiGULiughlBHJljib",
    "-----END PUBLIC KEY-----"
  ]
}
```

---
*This documentation was provided by Ken Moore from the [Project Trident](https://project-trident.org) distribution of TrueOS*
