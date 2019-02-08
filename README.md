# TrueOS Build

TrueOS Build repo is a JSON manifest-based build system for TrueOS. It uses poudriere, base packages, 'jq' and others in order to create a full package build, as well as ISO and update images.

# Requirements
 - Installed [TrueOS Image](https://pkg.trueos.org/iso/)
 - Installed ports-mgmt/poudriere-trueos package
 - Installed textproc/jq package
 - Configured /usr/local/etc/poudriere.conf (I.E. to setup ZPOOL)

# Usage

```
# make ports
# make iso
```

License
----

BSD 2 Clause
