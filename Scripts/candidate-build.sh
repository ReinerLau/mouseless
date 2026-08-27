#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT="$REPO_ROOT/Mouseless.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/build/candidate}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Mouseless.app"
MANIFEST_PATH="${MANIFEST_PATH:-$DERIVED_DATA_PATH/candidate-manifest.txt}"
EXPECTED_IDENTIFIER="com.reinerlau.mouseless"
EXPECTED_IDENTITY="Mouseless Local Development"

command -v swift >/dev/null || { echo "swift is required; install Xcode first." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen is required; install it before building Mouseless." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild is required; install Xcode first." >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign is required; install Xcode first." >&2; exit 1; }

if [[ "$CONFIGURATION" != "Release" ]]; then
  echo "Candidate builds must use CONFIGURATION=Release (got $CONFIGURATION)." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$EXPECTED_IDENTITY\""; then
  echo "The local signing identity is unavailable: $EXPECTED_IDENTITY" >&2
  exit 1
fi

echo "Running the deterministic runtime test suite..."
swift test --package-path "$REPO_ROOT"

echo "Generating the Xcode project from project.yml..."
xcodegen generate --spec "$REPO_ROOT/project.yml" --project "$REPO_ROOT"

echo "Running the generated Xcode test scheme..."
xcodebuild \
  -project "$PROJECT" \
  -scheme Mouseless \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test

CALLBACK_SOURCE=$(sed -n '/private func handleTapEvent/,/private func runtimeResponse/p' "$REPO_ROOT/Sources/MouselessApp/main.swift")
if grep -Eq 'logger|apply\(|CGEvent\(|configurationURL\(' <<<"$CALLBACK_SOURCE"; then
  echo "Event-tap callback guard failed: callback path contains forbidden work." >&2
  exit 1
fi

echo "Building the signed Release candidate..."
xcodebuild \
  -project "$PROJECT" \
  -scheme Mouseless \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="$EXPECTED_IDENTITY" \
  clean build

"$SCRIPT_DIR/tcc-smoke-test.sh" "$APP_PATH"

DETAILS=$(codesign --display --verbose=4 "$APP_PATH" 2>&1)
REQUIREMENTS=$(codesign --display --requirements - "$APP_PATH" 2>&1)
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")
EXECUTABLE_SHA256=$(shasum -a 256 "$APP_PATH/Contents/MacOS/Mouseless" | awk '{print $1}')
REQUIREMENTS_SINGLE_LINE=$(tr '\n' ' ' <<<"$REQUIREMENTS" | sed 's/[[:space:]]\+/ /g')
GIT_REVISION=$(git -C "$REPO_ROOT" rev-parse HEAD)
BUILT_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
WORKTREE_STATUS=$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)
if [[ -n "$WORKTREE_STATUS" ]]; then
  SOURCE_STATE=dirty
else
  SOURCE_STATE=clean
fi
WORKTREE_FINGERPRINT=$(
  {
    git -C "$REPO_ROOT" diff --binary --no-ext-diff HEAD --
    git -C "$REPO_ROOT" ls-files --others --exclude-standard -z \
      | while IFS= read -r -d '' path; do
          printf 'untracked:%s ' "$path"
          shasum -a 256 "$REPO_ROOT/$path"
        done
  } | shasum -a 256 | awk '{print $1}'
)

mkdir -p "$(dirname "$MANIFEST_PATH")"
cat > "$MANIFEST_PATH" <<EOF
schemaVersion=1
gitRevision=$GIT_REVISION
sourceState=$SOURCE_STATE
workingTreeFingerprint=$WORKTREE_FINGERPRINT
builtAtUTC=$BUILT_AT_UTC
configuration=$CONFIGURATION
version=$VERSION
buildNumber=$BUILD_NUMBER
bundleIdentifier=$EXPECTED_IDENTIFIER
signingIdentity=$EXPECTED_IDENTITY
designatedRequirement=$REQUIREMENTS_SINGLE_LINE
executableSHA256=$EXECUTABLE_SHA256
EOF

grep -Fq "Authority=$EXPECTED_IDENTITY" <<<"$DETAILS" || {
  echo "Candidate manifest verification failed: unexpected signing identity." >&2
  exit 1
}
grep -Fq "identifier \"$EXPECTED_IDENTIFIER\"" <<<"$REQUIREMENTS" || {
  echo "Candidate manifest verification failed: unexpected bundle identifier." >&2
  exit 1
}

echo "Candidate ready: $APP_PATH"
echo "Manifest: $MANIFEST_PATH"
