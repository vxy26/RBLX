#!/system/bin/sh

ZIP_URL="https://github.com/vxy26/RBLX/releases/download/rbl/afk1.zip"
ZIP_PATH="/storage/emulated/0/Download/afk1.zip"
EXTRACT_DIR="/storage/emulated/0/Download/afk"
SOURCE_DIR="/storage/emulated/0/Download/afk"
DEST_DIR="/data/local/tmp"

# Download
echo "[1/4] Downloading..."
if command -v curl > /dev/null 2>&1; then
    curl -L "$ZIP_URL" -o "$ZIP_PATH"
elif command -v wget > /dev/null 2>&1; then
    wget -O "$ZIP_PATH" "$ZIP_URL"
else
    echo "ERROR: curl/wget tidak ditemukan"
    exit 1
fi

# Cek apakah download berhasil
if [ ! -f "$ZIP_PATH" ]; then
    echo "ERROR: Download gagal"
    exit 1
fi

# Unzip
echo "[2/4] Extracting..."
unzip -o "$ZIP_PATH" -d "$EXTRACT_DIR"

# Cek hasil ekstrak
if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Folder afk tidak ditemukan setelah ekstrak"
    exit 1
fi

echo "[3/4] Installing..."
su -c "
# Copy APK
cp -r /storage/emulated/0/Download/afk/Delta /storage/emulated/0/
cp \"$SOURCE_DIR/remover.apk\" \"$DEST_DIR/\"
cp \"$SOURCE_DIR/1111fixlogin.apk\" \"$DEST_DIR/\"
cp \"$SOURCE_DIR/Auto Clicker_2.3.0.apk\" \"$DEST_DIR/\"
cp \"$SOURCE_DIR/Delta-2.718.1110-02.apk\" \"$DEST_DIR/\"
cp \"$SOURCE_DIR/Delta-2.718.1110-02_clone.apk\" \"$DEST_DIR/\"

# Install APK
pm install -r \"$DEST_DIR/remover.apk\"
pm install -r \"$DEST_DIR/1111fixlogin.apk\"
pm install -r \"$DEST_DIR/Auto Clicker_2.3.0.apk\"
pm install -r \"$DEST_DIR/Delta-2.718.1110-02.apk\"
pm install -r \"$DEST_DIR/Delta-2.718.1110-02_clone.apk\"

# Tweak
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

# Uninstall
pm uninstall bin.mt.plus.canary
"

echo "[4/4] Done! Semua APK terinstall dan tweak diterapkan."
