#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/release"
SIDESTORE_IPA=0
PHYSICAL_REPORT=""
ALLOW_UNVALIDATED_IPA=0

usage() {
  cat <<'EOF'
Usage: scripts/build-ios-release.sh [options]

Build a device Release archive and package the Studio bridge source.
An unsigned SideStore IPA is created only when both --sidestore-ipa and a
matching physical-device validation report are supplied, or the maintainer
explicitly selects --allow-unvalidated-ipa for unsigned packaging only.
This script never installs on a device.

Options:
  --output-dir PATH                  Output directory (default: build/release)
  --sidestore-ipa                    Create the unsigned IPA for SideStore to sign
  --physical-validation-report PATH  Report with PASS and validation_bundle_identifier
  --allow-unvalidated-ipa            Package unsigned without physical validation
  -h, --help                         Show this help
EOF
}

while (($#)); do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --output-dir" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --sidestore-ipa)
      SIDESTORE_IPA=1
      shift
      ;;
    --allow-unvalidated-ipa)
      ALLOW_UNVALIDATED_IPA=1
      shift
      ;;
    --physical-validation-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --physical-validation-report" >&2; exit 2; }
      PHYSICAL_REPORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ((ALLOW_UNVALIDATED_IPA)) && { (( ! SIDESTORE_IPA )) || [[ -n "$PHYSICAL_REPORT" ]]; }; then
  echo "--allow-unvalidated-ipa requires --sidestore-ipa and excludes a physical report." >&2
  exit 2
fi
if ((SIDESTORE_IPA && ! ALLOW_UNVALIDATED_IPA)); then
  if [[ -z "$PHYSICAL_REPORT" || ! -f "$PHYSICAL_REPORT" ]]; then
    echo "SideStore IPA creation requires --physical-validation-report PATH." >&2
    exit 2
  fi
  if ! /usr/bin/grep -Eq '^physical_device_validation:[[:space:]]*PASS[[:space:]]*$' "$PHYSICAL_REPORT"; then
    echo "The report must contain the exact line: physical_device_validation: PASS" >&2
    exit 2
  fi
  if ! /usr/bin/grep -Fxq 'validation_bundle_identifier: xyz.majorminor.talaria' "$PHYSICAL_REPORT"; then
    echo "Physical PASS must explicitly cover validation_bundle_identifier: xyz.majorminor.talaria." >&2
    exit 2
  fi
fi

for command in xcodebuild git python3 shasum unzip zip; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
if [[ "$OUTPUT_DIR" == "/" || "$OUTPUT_DIR" == "$ROOT" ]]; then
  echo "Choose a dedicated output directory, not the filesystem or repository root." >&2
  exit 2
fi
VERSION="$(/usr/bin/sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/hermes-mobile-bridge/pyproject.toml" | /usr/bin/head -n 1)"
[[ -n "$VERSION" ]] || { echo "Missing release version." >&2; exit 1; }
ARCHIVE_PATH="$OUTPUT_DIR/Talaria-v$VERSION.xcarchive"
DERIVED_DATA="$(/usr/bin/mktemp -d "/tmp/talaria-release-derived.XXXXXX")"
IPA_STAGING=""
trap 'rm -rf "$DERIVED_DATA"; [[ -z "$IPA_STAGING" ]] || rm -rf "$IPA_STAGING"' EXIT

if [[ -L "$ARCHIVE_PATH" || -e "$ARCHIVE_PATH" ]]; then
  echo "Refusing to replace an existing archive: $ARCHIVE_PATH" >&2
  echo "Choose another --output-dir or remove the previous generated archive after inspection." >&2
  exit 1
fi
"$ROOT/scripts/package-bridge.sh" --output-dir "$OUTPUT_DIR"

echo "Building unsigned iOS Release archive (bundle ID is checked after build)."
xcodebuild \
  -project "$ROOT/Hermes.xcodeproj" \
  -scheme Hermes \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_IDENTITY= \
  SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  "OTHER_SWIFT_FLAGS=\$(inherited) -file-compilation-dir . -prefix-serialized-debugging-options -debug-prefix-map $ROOT=. -file-prefix-map $ROOT=. -debug-prefix-map $DERIVED_DATA=.build -file-prefix-map $DERIVED_DATA=.build -debug-prefix-map $HOME=.home -file-prefix-map $HOME=.home" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/Hermes.app"
INFO_PLIST="$APP_PATH/Info.plist"
[[ -d "$APP_PATH" && -f "$INFO_PLIST" ]] || {
  echo "The iOS archive does not contain Hermes.app." >&2
  exit 1
}

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$BUNDLE_ID" != "xyz.majorminor.talaria" ]]; then
  echo "Unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 1
