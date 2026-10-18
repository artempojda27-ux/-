#!/usr/bin/env bash
# оживление партии: для каждого персонажа петли talk и idle; готовые пропускаются
L=/tmp/claude-0/-home-user--/1c48a050-dccd-5f37-96f0-2c33fbd755c1/scratchpad/lp
P=/home/user/-/tiktok-mafia
CAST=/tmp/claude-0/-home-user--/1c48a050-dccd-5f37-96f0-2c33fbd755c1/scratchpad/gen/cast
for slug in "$@"; do
  for kind in talk idle; do
    [ -f "$P/assets/alive/$slug-$kind.webm" ] && { echo "$slug $kind есть"; continue; }
    t=$(date +%s)
    (cd $L/src && OMP_NUM_THREADS=4 ../../sd/bin/python inference.py -s $CAST/$slug.png -d ../drv/$kind.mp4 --flag_force_cpu -o ../batch >/dev/null 2>&1)
    if [ -f "$L/batch/$slug--$kind.mp4" ]; then
      "$P/make-alive.sh" "$slug" "$kind" "$L/batch/$slug--$kind.mp4" >/dev/null && echo "$slug $kind ok $(( $(date +%s) - t ))s"
    else
      echo "$slug $kind ОШИБКА"
    fi
  done
done
