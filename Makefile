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
iso:
	@sh scripts/build.sh iso
vm:
	@sh scripts/build.sh vm
