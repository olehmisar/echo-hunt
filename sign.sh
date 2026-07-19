#!/bin/bash
# Signs, notarizes, and staples dist/EchoHunt.app so it opens with no warning
# on someone else's Mac.
#
# Prerequisites (one-time):
#   1. Paid Apple Developer Program membership.
#   2. A "Developer ID Application" certificate in your keychain.
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#      NOTE: an "Apple Development" certificate is NOT enough — it only works on
#      machines registered to your team.
#   3. Notary credentials stored in the keychain, so no password lives in a file:
#      xcrun notarytool store-credentials echo-hunt-notary \
#        --apple-id you@example.com --team-id YOURTEAMID
#      (it prompts for an app-specific password from appleid.apple.com)
#
# Usage:  ./package.sh && ./sign.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/EchoHunt.app"
PROFILE="${NOTARY_PROFILE:-echo-hunt-notary}"

if [[ ! -d "$APP" ]]; then
    echo "No $APP — run ./package.sh first." >&2
    exit 1
fi

# The `|| true` matters: without it, `grep` finding nothing trips `set -e` and
# the script dies before printing the explanation below.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)}"

if [[ -z "$IDENTITY" ]]; then
    echo "No 'Developer ID Application' certificate found in the keychain." >&2
    echo "Apple Development certificates will not work for distribution." >&2
    exit 1
fi

echo "Signing as: $IDENTITY"
# --options runtime enables the hardened runtime, which notarization requires.
# --timestamp embeds a trusted timestamp so the signature outlives the cert.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "Submitting for notarization (this usually takes a few minutes)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile "$PROFILE" --wait
rm dist/notarize.zip

# Stapling attaches the notarization ticket to the app itself, so it opens even
# if your friend is offline the first time.
echo "Stapling ticket…"
xcrun stapler staple "$APP"

echo "Verifying as Gatekeeper would see it…"
spctl -a -vv "$APP"

echo "Repacking…"
rm -f dist/EchoHunt.zip
(cd dist && zip -q -r EchoHunt.zip EchoHunt.app READ-ME-FIRST.txt)

echo
echo "Signed and notarized: $(cd dist && pwd)/EchoHunt.zip"
echo "Your friend can now just double-click it."
