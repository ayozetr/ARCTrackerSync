#!/usr/bin/env bash
# Build the Linux packages.
#
# The binary is compiled inside Debian 12 rather than on the build host: a
# dynamically linked Rust binary requires whatever glibc it was built against,
# and building on a current rolling distro produces something that refuses to
# start anywhere older ("version GLIBC_2.4x not found"). Debian 12 ships glibc
# 2.36, which covers Debian 12+, Ubuntu 22.04+ and current Fedora.
#
# Usage: packaging/build.sh [deb|rpm|all]   (default: all)
set -euo pipefail

cd "$(dirname "$0")/.."

TARGETS="${1:-all}"
BUILD_IMAGE="rust:1-slim-bookworm"
OUT_DIR="packaging/out"
VERSION="$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)"
ARCH_DEB="amd64"
ARCH_RPM="x86_64"

if command -v podman >/dev/null 2>&1; then
    CONTAINER=podman
elif command -v docker >/dev/null 2>&1; then
    CONTAINER=docker
else
    echo "error: needs podman or docker to build against an older glibc" >&2
    exit 1
fi

echo "==> Building arctracker-sync $VERSION in $BUILD_IMAGE"
mkdir -p "$OUT_DIR"
# CARGO_TARGET_DIR is kept out of ./target so a container-built binary never
# gets confused with a local `cargo build` one — they are not interchangeable.
"$CONTAINER" run --rm \
    --user "$(id -u):$(id -g)" \
    -e CARGO_HOME=/tmp/cargo \
    -e CARGO_TARGET_DIR=/src/packaging/out/target \
    -v "$PWD":/src \
    -w /src \
    "$BUILD_IMAGE" \
    cargo build --release --locked

BINARY="$OUT_DIR/target/release/arctracker-sync"
if [[ ! -x "$BINARY" ]]; then
    echo "error: build produced no binary at $BINARY" >&2
    exit 1
fi

echo "==> Oldest glibc this binary will run against:"
objdump -T "$BINARY" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 || true

stage_common() {
    local root="$1"
    install -Dm755 "$BINARY" "$root/usr/bin/arctracker-sync"
    install -Dm644 packaging/arctracker-sync.desktop \
        "$root/usr/share/applications/arctracker-sync.desktop"
    install -Dm644 assets/arc-mark.png \
        "$root/usr/share/icons/hicolor/256x256/apps/arctracker-sync.png"
    install -Dm644 LICENSE "$root/usr/share/doc/arctracker-sync/LICENSE"
    install -Dm644 packaging/README.md "$root/usr/share/doc/arctracker-sync/README.md"
}

build_deb() {
    echo "==> Building .deb"
    local root="$OUT_DIR/deb-root"
    rm -rf "$root"
    stage_common "$root"

    install -Dm644 packaging/deb/control "$root/DEBIAN/control"
    sed -i "s/@VERSION@/$VERSION/; s/@ARCH@/$ARCH_DEB/" "$root/DEBIAN/control"
    install -Dm755 packaging/deb/postinst "$root/DEBIAN/postinst"
    install -Dm755 packaging/deb/postrm "$root/DEBIAN/postrm"

    local out="$OUT_DIR/arctracker-sync_${VERSION}_${ARCH_DEB}.deb"
    # Built in the container too: dpkg-deb is not necessarily installed on the
    # host, and this keeps the toolchain identical to the binary's.
    "$CONTAINER" run --rm --user "$(id -u):$(id -g)" \
        -v "$PWD":/src -w /src "$BUILD_IMAGE" \
        bash -c "dpkg-deb --build --root-owner-group '$root' '$out'" >/dev/null
    echo "    $out"
}

build_rpm() {
    echo "==> Building .rpm"
    local spec="packaging/rpm/arctracker-sync.spec"
    local root
    root="$(mktemp -d)"
    stage_common "$root"

    # rpm is packaged for Debian, so the same container can emit both formats.
    "$CONTAINER" run --rm --user "$(id -u):$(id -g)" \
        -v "$PWD":/src -v "$root":/stage -w /src "$BUILD_IMAGE" \
        bash -c "
            set -e
            command -v rpmbuild >/dev/null || { echo 'error: rpmbuild missing from the image; run: apt-get install -y rpm' >&2; exit 1; }
            rpmbuild -bb '$spec' \
                --define '_topdir /tmp/rpmbuild' \
                --define '_rpmdir /src/$OUT_DIR' \
                --define 'version $VERSION' \
                --buildroot /stage
        " || {
        echo "    skipped: the build image has no rpmbuild (see packaging/README.md)" >&2
        rm -rf "$root"
        return 0
    }
    rm -rf "$root"
}

case "$TARGETS" in
deb) build_deb ;;
rpm) build_rpm ;;
all)
    build_deb
    build_rpm
    ;;
*)
    echo "usage: $0 [deb|rpm|all]" >&2
    exit 1
    ;;
esac

echo "==> Done. Packages in $OUT_DIR/"
