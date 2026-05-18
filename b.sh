#!/system/bin/sh
# =============================================================================
# roblox_master_daemon.sh
# Unified Auto-Restarter, Auto-Tiler, Cache Cleaner, & Resource Monitor
# =============================================================================

PACKAGES="dkapp.pol.seiyw dkapp.pol.seiyx"
ACTIVITY="com.roblox.client.ActivityProtocolLaunch"
VIP_LINK="https://www.roblox.com/share?code=ac5a31bf7737de46a02794815e5d13fa&type=Server"

CHECK_INTERVAL=3
LAUNCH_DELAY=12

# Paksa Mode Resizable (Berlaku jika didukung ROM)
settings put global enable_freeform_support 1 2>/dev/null
settings put global force_resizable_activities 1 2>/dev/null

# ── Resolusi Layar ──
SCREEN_SIZE=$(wm size 2>/dev/null | grep -o '[0-9]*x[0-9]*' | head -1)
W=$(echo "$SCREEN_SIZE" | cut -dx -f1)
H=$(echo "$SCREEN_SIZE" | cut -dx -f2)
[ -z "$W" ] && W=1080
[ -z "$H" ] && H=2400

HALF_W=$((W / 2))
HALF_H=$((H / 2))

echo "[SYS] Resolusi: ${W}x${H} | FSM Daemon Memulai..."

# ── Fungsi Pemantauan RAM & CPU ──
monitor_resources() {
    # Membaca Load Average CPU (1 menit terakhir)
    local cpu_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    
    # Membaca sisa RAM dalam Megabyte
    local ram_free_kb=$(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2}')
    local ram_free_mb=$((ram_free_kb / 1024))
    
    echo "[MONITOR] CPU Load: $cpu_load | RAM Bebas: ${ram_free_mb} MB"
}

# ── Fungsi Pembersihan Cache (Aman) ──
clear_app_cache() {
    local pkg="$1"
    echo "[CLEANUP] Membersihkan cache untuk $pkg..."
    # Menghapus cache tanpa menyentuh data login (shared_prefs/databases)
    rm -rf "/data/data/$pkg/cache/*" 2>/dev/null
    rm -rf "/data/data/$pkg/code_cache/*" 2>/dev/null
}

# ── Fungsi State Management (Simulasi FSM di Shell) ──
# Kita menggunakan eval untuk membuat variabel dinamis berdasarkan nama package
set_state() {
    local safe_pkg=$(echo "$1" | tr '.' '_')
    eval "STATE_$safe_pkg=\"$2\""
}

get_state() {
    local safe_pkg=$(echo "$1" | tr '.' '_')
    eval "echo \$STATE_$safe_pkg"
}

set_timer() {
    local safe_pkg=$(echo "$1" | tr '.' '_')
    local current_time=$(date +%s)
    eval "TIMER_$safe_pkg=$current_time"
}

get_timer() {
    local safe_pkg=$(echo "$1" | tr '.' '_')
    eval "echo \$TIMER_$safe_pkg"
}

# Inisialisasi State Awal
for pkg in $PACKAGES; do
    set_state "$pkg" "STOPPED"
    set_timer "$pkg" 0
    am force-stop "$pkg" 2>/dev/null
done

# Variabel pemicu Auto-Tiling
NEEDS_LAYOUT=0

