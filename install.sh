#!/system/bin/sh

BASE="$(cd "$(dirname "$0")" && pwd)"
ZIP_URL="https://github.com/vxy26/gamesdump/releases/download/film/afk.zip"
DEST_DIR="/data/local/tmp"

curl -s -L "$ZIP_URL" -o "$BASE/afk.zip"

unzip -q -o "$BASE/afk.zip" -d "$BASE"

su -c "
cp -r \"$BASE/Delta\" \"/storage/emulated/0/\" 2>/dev/null
cp \"$BASE/Paranoid.Launcher.Port.v1.0.for.A13.QPR3.Magisk.KernelSU.zip\" \"/storage/emulated/0/\" 2>/dev/null
cp \"$BASE/UPDATE-Busybox.Installer.v1.36.1-ALL-signed.zip\" \"/storage/emulated/0/\" 2>/dev/null
cp \"$BASE/remover.apk\" \"$DEST_DIR/\"
cp \"$BASE/1111fixlogin.apk\" \"$DEST_DIR/\"
cp \"$BASE/Auto Clicker_2.3.0.apk\" \"$DEST_DIR/\"
cp \"$BASE/dl1.apk\" \"$DEST_DIR/\"
cp \"$BASE/dl2.apk\" \"$DEST_DIR/\"

pm install -r \"$DEST_DIR/remover.apk\" > /dev/null 2>&1
pm install -r \"$DEST_DIR/1111fixlogin.apk\" > /dev/null 2>&1
pm install -r \"$DEST_DIR/Auto Clicker_2.3.0.apk\" > /dev/null 2>&1
pm install -r \"$DEST_DIR/dl1.apk\" > /dev/null 2>&1
pm install -r \"$DEST_DIR/dl2.apk\" > /dev/null 2>&1

setprop debug.hwui.disable_overlays 1
setprop debug.egl.force_msaa 1
setprop persist.logd.size 65536
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0.5
settings put global background_process_limit 4
settings put system pointer_speed 7
settings put global mobile_data_always_on 1
wm density 235
setprop debug.hwui.force_gpu_rendering true
setprop debug.renderengine.backend skiaglthreaded
setprop debug.sf.latch_unsignaled 1
setprop debug.input.dispatcher_priority 1
setprop net.tcp.buffersize.default 4096,87380,256960,4096,16384,256960
"
