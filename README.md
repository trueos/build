# TrueOS Build

TrueOS Build repo is a JSON manifest-based build system for TrueOS. It uses poudriere, base packages, 'jq' and others in order to create a full package build, as well as ISO and update images.

# Requirements
 - Installed [TrueOS Image](https://pkg.trueos.org/iso/)
 - Installed ports-mgmt/poudriere-trueos package
 - Installed textproc/jq package
 - Configured /usr/local/etc/poudriere.conf (I.E. to setup ZPOOL)

# Build Manifest
TrueOS uses a single JSON configuration file as a "build manifest" containing all the instructions and/or specifications for building the distribution. For details about the build manifests, please refer to the [manifests directory](https://github.com/trueos/build/tree/master/manifests) for information about creating a build manifest as well as example manifest files.

A build manifest can be supplied for the build in a couple of different ways:
1. Set the "TRUEOS_MANIFEST" environment variable to the absolute path to the desired build manifest file.
2. Run `make config` to select from one of the available build manifests in the [manifests directory](https://github.com/trueos/build/tree/master/manifests).
3. Do nothing and automatically use the default build manifest (trueos-snapshot). 
   * NOTE: The trueos-snapshot manifest only builds a tiny subset of packages and is primarily used for testing the build procedures and base OS packages only.

# Usage
Standard commands to build a TrueOS distribution:
```
# make ports
# make iso
```

## All Options

### make clean
This command will clean up files from previous builds. Running this command is typically not required by the user, as the individual cleaning operations are dynamically run as needed during a build procedure so that the current build is not negatively impacted by previous build artifacts.

This command will clean up:

* Poudriere jails, ports trees, and mountpoints.
* ISO output directory : Deleting the output of any "make iso" commands run previously.
* VM output directory : Deleting the output of any "make vm" commands run previously.

### make config
This will launch an interactive prompt to select a build manifest from the example files in the [manifests directory](https://github.com/trueos/build/tree/master/manifests) and use that as the default build manifest.
The selected Manifest name will get saved to the local ".config/manifest" file and used whenever the **TRUEOS_MANIFEST** environment variable is not set. This command may be run whenever a different default manifest is desired.

**WARNING:** If no build manifest is specified (either by running `make config` or providing the TRUEOS_MANIFEST environment variable), then the "trueos-snapshot.json" build manifest will be used automatically from the [manifests directory](https://github.com/trueos/build/tree/master/manifests).

### make ports
Build all of the OS and ports and assemble a package repository.

**Output Directory:** release/packages

**Output Logs:** release/port-logs, release/src-logs

Optional inputs (environment variables):
* **POUDRIERE_BASEFS** : This is the path to the poudriere working directory ("/usr/local/poudriere" by default)
* **SIGNING_KEY** : This is the private key which should be used to sign the packages once they are built.
* **LOCAL_SOURCE_DIR** : Location of any additional source files which need to be copied into the OS source tree (source tree overlay).
   * Default value: "source"

### make iso
Use the package repository to assemble an ISO (hybrid DVD/USB image).

**Note:** For any "*.iso" file that is created, this process will also generate *.sha256 and *.md5 checksum files as well.

**Output Directory:** release/iso

**Output Logs:** release/iso-logs

Optional inputs (environment variables):
* *TO-DO*

### make vm
Use the package repository to assemble a pre-installed VM image.

**Note:** For any "*.img" file that is created, this process will also generate *.sha256 and *.md5 checksum files as well.

**Output Directory:** release/vm

**Output Logs:** release/vm-logs

Optional inputs (environment variables):
* **VMPOOLNAME** : Create/use a temporary ZFS pool with this name for the VM build environment.
   * Default Value: "vm-gen-pool"
 
# License
BSD 2 Clause

----
*This documentation was provided by Ken Moore from the [Project Trident](https://project-trident.org) distribution of TrueOS*
