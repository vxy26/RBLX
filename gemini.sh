#!/system/bin/sh

# ==============================================================================
# ROBLOX MULTI-INSTANCE DAEMON - REWRITTEN & STABILIZED
# Mengadaptasi logika deep cache, Cgroups, IO priority, dan Network Watchdog
# ==============================================================================

LOG_FILE="/data/local/tmp/roblox_daemon.log"
STATE_DIR="/data/local/tmp/roblox_states"
PID_CACHE_DIR="/data/local/tmp/roblox_pids"
LOGCAT_CACHE="${STATE_DIR}/logcat_cache.tmp"

PACKAGES="com.roblox.client com.roblox.client0 com.roblox.client1 com.roblox.client2 com.roblox.client3 com.roblox.client4 com.roblox.client5 com.roblox.client6"
ACTIVITY="com.roblox.client.ActivityProtocolLaunch"
DEFAULT_URL="https://www.roblox.com/share?code=ac5a31bf7737de46a02794815e5d13fa&type=Server"

CHECK_INTERVAL=3
LAUNCH_DELAY=20
RESTART_COOLDOWN=60
STAGGER_DELAY_PER_PKG=8
ORIENTATION_CHECK_INTERVAL=10
HWCOMPOSER_GUARD_DELAY=3

HEALTH_CHECK_INTERVAL=300
LOGCAT_REFRESH_INTERVAL=60
RAM_CRITICAL_MB=200
THERMAL_WARN=70
THERMAL_CRIT=80
CPU_NICE_VALUE=-10
OOM_SCORE_VALUE=-200

get_ps_url() {
    case "$1" in
        "com.roblox.client")  echo "https://www.roblox.com/share?code=72f8ab334c55614aba4fbd7c57ef65ff&type=Server" ;; 
        "com.roblox.client0") echo "https://www.roblox.com/share?code=dbf1277d07e5ed4aae5db5f2e460f307&type=Server" ;; 
        "com.roblox.client1") echo "https://www.roblox.com/share?code=94b2b2cf24b2f140b9f90df11153e631&type=Server" ;; 
        "com.roblox.client2") echo "https://www.roblox.com/share?code=9f7152152ab7bb418d66c3c807be99d2&type=Server" ;; 
        "com.roblox.client3") echo "https://www.roblox.com/share?code=012cf985ad5b2441b8cde5398f5ace1e&type=Server" ;; 
        "com.roblox.client4") echo "https://www.roblox.com/share?code=dbf1277d07e5ed4aae5db5f2e460f307&type=Server" ;; 
        "com.roblox.client5") echo "https://www.roblox.com/share?code=7b872856ceea8c4f81759f5216721f61&type=Server" ;; 
        "com.roblox.client6") echo "https://www.roblox.com/share?code=d4b3cf2fe1c4874aa2fc534638c8d5e9&type=Server" ;; 
        *)                    echo "$DEFAULT_URL" ;;
    esac
}

# Inisialisasi Direktori
mkdir -p "$PID_CACHE_DIR" "$STATE_DIR"

