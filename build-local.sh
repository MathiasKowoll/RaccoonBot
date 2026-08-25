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

xcodebuild -project "$HERE/Procyon.xcodeproj" \
           -scheme Procyon \
           -configuration "$CONFIG" \
           -destination 'platform=macOS' \
           CODE_SIGN_STYLE=Manual \
           CODE_SIGN_IDENTITY=- \
           DEVELOPMENT_TEAM= \
           PROVISIONING_PROFILE_SPECIFIER= \
           build "${@:2}"

# Install it beside the sources, under a name that cannot be confused with the
# released Procyon. Both bundles declare the same identifier, so Spotlight and
# Launchpad will happily open the wrong one; the path is the only thing that
# tells them apart, and keeping ours in the checkout means there is never a
# stale copy of unknown vintage sitting in ~/Applications.
PRODUCT="$(xcodebuild -project "$HERE/Procyon.xcodeproj" -scheme Procyon \
             -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
           | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
if [ -n "$PRODUCT" ] && [ -d "$PRODUCT/Procyon.app" ]; then
  DEST="$HERE/build/Procyon-mgvf.app"
  mkdir -p "$HERE/build"
  rm -rf "$DEST" && cp -R "$PRODUCT/Procyon.app" "$DEST" \
    && echo "installed: $DEST"
fi
