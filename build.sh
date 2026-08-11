#!/bin/bash
# Build the AWS-buffer-patched OpenVPN as a self-contained macOS arm64
# binary (OpenSSL statically linked; only /usr/lib system dylibs remain).
#
# Usage: ./build.sh [output-dir]   (default: ./dist)
# Reads OPENVPN_VERSION / OPENVPN_SHA256 from versions.env.
set -euo pipefail

cd "$(dirname "$0")"
source ./versions.env
OUT="${1:-dist}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TARBALL="openvpn-${OPENVPN_VERSION}.tar.gz"
echo "==> Downloading OpenVPN ${OPENVPN_VERSION}"
curl -fsSL "https://swupdate.openvpn.org/community/releases/${TARBALL}" -o "$WORK/$TARBALL"
echo "${OPENVPN_SHA256}  $WORK/$TARBALL" | shasum -a 256 -c -

echo "==> Extracting and patching"
tar -xzf "$WORK/$TARBALL" -C "$WORK"
SRC="$WORK/openvpn-${OPENVPN_VERSION}"
patch -d "$SRC" -p1 <patches/aws-buffers.patch

echo "==> Building (static OpenSSL, no lzo/lz4/management/pkcs11)"
OPENSSL_PREFIX="$(brew --prefix openssl@3)"
export OPENSSL_CFLAGS="-I${OPENSSL_PREFIX}/include"
export OPENSSL_LIBS="${OPENSSL_PREFIX}/lib/libssl.a ${OPENSSL_PREFIX}/lib/libcrypto.a"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
(cd "$SRC" && ./configure --disable-debug --disable-silent-rules \
    --with-crypto-library=openssl \
    --disable-lzo --disable-lz4 --disable-management >configure.log 2>&1) \
  || { tail -30 "$SRC/configure.log"; exit 1; }
make -C "$SRC" -j"$(sysctl -n hw.ncpu)" >"$SRC/make.log" 2>&1 \
  || { tail -30 "$SRC/make.log"; exit 1; }
BIN="$SRC/src/openvpn/openvpn"

echo "==> Verifying"
"$BIN" --version | head -1
if otool -L "$BIN" | tail -n +2 | grep -v '/usr/lib/'; then
  echo "ERROR: binary links non-system libraries (above)" >&2
  exit 1
fi
"$BIN" --show-ciphers | grep -q AES-256-GCM

echo "==> Packaging"
OPENSSL_VERSION="$(brew list --versions openssl@3 | awk '{print $2}' | cut -d_ -f1)"
TAG="${TAG:-v${OPENVPN_VERSION}-0}"
mkdir -p "$OUT"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp "$BIN" "$STAGE/openvpn-aws"
cp COPYING patches/aws-buffers.patch "$STAGE/"
tar -czf "$OUT/openvpn-aws-${TAG}-aarch64-apple-darwin.tar.gz" -C "$STAGE" .
# GPLv2 corresponding source: the exact patched tree we compiled.
make -C "$SRC" distclean >/dev/null 2>&1 || true
tar -czf "$OUT/openvpn-aws-${TAG}-src.tar.gz" -C "$WORK" "openvpn-${OPENVPN_VERSION}"
echo "built with OpenSSL ${OPENSSL_VERSION}" >"$OUT/BUILDINFO"
(
  cd "$OUT"
  # One .sha256 per asset, published with the release so downloads can be
  # checked against a repo-published sum (transfer integrity, not authenticity).
  # Format matches pall8t: hash, two spaces, basename.
  for f in openvpn-aws-*.tar.gz; do
    shasum -a 256 "$f" >"$f.sha256"
  done
  cat openvpn-aws-*.tar.gz.sha256 | tee SHA256SUMS
)
