#############################################################################
# Makefile for building: TrueOS
#############################################################################

all: ports iso

clean:
	sh scripts/build.sh clean
ports:
	sh scripts/build.sh poudriere
iso:
	sh scripts/build.sh iso
