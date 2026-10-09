#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Moonfin"
APK_SOURCE="$REPO_ROOT/build/app/outputs/flutter-apk/app-mobile-release.apk"
BUNDLE_SOURCE="$REPO_ROOT/build/app/outputs/bundle/mobileRelease/app-mobile-release.aab"
TV_APK_SOURCE="$REPO_ROOT/build/app/outputs/flutter-apk/app-androidtv-release.apk"
TV_BUNDLE_SOURCE="$REPO_ROOT/build/app/outputs/bundle/androidTvRelease/app-androidTv-release.aab"
PAGE_SIZE_CHECKER="$REPO_ROOT/scripts/check-android-16kb-pages.sh"

resolve_flutter() {
  if [ -n "${FLUTTER_BIN:-}" ] && [ -x "$FLUTTER_BIN" ]; then
    printf '%s\n' "$FLUTTER_BIN"
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  local candidates=(
    "$HOME/flutter/bin/flutter"
    "$HOME/Documents/flutter/bin/flutter"
    "$HOME/snap/flutter/common/flutter/bin/flutter"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Error: Flutter not found. Add flutter to PATH or set FLUTTER_BIN to the full flutter executable path." >&2
  exit 1
}

FLUTTER="$(resolve_flutter)"

# 09.10, Sid ("j'ai trois TV, 3 tél + 3 tablettes + 2 voitures... réinstaller
# l'APK à chaque fois est lourd"): Shorebird code-push support, APK only (the
# AAB further down is for a possible future Play Store listing, untouched by
# OTA - Shorebird patches a directly-installed APK, not a store build).
#
# SHOREBIRD_MODE (set by build-carba-android.yml depending on tag vs plain
# push) picks the operation:
#   "release" - new install base (needed after a native change) - produces a
#               real APK, same downstream copy/16kb-check as a plain build.
#   "patch"   - OTA update of the existing release, no reinstall needed, the
#               common case. Produces no distributable artifact (the patch
#               is a binary diff pushed straight to Shorebird's servers) -
#               so this mode returns early, skipping the AAB/TV-bundle steps
#               entirely further below.
#   "" (unset) - unchanged plain "flutter build apk/appbundle", so running
#               this script by hand still works exactly as before.
SHOREBIRD_MODE="${SHOREBIRD_MODE:-}"

resolve_shorebird() {
  if command -v shorebird >/dev/null 2>&1; then
    command -v shorebird
    return 0
  fi
  # 09.10: the installer's actual target dir isn't stable across
  # environments - observed ~/.config/shorebird/bin on a GitHub Actions
  # runner but ~/.shorebird/bin in a local Docker container the same day.
  local candidate
  for candidate in "$HOME/.config/shorebird/bin/shorebird" "$HOME/.shorebird/bin/shorebird"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "Error: Shorebird CLI not found (SHOREBIRD_MODE=$SHOREBIRD_MODE needs it)." >&2
  exit 1
}

# 09.10: `shorebird release` refuses outright to recreate a release that
# already exists for the exact same build-name+build-number ("Please bump
# your version number and try again") - real, not a bug (hit once creating
# the very first TV release right after mobile's had already gone out).
# Since mobile/androidTv are versioned independently (APP_VERSION/
# APP_BUILD_NUMBER vs TV_VERSION/TV_BUILD_NUMBER), one flavor legitimately
# needing a new release while the other doesn't is a real, recurring case
# - not fatal to the whole script. Echoes the CLI's own output as it runs
# (so Gradle progress is still visible live) while also capturing it to
# detect that one message; sets SHOREBIRD_RELEASE_SKIPPED=1 for the caller
# to skip that flavor's artifact copy/check below instead of failing on a
# "file not found" that's really just "nothing new was built".
shorebird_release() {
  local shorebird_bin log_file status
  shorebird_bin="$(resolve_shorebird)"
  log_file="$(mktemp)"
  SHOREBIRD_RELEASE_SKIPPED=0
  if "$shorebird_bin" release android --artifact apk "$@" 2>&1 | tee "$log_file"; then
    status=0
  else
    status=1
  fi
  if [ "$status" -ne 0 ]; then
    if grep -q "existing android release" "$log_file"; then
      echo "Shorebird release already exists for this version - nothing new to publish, skipping this flavor."
      SHOREBIRD_RELEASE_SKIPPED=1
      rm -f "$log_file"
      return 0
    fi
    rm -f "$log_file"
    exit 1
  fi
  rm -f "$log_file"
}

VERSION_LINE=$(grep '^version:' "$REPO_ROOT/pubspec.yaml" | sed 's/version:[[:space:]]*//' | tr -d '[:space:]')
APP_VERSION=$(printf '%s' "$VERSION_LINE" | cut -d'+' -f1)
APP_BUILD_NUMBER=$(printf '%s' "$VERSION_LINE" | cut -d'+' -f2)
if [ -z "$APP_VERSION" ] || [ -z "$APP_BUILD_NUMBER" ]; then
  echo "Error: could not read semantic version and build number from pubspec.yaml (expected x.y.z+build)" >&2
  exit 1
fi

APK_OUTPUT="$REPO_ROOT/${APP_NAME}_Android_v${APP_VERSION}.apk"
BUNDLE_OUTPUT="$REPO_ROOT/${APP_NAME}_Android_v${APP_VERSION}.aab"

TV_VERSION=$(grep '^\s*android_tv_version:' "$REPO_ROOT/pubspec.yaml" | sed 's/.*android_tv_version:[[:space:]]*//' | tr -d '[:space:]')
TV_BUILD_NUMBER=$(grep '^\s*android_tv_build_number:' "$REPO_ROOT/pubspec.yaml" | sed 's/.*android_tv_build_number:[[:space:]]*//' | tr -d '[:space:]')
if [ -z "$TV_VERSION" ] || [ -z "$TV_BUILD_NUMBER" ]; then
  echo "Error: could not read android_tv_version / android_tv_build_number from pubspec.yaml" >&2
  exit 1
fi

TV_APK_OUTPUT="$REPO_ROOT/${APP_NAME}_AndroidTV_v${TV_VERSION}.apk"
TV_BUNDLE_OUTPUT="$REPO_ROOT/${APP_NAME}_AndroidTV_v${TV_VERSION}.aab"

echo "${APP_NAME} version: ${APP_VERSION} (${APP_BUILD_NUMBER})"
echo "${APP_NAME} Android TV version: ${TV_VERSION} (${TV_BUILD_NUMBER})"
echo "Shorebird mode: ${SHOREBIRD_MODE:-<none - plain flutter build>}"

cd "$REPO_ROOT"

echo "Cleaning previous Flutter outputs..."
"$FLUTTER" clean

echo "Resolving packages..."
"$FLUTTER" pub get

if [ "$SHOREBIRD_MODE" = "patch" ]; then
  SHOREBIRD="$(resolve_shorebird)"

  echo "Publishing Shorebird OTA patch - mobile flavor..."
  "$SHOREBIRD" patch android --flavor mobile \
    --release-version latest \
    --build-name "$APP_VERSION" \
    --build-number "$APP_BUILD_NUMBER" \
    --dart-define=DISTRIBUTION_CHANNEL=apk

  echo "Publishing Shorebird OTA patch - androidTv flavor..."
  "$SHOREBIRD" patch android --flavor androidTv \
    --release-version latest \
    --build-name "$TV_VERSION" \
    --build-number "$TV_BUILD_NUMBER" \
    --dart-define=MOONFIN_FORCE_TV=true \
    --dart-define=DISTRIBUTION_CHANNEL=android_tv_apk

  echo "Both OTA patches published - a patch has no APK/AAB artifact to upload (it's a binary diff pushed straight to Shorebird's servers), nothing else to do."
  exit 0
fi

echo "Building Android release APK (arm64-v8a, armeabi-v7a, x86_64)..."
MOBILE_RELEASE_SKIPPED=0
if [ "$SHOREBIRD_MODE" = "release" ]; then
  shorebird_release \
    --flavor mobile \
    --build-name "$APP_VERSION" \
    --build-number "$APP_BUILD_NUMBER" \
    --dart-define=DISTRIBUTION_CHANNEL=apk
  MOBILE_RELEASE_SKIPPED="$SHOREBIRD_RELEASE_SKIPPED"
else
  "$FLUTTER" build apk --release \
    --flavor mobile \
    --build-name "$APP_VERSION" \
    --build-number "$APP_BUILD_NUMBER" \
    --dart-define=DISTRIBUTION_CHANNEL=apk
fi

if [ "$MOBILE_RELEASE_SKIPPED" = "1" ]; then
  echo "Mobile flavor: release already existed, nothing new built - skipping APK/AAB copy for it."
else
  if [ ! -f "$APK_SOURCE" ]; then
    echo "Error: APK not found at $APK_SOURCE" >&2
    exit 1
  fi

  cp "$APK_SOURCE" "$APK_OUTPUT"

  if [ -x "$PAGE_SIZE_CHECKER" ]; then
    echo "Running 16 KB page-size compatibility check on APK (informational only)..."
    "$PAGE_SIZE_CHECKER" "$APK_SOURCE" || echo "Warning: APK 16 KB page-size check failed (not blocking)" >&2
  fi

  echo "APK created: $APK_SOURCE"
  echo "APK copied to root: $APK_OUTPUT"
fi

# 09.10: `shorebird release --artifact apk` already builds the full AAB
# internally before extracting the APK from it (confirmed in its own log
# output: "Your next step is to upload the app bundle... .aab"), at the
# exact same $BUNDLE_SOURCE path a plain `flutter build appbundle` would
# use. Rebuilding it again here doubled the Gradle work for no reason and
# is the likely cause of a real CI failure (09.10, mobile flavor: killed
# mid-build, exit 143, right after this redundant second build started -
# two consecutive full Gradle release builds plausibly exhausting the
# runner's memory, same OOM pattern already seen on the NAS for this repo).
# Trade-off accepted: this AAB then carries shorebird's own
# DISTRIBUTION_CHANNEL=apk define instead of "aab" - harmless, Sid
# distributes by direct APK install, not the Play Store.
if [ "$MOBILE_RELEASE_SKIPPED" = "1" ]; then
  echo "Mobile flavor: release already existed - skipping App Bundle too (same reason)."
elif [ "$SHOREBIRD_MODE" = "release" ]; then
  echo "Android App Bundle already built by 'shorebird release' above - skipping the redundant rebuild."
else
  if ! "$FLUTTER" build appbundle --release \
    --flavor mobile \
    --build-name "$APP_VERSION" \
    --build-number "$APP_BUILD_NUMBER" \
    --dart-define=DISTRIBUTION_CHANNEL=aab; then
    echo "Flutter appbundle build failed. Retrying with Gradle bundleRelease fallback..."
    (
      cd "$REPO_ROOT/android"
      ./gradlew bundleMobileRelease
    )
  fi
fi

if [ "$MOBILE_RELEASE_SKIPPED" != "1" ]; then
  if [ ! -f "$BUNDLE_SOURCE" ]; then
    echo "Error: App Bundle not found at $BUNDLE_SOURCE" >&2
    exit 1
  fi

  cp "$BUNDLE_SOURCE" "$BUNDLE_OUTPUT"

  if [ -x "$PAGE_SIZE_CHECKER" ]; then
    echo "Running 16 KB page-size compatibility check on App Bundle..."
    "$PAGE_SIZE_CHECKER" "$BUNDLE_SOURCE"
  fi

  echo "App Bundle created: $BUNDLE_SOURCE"
  echo "App Bundle copied to root: $BUNDLE_OUTPUT"
fi

echo "Building Android TV release APK..."
TV_RELEASE_SKIPPED=0
if [ "$SHOREBIRD_MODE" = "release" ]; then
  shorebird_release \
    --flavor androidTv \
    --build-name "$TV_VERSION" \
    --build-number "$TV_BUILD_NUMBER" \
    --dart-define=MOONFIN_FORCE_TV=true \
    --dart-define=DISTRIBUTION_CHANNEL=android_tv_apk
  TV_RELEASE_SKIPPED="$SHOREBIRD_RELEASE_SKIPPED"
else
  "$FLUTTER" build apk --release \
    --flavor androidTv \
    --build-name "$TV_VERSION" \
    --build-number "$TV_BUILD_NUMBER" \
    --dart-define=MOONFIN_FORCE_TV=true \
    --dart-define=DISTRIBUTION_CHANNEL=android_tv_apk
fi

if [ "$TV_RELEASE_SKIPPED" = "1" ]; then
  echo "Android TV flavor: release already existed, nothing new built - skipping APK/AAB copy for it."
else
  if [ ! -f "$TV_APK_SOURCE" ]; then
    echo "Error: TV APK not found at $TV_APK_SOURCE" >&2
    exit 1
  fi

  cp "$TV_APK_SOURCE" "$TV_APK_OUTPUT"

  if [ -x "$PAGE_SIZE_CHECKER" ]; then
    echo "Running 16 KB page-size compatibility check on TV APK (informational only)..."
    "$PAGE_SIZE_CHECKER" "$TV_APK_SOURCE" || echo "Warning: TV APK 16 KB page-size check failed (not blocking)" >&2
  fi

  echo "TV APK created: $TV_APK_SOURCE"
  echo "TV APK copied to root: $TV_APK_OUTPUT"
fi

echo "Building Android TV App Bundle..."
if [ "$TV_RELEASE_SKIPPED" = "1" ]; then
  echo "Android TV flavor: release already existed - skipping App Bundle too (same reason)."
elif [ "$SHOREBIRD_MODE" = "release" ]; then
  echo "Android TV App Bundle already built by 'shorebird release' above - skipping the redundant rebuild."
elif ! "$FLUTTER" build appbundle --release \
  --flavor androidTv \
  --build-name "$TV_VERSION" \
  --build-number "$TV_BUILD_NUMBER" \
  --dart-define=MOONFIN_FORCE_TV=true \
  --dart-define=DISTRIBUTION_CHANNEL=android_tv_aab; then
  echo "Flutter appbundle build failed. Retrying with Gradle bundleAndroidTvRelease fallback..."
  (
    cd "$REPO_ROOT/android"
    ./gradlew bundleAndroidTvRelease
  )
fi

if [ "$TV_RELEASE_SKIPPED" != "1" ]; then
  if [ ! -f "$TV_BUNDLE_SOURCE" ]; then
    echo "Error: TV App Bundle not found at $TV_BUNDLE_SOURCE" >&2
    exit 1
  fi

  cp "$TV_BUNDLE_SOURCE" "$TV_BUNDLE_OUTPUT"

  if [ -x "$PAGE_SIZE_CHECKER" ]; then
    echo "Running 16 KB page-size compatibility check on TV App Bundle..."
    "$PAGE_SIZE_CHECKER" "$TV_BUNDLE_SOURCE"
  fi

  echo "TV App Bundle created: $TV_BUNDLE_SOURCE"
  echo "TV App Bundle copied to root: $TV_BUNDLE_OUTPUT"
fi
