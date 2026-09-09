# Keep Awake
.PHONY: all build launch pkg clean

all: build

# Compile and install to ~/Applications/KeepAwake.app
build:
	./build.sh

# Build, install locally, and launch
launch:
	./build.sh --launch

# Build KeepAwake-<version>.pkg under dist/
pkg:
	./make-release.sh

clean:
	rm -rf dist /tmp/KeepAwake
