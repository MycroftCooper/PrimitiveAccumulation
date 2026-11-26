#!/bin/bash
# Run inside the fresh source archive prepared by release.py.
set -euo pipefail
cd "$(dirname "$0")/../frontend"
[[ "$(uname -s)" == Darwin ]] || { echo "iOS 打包需要 macOS 和 Xcode。" >&2; exit 1; }

# Optional per-machine signing settings; this directory is a temporary checkout.
signing="$HOME/.config/primitive-accumulation/ios.xcconfig"
if [[ -f "$signing" ]]; then
  cp "$signing" ios/Flutter/LocalSigning.xcconfig
fi
flutter_bin="${PA_FLUTTER:-flutter}"
"$flutter_bin" pub get --enforce-lockfile
export_args=(--export-method ad-hoc)
if [[ -n "${PA_IOS_EXPORT_OPTIONS:-}" ]]; then
  export_args=(--export-options-plist "$PA_IOS_EXPORT_OPTIONS")
fi
"$flutter_bin" build ipa --release --no-pub "${export_args[@]}"

# Flutter can finish the archive successfully even if the IPA export failed.
shopt -s nullglob
ipas=(build/ios/ipa/*.ipa)
if [[ ${#ipas[@]} != 1 ]]; then
  echo "Xcode 未导出唯一的 Ad Hoc IPA，请检查签名证书和设备描述文件。" >&2
  exit 1
fi
mkdir build/verify-ipa
/usr/bin/ditto -x -k "${ipas[0]}" build/verify-ipa
apps=(build/verify-ipa/Payload/*.app)
[[ ${#apps[@]} == 1 && -s "${apps[0]}/embedded.mobileprovision" ]]
/usr/bin/codesign --verify --deep --strict "${apps[0]}"
cp "${ipas[0]}" ../app.ipa