fi

MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ "$MARKETING_VERSION" == "$VERSION" && "$BUILD_NUMBER" == "1" ]] || { echo "App/bridge release version mismatch." >&2; exit 1; }

IPA_PATH=""
if ((SIDESTORE_IPA)); then
  IPA_STAGING="$(/usr/bin/mktemp -d "$OUTPUT_DIR/.sidestore-payload.XXXXXX")"
  mkdir -p "$IPA_STAGING/Payload"
  /usr/bin/ditto "$APP_PATH" "$IPA_STAGING/Payload/Hermes.app"

  # SideStore applies the device's signing identity during installation.
  /usr/bin/find "$IPA_STAGING/Payload/Hermes.app" -type d -name _CodeSignature -prune -exec rm -rf {} +
  /usr/bin/find "$IPA_STAGING/Payload/Hermes.app" -type f -name embedded.mobileprovision -delete
  IPA_PATH="$OUTPUT_DIR/Talaria-v$VERSION.ipa"
  if [[ -L "$IPA_PATH" ]]; then
    echo "Refusing to replace a symlink at $IPA_PATH" >&2
    exit 1
  fi
  rm -f "$IPA_PATH"
  (cd "$IPA_STAGING" && /usr/bin/zip -qry "$IPA_PATH" Payload)
  rm -rf "$IPA_STAGING"
  IPA_STAGING=""

  if /usr/bin/unzip -Z1 "$IPA_PATH" | /usr/bin/grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision)(/|$)'; then
    echo "Unsigned SideStore package still contains signing material." >&2
    rm -f "$IPA_PATH"
    exit 1
  fi
  /usr/bin/unzip -Z1 "$IPA_PATH" | /usr/bin/grep -qx 'Payload/Hermes.app/Info.plist' || {
    echo "Talaria IPA has an invalid Payload/Hermes.app layout." >&2
    rm -f "$IPA_PATH"
    exit 1
  }
fi

# A historical legacy-ID PASS must not be represented as validation of this IPA.
export TALARIA_RELEASE_OUTPUT="$OUTPUT_DIR"
export TALARIA_RELEASE_ROOT="$ROOT"
export TALARIA_DEVICE_VALIDATED="$((SIDESTORE_IPA && ! ALLOW_UNVALIDATED_IPA))"
python3 - <<'PYMETA'
import json, os, pathlib, hashlib, subprocess
# Record only public build inputs; never local signing files or absolute source paths.
root = pathlib.Path(os.environ['TALARIA_RELEASE_ROOT'])
tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
inputs = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in tracked
          if name and (name.startswith(('Hermes/', 'Hermes.xcodeproj/', 'Config/')) or name == 'scripts/build-ios-release.sh')}
metadata = {'product': 'Talaria', 'publisher': 'MAJOR//MINOR', 'version': '0.1.0', 'build': '1',
            'bundle_identifier': 'xyz.majorminor.talaria', 'signing': 'unsigned',
            'physical_device_validation': 'PASS' if os.environ['TALARIA_DEVICE_VALIDATED'] == '1' else 'NOT_PERFORMED',
            'source_input_sha256': inputs}
(pathlib.Path(os.environ['TALARIA_RELEASE_OUTPUT'])/'BUILD_METADATA.json').write_text(json.dumps(metadata, indent=2)+'\n')
PYMETA

SUMS="$OUTPUT_DIR/SHA256SUMS.txt"
: > "$SUMS"
for artifact in "$OUTPUT_DIR"/hermes-mobile-bridge-v*.tar.gz; do
  [[ -f "$artifact" ]] || continue
  (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$artifact")") >> "$SUMS"
done
if [[ -n "$IPA_PATH" ]]; then
  (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$IPA_PATH")") >> "$SUMS"
fi

(cd "$OUTPUT_DIR" && shasum -a 256 -c "$(basename "$SUMS")")

echo "Release archive: $ARCHIVE_PATH"
BRIDGE_ARCHIVE="$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'hermes-mobile-bridge-v*.tar.gz' -print -quit)"
echo "Bridge archive: ${BRIDGE_ARCHIVE:-$OUTPUT_DIR (not found)}"
echo "Checksums: $SUMS"
if [[ -n "$IPA_PATH" ]]; then
  echo "SideStore IPA: $IPA_PATH"
else
  echo "No IPA created. Use a matching physical PASS report or explicit --allow-unvalidated-ipa for unsigned packaging."
fi
