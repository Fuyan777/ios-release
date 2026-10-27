#!/bin/bash
# アップロードの前に、説明文の文字数とスクショの大きさを確かめる。
#   check.sh <fastlane フォルダ>   例: check.sh ./fastlane
# 問題がなければ 0、あれば 1 で終わる。
set -u
export LC_ALL=en_US.UTF-8
FL="${1:-./fastlane}"
NG=0

say() { printf '%s\n' "$*"; }
bad() { say "  NG  $*"; NG=1; }
ok() { say "  OK  $*"; }

# 文字数（App Store の上限）
check_len() {
  local file="$1" max="$2" required="$3"
  if [ ! -f "$file" ]; then
    if [ "$required" = 1 ]; then bad "$(basename "$file") がない（必須）"; fi
    return
  fi
  local n
  n=$(tr -d '\n' < "$file" | wc -m | tr -d ' ')
  if [ "$n" -eq 0 ] && [ "$required" = 1 ]; then bad "$(basename "$file") が空（必須）"
  elif [ "$n" -gt "$max" ]; then bad "$(basename "$file") が ${n} 文字（上限 ${max}）"
  else ok "$(basename "$file") ${n}/${max}"
  fi
}

say "■ 説明文"
found=0
for dir in "$FL"/metadata/*/; do
  [ -d "$dir" ] || continue
  lang=$(basename "$dir")
  [ "$lang" = "review_information" ] && continue
  [ -f "$dir/name.txt" ] || [ -f "$dir/description.txt" ] || continue
  found=1
  say "[$lang]"
  check_len "$dir/name.txt" 30 1
  check_len "$dir/subtitle.txt" 30 0
  check_len "$dir/description.txt" 4000 1
  check_len "$dir/keywords.txt" 100 1
  check_len "$dir/promotional_text.txt" 170 0
  check_len "$dir/release_notes.txt" 4000 0
  check_len "$dir/support_url.txt" 255 1
  check_len "$dir/privacy_url.txt" 255 1
done
[ "$found" = 1 ] || bad "$FL/metadata/<言語>/ に説明文がない"
[ -f "$FL/metadata/copyright.txt" ] && ok "copyright.txt" || bad "copyright.txt がない（必須）"
[ -f "$FL/metadata/primary_category.txt" ] && ok "primary_category.txt" || bad "primary_category.txt がない（必須）"

# スクショの大きさ（App Store が受け付けるもの）
say "■ スクショ"
IPHONE="1320x2868 2868x1320 1290x2796 2796x1290 1260x2736 2736x1260 1284x2778 2778x1284 1242x2688 2688x1242"
IPAD="2064x2752 2752x2064 2048x2732 2732x2048"
shots=0; iphone=0
while IFS= read -r -d '' f; do
  shots=$((shots + 1))
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')
  size="${w}x${h}"
  rel="${f#"$FL"/screenshots/}"
  if [[ " $IPHONE " == *" $size "* ]]; then ok "${rel}  ${size}（iPhone）"; iphone=$((iphone + 1))
  elif [[ " $IPAD " == *" $size "* ]]; then ok "${rel}  ${size}（iPad 13インチ）"
  else bad "${rel}  ${size}（この大きさは受け付けられない）"
  fi
done < <(find "$FL/screenshots" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) -print0 2>/dev/null | sort -z)
[ "$shots" -gt 0 ] || bad "$FL/screenshots/<言語>/ にスクショがない"
[ "$shots" -eq 0 ] || [ "$iphone" -gt 0 ] || bad "iPhone のスクショがない（必須）"

# 秘密のファイルがリポジトリに入っていないか
say "■ 秘密のファイル"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  leaked=$(git ls-files | grep -E '\.p8$|api_key\.json$|review_information/' || true)
  if [ -n "$leaked" ]; then bad "git に入っている: $leaked"; else ok "APIキー・審査用の連絡先は git に入っていない"; fi
fi

say ""
if [ "$NG" = 0 ]; then say "問題なし"; else say "NG を直してからアップロードする"; fi
exit "$NG"
