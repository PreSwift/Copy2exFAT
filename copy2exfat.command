#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/Copy2exFAT.app"

if [[ ! -x "$APP/Contents/MacOS/Copy2exFAT" ]]; then
    echo "首次运行，正在构建应用…"
    /bin/bash "$DIR/build.sh"
fi

open "$APP"
