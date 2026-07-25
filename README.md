# openvpn-aws — patched OpenVPN for AWS Client VPN SAML federation

Prebuilt, self-contained OpenVPN 2.7.x for macOS (Apple Silicon) with the
buffer patch that AWS Client VPN's SAML/SSO federation requires. Built for
[vpnp](https://github.com/TakiTake/vpnp), usable by anything that speaks
AWS's SAML flow (e.g. scripts in the samm-git/aws-vpn-client style).

```sh
brew install TakiTake/tap/openvpn-aws     # installs the `openvpn-aws` binary
```

No compilation on your machine; OpenSSL is statically linked, so the binary
depends only on `/usr/lib` system libraries. It installs as `openvpn-aws`
and never conflicts with stock openvpn.

## Why this exists

AWS Client VPN's federated auth transports the multi-KB SAML response **as
the OpenVPN password** inside a single TLS control-channel message. Stock
OpenVPN caps that message at 2 KB (`TLS_CHANNEL_BUF_SIZE`) and the password
buffer at 128 B–4 KB (`USER_PASS_LEN`) — compile-time constants, no flags.

Upstream OpenVPN explicitly rejected raising them
([openvpn#295](https://github.com/OpenVPN/openvpn/pull/295)): they consider
AWS's design a vendor hack and point to `AUTH_PENDING`/webauth instead —
which AWS's servers don't speak. Until AWS reworks its protocol, every
open-source client needs this patch. The AWS-official client is itself a
patched OpenVPN fork doing the same thing.

The whole patch is three `#define` bumps: [patches/aws-buffers.patch](patches/aws-buffers.patch)
(`TLS_CHANNEL_BUF_SIZE` → 256 KB, `USER_PASS_LEN` → 128 KB,
`ERR_BUF_SIZE` → 256 KB). Features not needed for AWS Client VPN
(lzo/lz4 compression, pkcs11, the management interface) are disabled.

## How releases work

- `versions.env` pins the OpenVPN version/sha256 and records the OpenSSL
  version last built in.
- A daily [watch-upstream](.github/workflows/watch-upstream.yml) workflow
  opens a bump PR when OpenVPN releases or Homebrew's `openssl@3` moves
  (OpenSSL is statically linked, so security updates warrant a rebuild).
  CI on the PR proves the patch still applies and the build passes.
- Merging and tagging are **deliberately manual** — a VPN binary should
  not auto-release unreviewed. Tag `v<openvpn-version>-<n>` and the
  [release workflow](.github/workflows/release.yml) builds on a GitHub
  macOS arm64 runner and attaches the binary, checksums, and the exact
  patched source tree.

Build locally with `./build.sh` (needs Homebrew `openssl@3` and `pkgconf`).

## License

GPL-2.0 (OpenVPN's license, with its OpenSSL linking exception) — see
[COPYING](COPYING). Each release's corresponding source is attached to it
as `openvpn-aws-<tag>-src.tar.gz` (upstream 2.7.x plus
`patches/aws-buffers.patch`).
