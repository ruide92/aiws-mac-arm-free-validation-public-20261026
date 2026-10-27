#!/bin/bash
# 在 Apple 芯片 Mac 上做基础双击验收；不写入 Key，不做模型调用。
# 默认检查 /Volumes/AIWSMM0004；也可以把 U 盘路径作为第一个参数传入。
set -u

VOLUME_NAME="AIWSMM0004"
BASE="${1:-/Volumes/$VOLUME_NAME}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
OUT="$HOME/Desktop/AIWS-验收-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

fail() {
  echo "错误：$*" >&2
  echo
  echo "请先把 U 盘插上，确认 Finder 里能看到 $VOLUME_NAME，再重新运行。"
  read -r -p "按回车关闭……" _
  exit 1
}

if [ ! -d "$BASE/Hermes Agent.app" ]; then
  for candidate in /Volumes/AIWSMM0004*; do
    if [ -d "$candidate/Hermes Agent.app" ]; then
      BASE="$candidate"
      break
    fi
  done
fi

[ -d "$BASE/Hermes Agent.app" ] || fail "在 $BASE 找不到 Hermes Agent.app"
[ -d "$BASE/DeepSeek Harness.app" ] || fail "在 $BASE 找不到 DeepSeek Harness.app"

{
  echo "date=$(date)"
  echo "uname=$(uname -a)"
  echo "arch=$(uname -m)"
  sw_vers
  echo
  system_profiler SPHardwareDataType | sed -n '1,40p'
  echo
  echo "base=$BASE"
} > "$OUT/host.txt" 2>&1

for app in "Hermes Agent.app" "DeepSeek Harness.app"; do
  echo "--- $app ---" | tee -a "$OUT/apps.txt"
  codesign --verify --deep --strict "$BASE/$app" >> "$OUT/apps.txt" 2>&1 && echo "codesign=OK" >> "$OUT/apps.txt" || echo "codesign=FAIL" >> "$OUT/apps.txt"
  find "$BASE/$app" -type l ! -exec test -e {} \; -print > "$OUT/broken-links.txt" 2>&1 || true
  if [ -s "$OUT/broken-links.txt" ]; then echo "symlinks=FAIL" >> "$OUT/apps.txt"; else echo "symlinks=OK" >> "$OUT/apps.txt"; fi
  open -n "$BASE/$app" >> "$OUT/apps.txt" 2>&1 || true
done

# Hermes 首次打开会先显示加载动画，约 60 秒后才出现引导页；不能只等 25 秒。
sleep 80
pgrep -af 'Hermes|DeepSeek' > "$OUT/processes.txt" 2>&1 || true
osascript -e 'tell application "System Events" to get name of every process whose background only is false' > "$OUT/windows.txt" 2>&1 || true
screencapture -x "$OUT/screen.png" 2>/dev/null || true
system_profiler SPUSBDataType > "$OUT/usb.txt" 2>&1 || true

echo
echo "验收资料已保存到：$OUT"
echo "请把整个文件夹发给卖家；两个 App 窗口是否出现，也请拍照或说明。"
open "$OUT"
