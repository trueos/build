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
3. Do nothing and automatically use the default build manifest (trueos-snapshot-builder). 
   * NOTE: The trueos-snapshot-builder manifest only builds a tiny subset of packages and is primarily used for testing the build procedures and base OS packages only.

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

### make ports
|Output Files|Output Ports Logs| Output Source Logs | Output Manifests |
|:---:|:---:|:---:|:---:|
|release/packages |release/port-logs | release/src-logs| release/pkg-manifests |

Assemble packages for the OS and any ports listed in the build manifest. These packages will be automatically treated as  a full repository for use as needed.

#### Optional inputs (environment variables):
* **POUDRIERE_BASEFS** : This is the path to the poudriere working directory ("/usr/local/poudriere" by default)
* **SIGNING_KEY** : This is the private key which should be used to sign the packages once they are built.
* **LOCAL_SOURCE_DIR** : Location of any additional source files which need to be copied into the OS source tree (source tree overlay).
   * Default value: "source"

#### Output directory details:
* release/packages (symlink) : Main outputs. Directory structure containing package repository
* release/port-logs (symlink) : Poudriere build logs for each package are contained here.
* release/src-logs (symlink) : Special build logs for the buildworld/buildkernel base packages.
* release/pkg-manifests (optional) : Additional repository management files
   * The "ports" -> "generate-manifests" field must be set to `true` to generate these outputs
   * Manifest files contain:
      * CHANGES : Management file from the version of the ports tree that was used.
      * MOVED : Management file from the version of the ports tree that was used.
      * UPDATING : Management file from the version of the ports tree that was used.
      * pkg.list : Plaintext file containing a list of all packages contained in the repo (one package per line)
         * Line syntax: "[port origin] : [package name] : [package version]")

### make iso
|Output Files|Output Logs|
|:---:|:---:|
|release/iso |release/iso-logs |
|release/update |release/iso-logs/01_offline_update.log |

Use the package repository to assemble an ISO (hybrid DVD/USB image). If the "iso" -> "offline_update" field is set to "true" in the build manifest, the release/update directory will also get created for the offline update image and associated checksums.

**Note:** For any "*.iso" file that is created, this process will also generate *.sha256 and *.md5 checksum files as well.

Optional inputs (environment variables):
* **SIGNING_KEY** : This is the private key which should be used to sign the ISO file once it is built.
   * This will also create a "pubkey.pem" file in the output dir which contains the public key for the signature verification

### make vm
|Output Files|Output Logs|
|:---:|:---:|
|release/vm |release/vm-logs |

Use the package repository to assemble a pre-installed VM image.

**Note:** For any "*.img" file that is created, this process will also generate *.sha256 and *.md5 checksum files as well.

Optional inputs (environment variables):
* **SIGNING_KEY** : This is the private key which should be used to sign the IMG file once it is built.
   * This will also create a "pubkey.pem" file in the output dir which contains the public key for the signature verification
* **VMPOOLNAME** : Create/use a temporary ZFS pool with this name for the VM build environment.
   * Default Value: "vm-gen-pool"
 
# License
BSD 2 Clause

----
*This documentation was provided by Ken Moore from the [Project Trident](https://project-trident.org) distribution of TrueOS*
