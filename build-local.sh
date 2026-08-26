#!/usr/bin/env bash
#
# Build Procyon locally, without the author's signing identity.
#
# The project hardcodes DEVELOPMENT_TEAM = S5P3AKN3YC and CODE_SIGN_IDENTITY =
# "Apple Development" at target level, which beats anything Config.xcconfig
# says, so a machine without that certificate cannot build at all. Overriding
# on the command line is the one place that wins over target settings, and it
# keeps project.pbxproj untouched -- a tracked file we would otherwise have to
# un-edit on every rebase against upstream.
#
# Ad-hoc ("-") is enough here: the target ships no entitlements file and has
# ENABLE_APP_SANDBOX = NO.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-Debug}"

xcodebuild -project "$HERE/RaccoonBot.xcodeproj" \
           -scheme RaccoonBot \
           -configuration "$CONFIG" \
           -destination 'platform=macOS' \
           CODE_SIGN_STYLE=Manual \
           CODE_SIGN_IDENTITY=- \
           DEVELOPMENT_TEAM= \
           PROVISIONING_PROFILE_SPECIFIER= \
           build "${@:2}"

# Install it beside the sources. The bundle identifier is now our own, so
# this no longer competes with the released Procyon for the same identity --
# but keeping it in the checkout still means there is never a stale copy of
# unknown vintage sitting in ~/Applications.
# Both the directory and the bundle name come from the build settings rather
# than being spelled here. They have already disagreed once: this hardcoded
# "Procyon.app" after the target was renamed. A stale bundle of the old name
# was still sitting in BUILT_PRODUCTS_DIR, so the -d test passed and the script
# cheerfully installed the WRONG binary -- older, and named for a product that
# no longer exists. Deriving the name removes the chance to be right by
# accident, and a missing product is now an error rather than a no-op.
SETTINGS="$(xcodebuild -project "$HERE/RaccoonBot.xcodeproj" -scheme RaccoonBot \
              -configuration "$CONFIG" -showBuildSettings 2>/dev/null)"
PRODUCT="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
BUNDLE="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME /{print $2; exit}')"

if [ -z "$PRODUCT" ] || [ -z "$BUNDLE" ]; then
  echo "build-local.sh: could not read BUILT_PRODUCTS_DIR / FULL_PRODUCT_NAME" >&2
  exit 1
fi
if [ ! -d "$PRODUCT/$BUNDLE" ]; then
  echo "build-local.sh: built nothing at $PRODUCT/$BUNDLE" >&2
  exit 1
fi

DEST="$HERE/build/$BUNDLE"
mkdir -p "$HERE/build"
rm -rf "$DEST" && cp -R "$PRODUCT/$BUNDLE" "$DEST" || exit 1
echo "installed: $DEST"
