#!/bin/bash
# 在 Apple 芯片 Mac 上做基础双击验收；不写入 Key，不做模型调用。
set -u

HERE="$(cd "$(dirname "$0")" && pwd -P)"
OUT="$HERE/验收结果-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

{
  echo "date=$(date)"
  echo "uname=$(uname -a)"
  echo "arch=$(uname -m)"
  sw_vers
  echo
  system_profiler SPHardwareDataType | sed -n '1,40p'
} > "$OUT/host.txt" 2>&1

for app in "Hermes Agent.app" "DeepSeek Harness.app"; do
  echo "--- $app ---" | tee -a "$OUT/apps.txt"
  if [ ! -d "$HERE/$app" ]; then
    echo "MISSING" | tee -a "$OUT/apps.txt"
    continue
  fi
  codesign --verify --deep --strict "$HERE/$app" >> "$OUT/apps.txt" 2>&1 && echo "codesign=OK" >> "$OUT/apps.txt" || echo "codesign=FAIL" >> "$OUT/apps.txt"
  find "$HERE/$app" -type l ! -exec test -e {} \; -print > "$OUT/broken-links.txt" 2>&1 || true
  if [ -s "$OUT/broken-links.txt" ]; then echo "symlinks=FAIL" >> "$OUT/apps.txt"; else echo "symlinks=OK" >> "$OUT/apps.txt"; fi
  open -n "$HERE/$app" >> "$OUT/apps.txt" 2>&1 || true
done

sleep 25
pgrep -af 'Hermes|DeepSeek' > "$OUT/processes.txt" 2>&1 || true
osascript -e 'tell application "System Events" to get name of every process whose background only is false' > "$OUT/windows.txt" 2>&1 || true
screencapture -x "$OUT/screen.png" 2>/dev/null || true
system_profiler SPUSBDataType > "$OUT/usb.txt" 2>&1 || true

echo
echo "验收资料已保存到：$OUT"
echo "请把整个文件夹发给卖家；两个 App 窗口是否出现，也请拍照或说明。"
open "$OUT"