if ! mount | grep -q "$STATE_DIR"; then
    if ! mount -t tmpfs -o size=5M tmpfs "$STATE_DIR" 2>/dev/null; then
        rm -f "$STATE_DIR"/*.state "$STATE_DIR"/*.timer "$STATE_DIR"/*.restart 2>/dev/null
    fi
fi

mount -o remount,rw /proc/sys 2>/dev/null || mount -o remount,rw /proc 2>/dev/null

# Log System
log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    local size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 2000000 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SYS] Log rotated." > "$LOG_FILE"
    fi
}

# State Management
set_state()        { echo "$2" > "${STATE_DIR}/$1.state";   }
get_state()        { cat "${STATE_DIR}/$1.state"   2>/dev/null || echo "STOPPED"; }
set_timer()        { date +%s  > "${STATE_DIR}/$1.timer";   }
get_timer()        { cat "${STATE_DIR}/$1.timer"   2>/dev/null || echo "0"; }
set_restart_time() { date +%s  > "${STATE_DIR}/$1.restart"; }
get_restart_time() { cat "${STATE_DIR}/$1.restart" 2>/dev/null || echo "0"; }

get_pid() {
    local pkg="$1"
    local cache="${PID_CACHE_DIR}/${pkg}.pid"
    local cached_pid=$(cat "$cache" 2>/dev/null)

    if [ -n "$cached_pid" ] && [ -d "/proc/$cached_pid" ]; then
        echo "$cached_pid"
        return
    fi

    local new_pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
    if [ -n "$new_pid" ]; then
        echo "$new_pid" > "$cache"
    else
        rm -f "$cache"
    fi
    echo "$new_pid"
}

invalidate_pid() { rm -f "${PID_CACHE_DIR}/$1.pid" 2>/dev/null; }

get_pkg_index() {
    local target="$1" idx=0
    for pkg in $PACKAGES; do
        [ "$pkg" = "$target" ] && echo "$idx" && return
        idx=$(( idx + 1 ))
    done
    echo "0"
}

# ==============================================================================
# OPTIMASI STABILITAS LOGIKA YURXZ
# ==============================================================================

clear_deep_caches() {
    local pkg="$1"
    rm -rf "/data/data/$pkg/cache/*" 2>/dev/null
    rm -rf "/data/data/$pkg/code_cache/*" 2>/dev/null
    rm -rf "/sdcard/Android/data/$pkg/cache/*" 2>/dev/null
    rm -rf "/data/data/$pkg/app_webview/Default/GPUCache/*" 2>/dev/null
    rm -rf "/data/data/$pkg/files/logs/*" 2>/dev/null
    rm -rf "/data/data/$pkg/files/shaders/*" 2>/dev/null
}

force_low_quality() {
    local pkg="$1"
    local prefs_dir="/data/data/$pkg/shared_prefs"
    for gfile in "$prefs_dir"/GlobalSettings*.xml; do
        [ -f "$gfile" ] || continue
        sed -i 's|name="QualityLevel" value="[^"]*"|name="QualityLevel" value="1"|g' "$gfile" 2>/dev/null
        sed -i 's|name="SavedQualityLevel" value="[^"]*"|name="SavedQualityLevel" value="1"|g' "$gfile" 2>/dev/null
    done
}

apply_process_limits() {
    local pkg="$1"
    local pid="$2"

    renice "$CPU_NICE_VALUE" -p "$pid" 2>/dev/null
    ionice -c 2 -n 0 -p "$pid" 2>/dev/null
    echo "$OOM_SCORE_VALUE" > "/proc/$pid/oom_score_adj" 2>/dev/null

    local cg="/dev/memcg/$pkg"
    mkdir -p "$cg" 2>/dev/null
    echo "$pid" > "$cg/cgroup.procs" 2>/dev/null
    echo 629145600 > "$cg/memory.limit_in_bytes" 2>/dev/null
    echo 524288000 > "$cg/memory.soft_limit_in_bytes" 2>/dev/null
}

anti_minimize() {
    local pkg="$1"
    am start -n "${pkg}/com.roblox.client.ActivityNativeMain" >/dev/null 2>&1
}

mute_device() {
    media volume --stream 3 --set 0 2>/dev/null || true
}

# ==============================================================================
# WINDOW TILING LOGIC
# ==============================================================================

W=""
H=""
ROT=""
NEEDS_LAYOUT=0

read_screen_size() {
    local raw=$(dumpsys window displays 2>/dev/null | grep -oE 'app=[0-9]+x[0-9]+' | head -1 | cut -d= -f2)
    local new_w=$(echo "$raw" | cut -dx -f1)
    local new_h=$(echo "$raw" | cut -dx -f2)
    local new_rot=$(settings get system user_rotation 2>/dev/null || echo 0)

    if [ -z "$new_w" ] || [ -z "$new_h" ]; then return; fi
    if [ -z "$W" ]; then W=$new_w; H=$new_h; ROT=$new_rot; return; fi
    if [ "$new_w" = "$W" ] && [ "$new_h" = "$H" ] && [ "$new_rot" = "$ROT" ]; then return; fi

    W=$new_w; H=$new_h; ROT=$new_rot
    NEEDS_LAYOUT=1
}

read_screen_size
[ -z "$W" ] && W=1080
[ -z "$H" ] && H=2320

get_pkg_coords() {
    local target="$1"
    local idx=$(get_pkg_index "$target")
    local total=0
    for _ in $PACKAGES; do total=$((total + 1)); done

    local cols rows
    if   [ "$total" -le 1 ]; then cols=1; rows=1
    elif [ "$total" -le 2 ]; then cols=1; rows=2
    elif [ "$total" -le 4 ]; then cols=2; rows=2
    elif [ "$total" -le 6 ]; then cols=2; rows=3
    else                          cols=2; rows=4
    fi

    local cell_w=$(( W / cols ))
    local cell_h=$(( H / rows ))

    echo "$(( (idx % cols) * cell_w )) $(( (idx / cols) * cell_h )) $(( ((idx % cols) * cell_w) + cell_w )) $(( ((idx / cols) * cell_h) + cell_h ))"
}

apply_xml_tiling() {
    local pkg="$1" x1="$2" y1="$3" x2="$4" y2="$5"
    local xml="/data/data/$pkg/shared_prefs/${pkg}_preferences.xml"

    [ ! -f "$xml" ] && return 0

    local cl=$(awk -F'"' '/app_cloner_current_window_left/{print $4}'   "$xml")
    local ct=$(awk -F'"' '/app_cloner_current_window_top/{print $4}'    "$xml")
    local cr=$(awk -F'"' '/app_cloner_current_window_right/{print $4}'  "$xml")
    local cb=$(awk -F'"' '/app_cloner_current_window_bottom/{print $4}' "$xml")

    if [ "$cl" = "$x1" ] && [ "$ct" = "$y1" ] && [ "$cr" = "$x2" ] && [ "$cb" = "$y2" ]; then return 0; fi

    am force-stop "$pkg" 2>/dev/null
    invalidate_pid "$pkg"
    sleep "$HWCOMPOSER_GUARD_DELAY"

    sed "s/<int name=\"app_cloner_current_window_left\" value=\"[^\"]*\" \/>/<int name=\"app_cloner_current_window_left\" value=\"$x1\" \/>/g;
         s/<int name=\"app_cloner_current_window_top\" value=\"[^\"]*\" \/>/<int name=\"app_cloner_current_window_top\" value=\"$y1\" \/>/g;
         s/<int name=\"app_cloner_current_window_right\" value=\"[^\"]*\" \/>/<int name=\"app_cloner_current_window_right\" value=\"$x2\" \/>/g;
         s/<int name=\"app_cloner_current_window_bottom\" value=\"[^\"]*\" \/>/<int name=\"app_cloner_current_window_bottom\" value=\"$y2\" \/>/g" \
        "$xml" > "${xml}.tmp"

    if [ -s "${xml}.tmp" ]; then
        cat "${xml}.tmp" > "$xml"
        rm -f "${xml}.tmp"
        return 1
    else
        rm -f "${xml}.tmp"
        return 0
    fi
}

run_layout_update() {
    for pkg in $PACKAGES; do
        local coords=$(get_pkg_coords "$pkg")
        apply_xml_tiling "$pkg" $(echo "$coords" | awk '{print $1}') $(echo "$coords" | awk '{print $2}') $(echo "$coords" | awk '{print $3}') $(echo "$coords" | awk '{print $4}')
        if [ "$?" -eq 1 ]; then
            set_state "$pkg" "STOPPED"
            set_restart_time "$pkg"
        fi
    done
}

# ==============================================================================
# MONITORING KESEHATAN DAN WATCHDOG
# ==============================================================================

LAST_LOGCAT_REFRESH=0
LOGCAT_BG_PID=""

refresh_logcat_cache() {
    local now="$1"
    if [ -n "$LOGCAT_BG_PID" ] && ! kill -0 "$LOGCAT_BG_PID" 2>/dev/null; then
        [ -s "${LOGCAT_CACHE}.new" ] && mv "${LOGCAT_CACHE}.new" "$LOGCAT_CACHE"
        LOGCAT_BG_PID=""
    fi

    if [ $(( now - LAST_LOGCAT_REFRESH )) -ge "$LOGCAT_REFRESH_INTERVAL" ] && [ -z "$LOGCAT_BG_PID" ]; then
        logcat -d -t 200 2>/dev/null > "${LOGCAT_CACHE}.new" &
        LOGCAT_BG_PID=$!
        LAST_LOGCAT_REFRESH=$now
    fi
}

throttle_cpu() {
    for cpufreq in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -d "$cpufreq" ] || continue
        local gov="$cpufreq/scaling_governor"
        local max_f="$cpufreq/scaling_max_freq"
        local cap=$(cat "$cpufreq/cpuinfo_max_freq" 2>/dev/null)
        
        if [ -w "$gov" ]; then
            case "$1" in
                "crit")   echo "powersave"    > "$gov" 2>/dev/null ;;
                "warn")   echo "conservative" > "$gov" 2>/dev/null ;;
                "normal") echo "schedutil"    > "$gov" 2>/dev/null ;;
            esac
        fi
        if [ -w "$max_f" ] && [ -n "$cap" ]; then
            case "$1" in
                "crit")   echo $(( cap / 2 ))          > "$max_f" 2>/dev/null ;;
                "warn")   echo $(( cap * 75 / 100 ))   > "$max_f" 2>/dev/null ;;
                "normal") echo "$cap"                  > "$max_f" 2>/dev/null ;;
            esac
        fi
    done
}

scheduled_health_check() {
    local thermal_file="/sys/class/thermal/thermal_zone0/temp"
    if [ -f "$thermal_file" ]; then
        local temp_c=$(( $(cat "$thermal_file" 2>/dev/null || echo 0) / 1000 ))
        if   [ "$temp_c" -gt "$THERMAL_CRIT" ]; then throttle_cpu "crit"
        elif [ "$temp_c" -gt "$THERMAL_WARN" ]; then throttle_cpu "warn"
        else                                         throttle_cpu "normal"
        fi
    fi

    local mem_avail_mb=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 ))
    for pkg in $PACKAGES; do
        local pid=$(get_pid "$pkg")
        [ -z "$pid" ] && continue
        
        anti_minimize "$pkg"
        apply_process_limits "$pkg" "$pid"

        local rss_kb=$(grep VmRSS "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
        if [ -n "$rss_kb" ]; then
            if [ "$mem_avail_mb" -lt "$RAM_CRITICAL_MB" ] || [ "$rss_kb" -gt 800000 ]; then
                am send-trim-memory "$pkg" COMPLETE >/dev/null 2>&1
            else
                am send-trim-memory "$pkg" MODERATE >/dev/null 2>&1
            fi
        fi
    done
}

watchdog_check() {
    local now_time=$(date +%s)
    
    for pkg in $PACKAGES; do
        [ "$(get_state "$pkg")" != "RUNNING" ] && continue
        local pid=$(get_pid "$pkg")
        [ -z "$pid" ] && continue

        local trigger_restart=0
        local reason=""

        # 1. Pengecekan Logcat
        if [ -f "$LOGCAT_CACHE" ]; then
            if grep -qEi "(ActivityManager.*error 277.*$pkg|$pkg/.*error 277|ANR in $pkg|Fatal signal [0-9]+ \(.*\).*pid $pid)" "$LOGCAT_CACHE" 2>/dev/null; then
                trigger_restart=1
                reason="Logcat Error/ANR"
            fi
        fi

        # 2. Pengecekan Jaringan
        local start_time=$(get_timer "$pkg")
        if [ "$trigger_restart" -eq 0 ] && [ $(( now_time - start_time )) -gt 90 ]; then
            local net_active=$(netstat -tunp 2>/dev/null | grep "$pid" | grep -c "ESTABLISHED")
            if [ "$net_active" -eq 0 ]; then
                trigger_restart=1
                reason="Silent Disconnect"
            fi
        fi

        # Eksekusi Restart
        if [ "$trigger_restart" -eq 1 ]; then
            log_msg "[WATCHDOG] $pkg terdeteksi mati: $reason. Restarting..."
            am force-stop "$pkg" 2>/dev/null
            invalidate_pid "$pkg"
            set_state "$pkg" "STOPPED"
            set_restart_time "$pkg"
        fi
    done
}

# ==============================================================================
# MAIN DAEMON LOOP
# ==============================================================================

log_msg "Daemon mulai - Menggunakan logika YURXZ (No Discord)"
mute_device

LAST_ORIENTATION_CHECK=0
LAST_HEALTH_CHECK=0

run_layout_update

while true; do
    NOW=$(date +%s)
    refresh_logcat_cache "$NOW"

    if [ $(( NOW - LAST_ORIENTATION_CHECK )) -ge "$ORIENTATION_CHECK_INTERVAL" ]; then
        read_screen_size
        if [ "$NEEDS_LAYOUT" -eq 1 ]; then
            run_layout_update
            NEEDS_LAYOUT=0
        fi
        LAST_ORIENTATION_CHECK=$NOW
    fi

    if [ $(( NOW - LAST_HEALTH_CHECK )) -ge "$HEALTH_CHECK_INTERVAL" ]; then
        scheduled_health_check
        watchdog_check
        LAST_HEALTH_CHECK=$NOW
    fi

    for pkg in $PACKAGES; do
        pid=$(get_pid "$pkg")
        state=$(get_state "$pkg")

        case "$state" in
            "STOPPED")
                last=$(get_restart_time "$pkg")
                if [ -n "$pid" ] && [ "$last" -eq 0 ]; then
                    set_state "$pkg" "RUNNING"
                else
                    idx=$(get_pkg_index "$pkg")
                    stagger=$(( idx * STAGGER_DELAY_PER_PKG ))
                    
                    if [ "$last" -gt 0 ] && [ $(( NOW - last )) -lt "$RESTART_COOLDOWN" ]; then continue; fi
                    if [ $(( NOW - last )) -lt "$stagger" ]; then continue; fi

                    am force-stop "$pkg" 2>/dev/null
                    
                    clear_deep_caches "$pkg"
                    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                    invalidate_pid "$pkg"
                    sleep 1
                    
                    force_low_quality "$pkg"

                    coords=$(get_pkg_coords "$pkg")
                    apply_xml_tiling "$pkg" $(echo "$coords" | awk '{print $1}') $(echo "$coords" | awk '{print $2}') $(echo "$coords" | awk '{print $3}') $(echo "$coords" | awk '{print $4}')

                    am start -n "${pkg}/${ACTIVITY}" -a android.intent.action.VIEW -d "$(get_ps_url "$pkg")" --activity-clear-top --activity-single-top >/dev/null 2>&1
                    
                    set_state "$pkg" "LAUNCHING"
                    set_timer "$pkg"
                fi
                ;;

            "LAUNCHING")
                if [ -z "$pid" ]; then
                    if [ $(( NOW - $(get_timer "$pkg") )) -gt 15 ]; then
                        set_state "$pkg" "STOPPED"
                        set_restart_time "$pkg"
                    fi
                else
                    if [ $(( NOW - $(get_timer "$pkg") )) -ge "$LAUNCH_DELAY" ]; then
                        set_state "$pkg" "RUNNING"
                        
                        apply_process_limits "$pkg" "$pid"
                    fi
                fi
                ;;

            "RUNNING")
                if [ -z "$pid" ]; then
                    set_state "$pkg" "STOPPED"
                    set_restart_time "$pkg"
                fi
                ;;
        esac
    done

    sleep "$CHECK_INTERVAL"
done