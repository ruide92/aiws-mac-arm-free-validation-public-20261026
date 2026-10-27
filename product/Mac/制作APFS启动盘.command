#!/bin/bash
# 在 Mac 上把已验证的 APFS 母版恢复到一块外置 U 盘。
# 这个脚本会清空目标盘，必须由用户明确输入 YES 才会执行。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
SRC="${1:-$HERE/AIWSMM0004-apfs.dmg}"
MOUNT="$HERE/.aiws-apfs-source"
VOLUME_NAME="AIWSMM0004"

say() { printf '\n%s\n' "$*"; }
fail() { printf '\n错误：%s\n' "$*" >&2; exit 1; }

[ -f "$SRC" ] || fail "找不到母版：$SRC"
[ "$(uname -s)" = "Darwin" ] || fail "这个脚本只能在 Mac 上运行。"

say "即将使用母版：$SRC"
say "当前外置磁盘列表："
diskutil list

printf '\n请输入要清空并制作成 Mac 启动盘的磁盘编号（例如 disk4，不要带 s1）：'
read -r DISK
case "$DISK" in
  disk[0-9]*) ;;
  *) fail "磁盘编号格式不对：$DISK" ;;
esac

INFO="$(diskutil info "$DISK" 2>/dev/null)" || fail "找不到磁盘 $DISK"
printf '%s\n' "$INFO" | grep -q 'Internal:.*No' || fail "拒绝操作：$DISK 不是外置磁盘。"
SIZE="$(printf '%s\n' "$INFO" | awk -F: '/Disk Size:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')"
say "目标：$DISK"
say "容量：${SIZE:-未知}"

printf '\n这会清空 %s 上的全部内容。确定输入 YES：' "$DISK"
read -r CONFIRM
[ "$CONFIRM" = "YES" ] || fail "用户取消。"

mkdir -p "$MOUNT"
cleanup() {
  hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
}
trap cleanup EXIT

say "挂载只读母版……"
hdiutil attach "$SRC" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null

say "格式化为 APFS（GPT）……"
diskutil eraseDisk APFS "$VOLUME_NAME" GPT "$DISK" >/dev/null
TARGET="/Volumes/$VOLUME_NAME"
[ -d "$TARGET" ] || fail "目标卷没有挂载：$TARGET"

say "复制两个完整官方 App（保留符号链接、权限和签名）……"
for app in "Hermes Agent.app" "DeepSeek Harness.app"; do
  [ -d "$MOUNT/$app" ] || fail "母版里缺少 $app"
  ditto "$MOUNT/$app" "$TARGET/$app"
done

for f in "开始使用.html" "先看这里.txt"; do
  [ -f "$MOUNT/$f" ] && ditto "$MOUNT/$f" "$TARGET/$f"
done

say "校验代码签名……"
for app in "Hermes Agent.app" "DeepSeek Harness.app"; do
  codesign --verify --deep --strict "$TARGET/$app" || fail "$app 签名校验失败"
  printf 'OK  %s\n' "$app"
done

say "校验关键符号链接……"
for app in "Hermes Agent.app" "DeepSeek Harness.app"; do
  if find "$TARGET/$app" -type l ! -exec test -e {} \; -print | grep -q .; then
    fail "$app 里有断开的符号链接"
  fi
done

say "完成。"
say "请在 Finder 中推出 U 盘，再拿到 Apple 芯片 Mac 上双击两个 App 验收。"
say "目标卷：$TARGET"
