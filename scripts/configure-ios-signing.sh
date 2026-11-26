#!/bin/bash
# This step runs on a disposable GitHub-hosted macOS runner.
set -euo pipefail
umask 077
: "${IOS_CERTIFICATE_BASE64:?缺少 IOS_CERTIFICATE_BASE64}"
: "${IOS_CERTIFICATE_PASSWORD:?缺少 IOS_CERTIFICATE_PASSWORD}"
: "${IOS_PROFILE_BASE64:?缺少 IOS_PROFILE_BASE64}"

p12="$RUNNER_TEMP/distribution.p12"
profile="$RUNNER_TEMP/adhoc.mobileprovision"
keychain="$RUNNER_TEMP/release.keychain-db"
trap 'rm -f "$p12" "$profile"' EXIT
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 -D > "$p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 -D > "$profile"
keypass="$(openssl rand -hex 24)"
security create-keychain -p "$keypass" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keypass" "$keychain"
security import "$p12" -P "$IOS_CERTIFICATE_PASSWORD" -f pkcs12 -k "$keychain" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "$keypass" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"

plist="$RUNNER_TEMP/adhoc.plist"
security cms -D -i "$profile" > "$plist"
uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist")"
team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist")"
[[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ && "$team" =~ ^[A-Z0-9]{10}$ ]]
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
cp "$profile" "$profiles/$uuid.mobileprovision"
cat > frontend/ios/Flutter/LocalSigning.xcconfig <<EOF
DEVELOPMENT_TEAM = $team
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
PROVISIONING_PROFILE_SPECIFIER = $uuid
EOF

# Explicit manual export also works with an otherwise empty runner account.
export_plist="$RUNNER_TEMP/ExportOptions.plist"
plutil -create xml1 "$export_plist"
plutil -insert method -string release-testing "$export_plist"
plutil -insert signingStyle -string manual "$export_plist"
plutil -insert teamID -string "$team" "$export_plist"
plutil -insert provisioningProfiles -dictionary "$export_plist"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:app.primitiveaccumulation.primitiveAccumulation string $uuid" "$export_plist"
echo "PA_IOS_EXPORT_OPTIONS=$export_plist" >> "$GITHUB_ENV"
