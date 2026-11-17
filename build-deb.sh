#!/bin/sh
# Build a Debian 13 (trixie) surf package with the surf-touch patches.
# Usage: ./build-deb.sh [arch]      arch: i386 (default) | amd64 | arm64 ...
# Needs Docker. The .deb lands in ./out/.
set -e
ARCH=${1:-i386}
VER=2.1+git20250419
DEBREV=1
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
mkdir -p "$OUT"
case "$ARCH" in
	i386)  IMG=i386/debian:trixie;  PLAT=linux/386 ;;
	amd64) IMG=debian:trixie;       PLAT=linux/amd64 ;;
	arm64) IMG=arm64v8/debian:trixie; PLAT=linux/arm64 ;;
	*)     IMG=debian:trixie;       PLAT=linux/$ARCH ;;
esac
docker run --rm --platform "$PLAT" -v "$HERE":/src:ro -v "$OUT":/out "$IMG" sh -ec "
	export DEBIAN_FRONTEND=noninteractive
	sed -i 's/^Types: deb\$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends build-essential devscripts dpkg-dev >/dev/null
	cd /tmp && apt-get source -qq surf=$VER-$DEBREV >/dev/null
	apt-get build-dep -y -qq surf=$VER-$DEBREV >/dev/null
	cd surf-$VER
	cp /src/patches/*.patch debian/patches/
	printf 'touchbar.patch\nwayland.patch\n' >> debian/patches/series
	dch -v $VER-$DEBREV+touch2 -D trixie 'surf-touch: touchbar + native Wayland (https://github.com/ardyln/surf-touch)'
	dpkg-buildpackage -us -uc -b >/dev/null
	cp ../surf_*+touch2_*.deb /out/
	chown -R $(id -u):$(id -g) /out
"
ls -l "$OUT"/*.deb
