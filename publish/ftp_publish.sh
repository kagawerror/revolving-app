#!/usr/bin/env bash
# Build a release APK, generate version.json, and upload both to the FTP server.
# Usage:  ./publish/ftp_publish.sh ["release notes shown in the update dialog"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/.ftp.env"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found. Copy publish/.ftp.env.example to publish/.ftp.env and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

for var in FTP_HOST FTP_USER FTP_PASS FTP_REMOTE_DIR HTTPS_BASE_URL; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in $CONFIG" >&2
    exit 1
  fi
done

NOTES="${1:-}"

# Parse "version: X.Y.Z+N" from pubspec.yaml -> name X.Y.Z, code N.
VERSION_LINE="$(grep '^version:' "$ROOT_DIR/pubspec.yaml" | awk '{print $2}')"
VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="${VERSION_LINE##*+}"
if [ "$VERSION_NAME" = "$VERSION_CODE" ]; then
  echo "ERROR: pubspec version '$VERSION_LINE' has no +buildNumber (need X.Y.Z+N)." >&2
  exit 1
fi
echo "Building rev_app $VERSION_NAME (code $VERSION_CODE)..."

# Build release APK with the same env the app expects.
( cd "$ROOT_DIR" && flutter build apk --release --dart-define-from-file=.env )

APK_SRC="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_SRC" ]; then
  echo "ERROR: expected APK not found at $APK_SRC" >&2
  exit 1
fi

# Dash (not '+') between name and build: a literal '+' is valid in a URL path,
# but browsers / chat apps decode it to a space on manual download -> 404. Dash
# is safe everywhere (ota_update and human-shared links alike).
APK_NAME="rev_app-${VERSION_NAME}-${VERSION_CODE}.apk"
APK_URL="${HTTPS_BASE_URL%/}/${APK_NAME}"

# Escape for safe embedding in a JSON string (backslash first, then double-quote).
NOTES_ESCAPED="${NOTES//\\/\\\\}"
NOTES_ESCAPED="${NOTES_ESCAPED//\"/\\\"}"

# Write version.json (manifest the app reads).
MANIFEST="$ROOT_DIR/build/version.json"
cat > "$MANIFEST" <<EOF
{
  "versionCode": ${VERSION_CODE},
  "versionName": "${VERSION_NAME}",
  "apkUrl": "${APK_URL}",
  "notes": "${NOTES_ESCAPED}"
}
EOF

# Upload helper. Uploads to FTP_REMOTE_DIR. Uses explicit FTPS when enabled.
upload() {
  local localfile="$1" remotename="$2"
  local sslflag=""
  if [ "${FTP_USE_FTPS:-true}" = "true" ]; then sslflag="--ssl-reqd"; fi
  curl --fail --ftp-create-dirs $sslflag \
    --user "${FTP_USER}:${FTP_PASS}" \
    -T "$localfile" \
    "ftp://${FTP_HOST}${FTP_REMOTE_DIR%/}/${remotename}"
}

echo "Uploading APK ($APK_NAME)..."
upload "$APK_SRC" "$APK_NAME"

# Upload the manifest LAST so clients never see a manifest pointing at a
# half-uploaded APK.
echo "Uploading version.json..."
upload "$MANIFEST" "version.json"

echo "Done. Manifest -> ${HTTPS_BASE_URL%/}/version.json"
echo "       APK      -> ${APK_URL}"
