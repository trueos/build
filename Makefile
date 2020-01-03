#############################################################################
# Makefile for building: TrueOS
#############################################################################

all: ports iso

clean:
	@sh scripts/build.sh clean
config:
	@sh scripts/build.sh config
ports:
	@sh scripts/build.sh poudriere
pullpkgs:
	@sh scripts/build.sh pullpkgs
pushpkgs:
	@sh scripts/build.sh pushpkgs
iso:
	@sh scripts/build.sh iso
image:
	@sh scripts/build.sh image