# ── Loop Utama (Daemon) ──
while true; do
    monitor_resources
    
    for pkg in $PACKAGES; do
        # Cek apakah proses berjalan
        pid=$(pidof "$pkg" 2>/dev/null)
        state=$(get_state "$pkg")
        
        case "$state" in
            "STOPPED")
                if [ -n "$pid" ]; then
                    # Jika tiba-tiba berjalan (dibuka manual)
                    set_state "$pkg" "RESIZING"
                else
                    echo "[WATCHDOG] $pkg mati. Memulai peluncuran..."
                    am start -n "${pkg}/${ACTIVITY}" \
                        -a android.intent.action.VIEW \
                        -d "${VIP_LINK}" \
                        --activity-clear-top --activity-single-top \
                        --windowingMode 5 >/dev/null 2>&1
                    
                    set_state "$pkg" "LAUNCHING"
                    set_timer "$pkg"
                fi
                ;;
                
            "LAUNCHING")
                if [ -z "$pid" ]; then
                    # Jika gagal terbuka setelah beberapa detik, kembalikan ke STOPPED
                    start_time=$(get_timer "$pkg")
                    now=$(date +%s)
                    if [ $((now - start_time)) -gt 5 ]; then
                        set_state "$pkg" "STOPPED"
                    fi
                else
                    # Menunggu delay loading agar UI tidak rusak
                    start_time=$(get_timer "$pkg")
                    now=$(date +%s)
                    if [ $((now - start_time)) -ge "$LAUNCH_DELAY" ]; then
                        echo "[LIFECYCLE] $pkg selesai loading. Bersiap Resize."
                        set_state "$pkg" "RESIZING"
                    fi
                fi
                ;;
                
            "RESIZING")
                if [ -z "$pid" ]; then
                    set_state "$pkg" "STOPPED"
                else
                    # Tandai bahwa layout perlu diperbarui
                    NEEDS_LAYOUT=1
                    set_state "$pkg" "RUNNING"
                fi
                ;;
                
            "RUNNING")
                if [ -z "$pid" ]; then
                    echo "[WARN] Force Close terdeteksi pada $pkg!"
                    clear_app_cache "$pkg"
                    set_state "$pkg" "STOPPED"
                    NEEDS_LAYOUT=1 # Memicu penyesuaian layar untuk aplikasi yang tersisa
                fi
                ;;
        esac
    done

    # ── Logika Penataan Letak (Tiling) Dieksekusi Hanya Jika Perlu ──
    if [ "$NEEDS_LAYOUT" -eq 1 ]; then
        echo "[TILER] Menghitung ulang tata letak (Tiling)..."
        
        # Kumpulkan Task ID yang benar-benar aktif (RUNNING)
        ACTIVE_TIDS=""
        for pkg in $PACKAGES; do
            if [ "$(get_state "$pkg")" = "RUNNING" ]; then
                tid=$(dumpsys activity activities 2>/dev/null | grep ":${pkg} U=" | grep -o '#[0-9]*' | head -1 | tr -d '#')
                if [ -n "$tid" ]; then
                    ACTIVE_TIDS="$ACTIVE_TIDS $tid"
                fi
            fi
        done
        
        # Konversi string ke parameter $1, $2, dst
        set -- $ACTIVE_TIDS
        NUM_TASKS=$#
        
        if [ "$NUM_TASKS" -eq 1 ]; then
            am task resize "$1" 0 0 "$W" "$H" >/dev/null 2>&1
            echo "[TILER] Mode 1 Jendela diterapkan."
            
        elif [ "$NUM_TASKS" -eq 2 ]; then
            am task resize "$1" 0 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" 0 "$HALF_H" "$W" "$H" >/dev/null 2>&1
            echo "[TILER] Mode 2 Jendela (Atas-Bawah) diterapkan."
            
        elif [ "$NUM_TASKS" -eq 3 ]; then
            am task resize "$1" 0 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" 0 "$HALF_H" "$HALF_W" "$H" >/dev/null 2>&1
            am task resize "$3" "$HALF_W" "$HALF_H" "$W" "$H" >/dev/null 2>&1
            echo "[TILER] Mode 3 Jendela diterapkan."
            
        elif [ "$NUM_TASKS" -ge 4 ]; then
            am task resize "$1" 0 0 "$HALF_W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" "$HALF_W" 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$3" 0 "$HALF_H" "$HALF_W" "$H" >/dev/null 2>&1
            am task resize "$4" "$HALF_W" "$HALF_H" "$W" "$H" >/dev/null 2>&1
            echo "[TILER] Mode 4 Jendela diterapkan."
        fi
        
        NEEDS_LAYOUT=0 # Reset pemicu layout
    fi

    echo "--------------------------------------------------"
    sleep "$CHECK_INTERVAL"
done
