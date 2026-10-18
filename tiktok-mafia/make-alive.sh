#!/usr/bin/env bash
# Живые петли персонажей: видео LivePortrait (на зелёном фоне) → WebM с прозрачностью.
#
#     ./make-alive.sh margo talk lp-out/margo--talk.mp4
#
# Петля «туда-обратно»: клип и он же задом наперёд. Тогда последний кадр
# совпадает с первым и петля крутится без скачка — у лица не бывает «склейки».
# WebM VP9 с альфой понимают Chrome и OBS (Browser Source — это Chromium).
# Safari альфу в VP9 не умеет — там сцена остаётся на статичных портретах.
set -euo pipefail
slug="$1"; kind="$2"; src="$3"
out="$(dirname "$0")/assets/alive/${slug}-${kind}.webm"
mkdir -p "$(dirname "$out")"

# similarity 0.16: зелень фона уходит, тёмно-зелёная одежда (Нина) остаётся
ffmpeg -v error -y -i "$src" -filter_complex "
  [0]chromakey=0x00ff00:0.16:0.06,despill=type=green,split[a][b];
  [b]reverse[r];
  [a][r]concat=n=2:v=1:a=0,format=yuva420p[v]" \
  -map "[v]" -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 34 -deadline good -an "$out"
echo "$out"
