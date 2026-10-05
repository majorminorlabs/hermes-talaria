#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/release"

usage() {
  cat <<'EOF'
Usage: scripts/package-bridge.sh [--output-dir PATH]

Create a clean source archive of the tracked Studio bridge runtime, contracts,
launchd configuration, and bridge install/update scripts. No virtualenv,
machine configuration, credentials, logs, databases, or build products are
included.
EOF
}

while (($#)); do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --output-dir" >&2; exit 2; }
      OUTPUT_DIR="$2"
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

command -v git >/dev/null 2>&1 || { echo "git is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required." >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
VERSION="$(/usr/bin/sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/hermes-mobile-bridge/pyproject.toml" | /usr/bin/head -n 1)"
[[ -n "$VERSION" ]] || { echo "Could not read bridge version." >&2; exit 1; }

ARCHIVE="$OUTPUT_DIR/hermes-mobile-bridge-v$VERSION.tar.gz"
export HERMES_PACKAGE_ROOT="$ROOT"
export HERMES_PACKAGE_ARCHIVE="$ARCHIVE"

python3 - <<'PY'
import os
import gzip
import pathlib
import subprocess
import tarfile

root = pathlib.Path(os.environ["HERMES_PACKAGE_ROOT"]).resolve()
archive = pathlib.Path(os.path.abspath(os.environ["HERMES_PACKAGE_ARCHIVE"]))
if archive.is_symlink() or archive.with_name(archive.name + ".sha256").is_symlink():
    raise SystemExit("Refusing to replace a symlink at the release artifact path.")
temporary = archive.with_name(f".{archive.name}.{os.getpid()}.tmp")
checksum = archive.with_name(archive.name + ".sha256")
checksum_temporary = checksum.with_name(f".{checksum.name}.{os.getpid()}.tmp")
if temporary.exists() or temporary.is_symlink() or checksum_temporary.exists() or checksum_temporary.is_symlink():
    raise SystemExit("A temporary bridge release artifact already exists; remove it after inspection.")
raw = subprocess.run(
    ["git", "-C", str(root), "ls-files", "--cached", "-z"],
    check=True,
    stdout=subprocess.PIPE,
).stdout
tracked = [path.decode("utf-8") for path in raw.split(b"\0") if path]

runtime_roots = ("hermes-mobile-bridge/src/", "third_party/licenses/")
runtime_files = {
    "hermes-mobile-bridge/README.md",
    "hermes-mobile-bridge/LICENSE",
    "hermes-mobile-bridge/config.example.json",
    "hermes-mobile-bridge/pyproject.toml",
}
contract_files = {
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "BRIDGE_API.md",
    "BRIDGE_HERMES_MAPPING.md",
    "IOS_INTEGRATION_GUIDE.md",
    "docs/INSTALL.md",
    "docs/BRIDGE_PACKAGE.md",
    "docs/USING_TALARIA.md",
    "docs/SIDESTORE.md",
    "docs/TROUBLESHOOTING.md",
    "docs/RESEARCH_TERMINAL_SETUP.md",
    "docs/STUDIO_SETUP.md",
}
# Include the public documentation closure, including the SideStore patch and
# validation it links to. Only tracked public files enter this package.
contract_files |= {
    name for name in tracked
    if ("/" not in name and name.endswith(".md") and name != "README.md") or name.startswith("docs/")
}

service_files = {
    "scripts/bridge-service.py",
    "scripts/studio-runtime.py",
    "scripts/install-bridge.sh",
    "scripts/start-bridge.sh",
    "scripts/stop-bridge.sh",
    "scripts/status-bridge.sh",
    "scripts/update-bridge.sh",
    "scripts/uninstall-bridge.sh",
    "scripts/pairing-token.sh",
    "scripts/configure-tailscale.sh",
}

def selected(name: str) -> bool:
    return (
        name in runtime_files
        or name in contract_files
        or name in service_files
        or name.startswith(runtime_roots)
        or (name.startswith("launchd/") and name.endswith(".plist"))
    )

def forbidden(name: str) -> bool:
    path = pathlib.PurePosixPath(name)
    blocked_parts = {".git", ".venv", "__pycache__", ".pytest_cache", "build", "dist", "node_modules", ".tox"}
    if any(part in blocked_parts for part in path.parts):
        return True
    lowered = path.name.lower()
    if lowered in {"config.json", "credentials.json", "secrets.json", "token", "token.txt"}:
        return True
    if lowered.startswith(".env") or lowered.endswith((".log", ".sqlite", ".sqlite3", ".db", ".pem", ".key", ".p12", ".cer", ".mobileprovision", ".provisionprofile")):
        return True
    return False

members = []
for name in tracked:
    if not selected(name):
        continue
    if forbidden(name):
        raise SystemExit(f"Refusing to package sensitive or generated path: {name}")
    source = (root / name)
    if source.is_symlink():
        raise SystemExit(f"Refusing symlink in bridge archive: {name}")
    if not source.is_file():
        # A tracked but locally removed file must not silently yield an incomplete package.
        raise SystemExit(f"Tracked bridge release file is missing: {name}")
    members.append((name, source))

required = runtime_files | contract_files | service_files
missing = sorted(required - {name for name, _ in members})
if missing:
    raise SystemExit("Required bridge release files are not tracked: " + ", ".join(missing))
if not any(name.startswith("launchd/") and name.endswith(".plist") for name, _ in members):
    raise SystemExit("No tracked launchd plist was found for the Studio bridge service.")

try:
    # Stable gzip/tar metadata also prevents disclosing the packaging user's name.
    with temporary.open("xb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as output:
                for name, source in sorted(members):
                    package_name = "README.md" if name == "docs/BRIDGE_PACKAGE.md" else name
                    info = output.gettarinfo(str(source), arcname=f"hermes-mobile-bridge-release/{package_name}")
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    info.mode = 0o755 if source.stat().st_mode & 0o111 else 0o644
                    info.pax_headers = {}
                    if name == "docs/BRIDGE_PACKAGE.md":
                        import io
                        readme = source.read_bytes()
                        for guide in ("INSTALL", "STUDIO_SETUP", "USING_TALARIA", "SIDESTORE", "TROUBLESHOOTING"):
                            readme = readme.replace(f"]({guide}.md)".encode(), f"](docs/{guide}.md)".encode())
                        readme = readme.replace(b"](../LICENSE)", b"](LICENSE)")
                        readme = readme.replace(b"](../THIRD_PARTY_NOTICES.md)", b"](THIRD_PARTY_NOTICES.md)")
                        info.size = len(readme)
                        output.addfile(info, io.BytesIO(readme))
                        info.name = f"hermes-mobile-bridge-release/{name}"
                        info.size = source.stat().st_size
                    with source.open("rb") as contents:
                        output.addfile(info, contents)
    os.replace(temporary, archive)
finally:
    temporary.unlink(missing_ok=True)

print(f"Packaged {len(members)} tracked source and service files.")
PY

if [[ -L "$ARCHIVE.sha256" ]]; then
  echo "Refusing to replace a symlink at $ARCHIVE.sha256" >&2
  exit 1
fi
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE")") > "$ARCHIVE.sha256"
echo "Bridge package: $ARCHIVE"
echo "Checksum: $ARCHIVE.sha256"
