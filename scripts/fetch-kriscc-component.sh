#!/usr/bin/env bash
set -euo pipefail

repo="krism-eu/krisCC"
root="${GITHUB_WORKSPACE:-$(pwd)}"
lock="${KRISCC_LOCK_FILE:-$root/build_files/krisCC.lock}"
if [[ "$lock" != /* ]]; then
  lock="$root/$lock"
fi
out="$root/build_files/krisCC"

if [[ ! -f "$lock" ]]; then
  echo "Missing krisCC lock file: $lock" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$lock"
: "${KRISCC_TAG:?KRISCC_TAG missing from lock}"
: "${KRISCC_RPM:?KRISCC_RPM missing from lock}"
: "${KRISCC_SHA256:?KRISCC_SHA256 missing from lock}"

if [[ ! "$KRISCC_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid KRISCC_TAG: $KRISCC_TAG" >&2
  exit 1
fi
if [[ ! "$KRISCC_RPM" =~ ^krisCC-[0-9]+\.[0-9]+\.[0-9]+-1\.fc44\.x86_64\.rpm$ ]]; then
  echo "Invalid KRISCC_RPM: $KRISCC_RPM" >&2
  exit 1
fi
if [[ ! "$KRISCC_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid KRISCC_SHA256" >&2
  exit 1
fi

mkdir -p "$out"
rm -f "$out"/krisCC.rpm "$out"/SHA256SUMS "$out"/RELEASE_TAG "$out"/RELEASE_ASSET "$out"/RELEASE_SHA256

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if command -v gh >/dev/null 2>&1; then
  gh release download "$KRISCC_TAG" --repo "$repo" -p "$KRISCC_RPM" -p SHA256SUMS -D "$tmp"
else
  base="https://github.com/$repo/releases/download/$KRISCC_TAG"
  curl -fL --retry 3 --retry-delay 2 "$base/$KRISCC_RPM" -o "$tmp/$KRISCC_RPM"
  curl -fL --retry 3 --retry-delay 2 "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"
fi

cd "$tmp"
mapfile -t checksum_lines < <(awk -v f="$KRISCC_RPM" '$2 == f || $2 == "./" f {print}' SHA256SUMS)
if [[ ${#checksum_lines[@]} -ne 1 ]]; then
  echo "Expected exactly one checksum entry for $KRISCC_RPM" >&2
  exit 1
fi
if [[ ! "${checksum_lines[0]}" =~ ^([0-9a-f]{64})[[:space:]]+\*?\.?/?${KRISCC_RPM//./\.}$ ]]; then
  echo "Invalid checksum entry for $KRISCC_RPM" >&2
  exit 1
fi
checksum="${BASH_REMATCH[1]}"
printf '%s  %s\n' "$checksum" "$KRISCC_RPM" | sha256sum -c -

if [[ "$checksum" != "$KRISCC_SHA256" ]]; then
  echo "krisCC checksum does not match lock" >&2
  exit 1
fi

rpm_name="$(rpm -qp --qf '%{NAME}' "$KRISCC_RPM")"
rpm_version="$(rpm -qp --qf '%{VERSION}' "$KRISCC_RPM")"
rpm_release="$(rpm -qp --qf '%{RELEASE}' "$KRISCC_RPM")"
[[ "$rpm_name" == "krisCC" ]]
[[ "$rpm_version" == "${KRISCC_TAG#v}" ]]
[[ "$rpm_release" == "1.fc44" ]]

cp "$KRISCC_RPM" "$out/krisCC.rpm"
cp SHA256SUMS "$out/SHA256SUMS"
printf '%s\n' "$KRISCC_TAG" > "$out/RELEASE_TAG"
printf '%s\n' "$KRISCC_RPM" > "$out/RELEASE_ASSET"
printf '%s\n' "$checksum" > "$out/RELEASE_SHA256"
