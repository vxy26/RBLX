#!/system/bin/sh

PACKAGES="com.roblox.client com.roblox.client0"
ACTIVITY="com.roblox.client.ActivityProtocolLaunch"
VIP_LINK="https://www.roblox.com/share?code=ac5a31bf7737de46a02794815e5d13fa&type=Server"
CHECK_INTERVAL=3
LAUNCH_DELAY=12
NEEDS_LAYOUT=0

settings put global enable_freeform_support 1 2>/dev/null
settings put global force_resizable_activities 1 2>/dev/null

SCREEN_SIZE=$(wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1)
W=$(echo "$SCREEN_SIZE" | cut -dx -f1)
H=$(echo "$SCREEN_SIZE" | cut -dx -f2)
[ -z "$W" ] && W=1080
[ -z "$H" ] && H=2400
HALF_W=$((W / 2))
HALF_H=$((H / 2))

clear_app_cache() {
    local pkg="$1"
    rm -rf "/data/data/$pkg/cache/" 2>/dev/null
    rm -rf "/data/data/$pkg/code_cache/" 2>/dev/null
}

set_state() { eval "STATE_$(echo "$1" | tr '.' '_')=$2"; }
get_state() { eval "echo \$STATE_$(echo "$1" | tr '.' '_')"; }
set_timer() { eval "TIMER_$(echo "$1" | tr '.' '_')=$(date +%s)"; }
get_timer() { eval "echo \$TIMER_$(echo "$1" | tr '.' '_')"; }

for pkg in $PACKAGES; do
    set_state "$pkg" "STOPPED"
    set_timer "$pkg"
    am force-stop "$pkg" 2>/dev/null
done

while true; do
    DUMP_ACT=$(dumpsys activity activities 2>/dev/null)
    
    for pkg in $PACKAGES; do
        pid=$(pidof "$pkg" 2>/dev/null)
        state=$(get_state "$pkg")
        
        case "$state" in
            "STOPPED")
                if [ -n "$pid" ]; then
                    set_state "$pkg" "RESIZING"
                else
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
                    now=$(date +%s)
                    start_time=$(get_timer "$pkg")
                    [ $((now - start_time)) -gt 5 ] && set_state "$pkg" "STOPPED"
                else
                    now=$(date +%s)
                    start_time=$(get_timer "$pkg")
                    if [ $((now - start_time)) -ge "$LAUNCH_DELAY" ]; then
                        set_state "$pkg" "RESIZING"
                    fi
                fi
                ;;
            "RESIZING")
                if [ -z "$pid" ]; then
                    set_state "$pkg" "STOPPED"
                else
                    NEEDS_LAYOUT=1
                    set_state "$pkg" "RUNNING"
                fi
                ;;
            "RUNNING")
                if [ -z "$pid" ]; then
                    clear_app_cache "$pkg"
                    set_state "$pkg" "STOPPED"
                    NEEDS_LAYOUT=1
                fi
                ;;
        esac
    done

    if [ "$NEEDS_LAYOUT" -eq 1 ]; then
        ACTIVE_TIDS=""
        for pkg in $PACKAGES; do
            if [ "$(get_state "$pkg")" = "RUNNING" ]; then
                tid=$(echo "$DUMP_ACT" | grep "${pkg}" | grep -oE '(#|taskId=)[0-9]+' | head -1 | tr -d '#a-zA-Z=')
                if [ -n "$tid" ]; then
                    ACTIVE_TIDS="$ACTIVE_TIDS $tid"
                fi
            fi
        done
        
        set -- $ACTIVE_TIDS
        NUM_TASKS=$#
        
        if [ "$NUM_TASKS" -eq 1 ]; then
            am task resize "$1" 0 0 "$W" "$H" >/dev/null 2>&1
        elif [ "$NUM_TASKS" -eq 2 ]; then
            am task resize "$1" 0 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" 0 "$HALF_H" "$W" "$H" >/dev/null 2>&1
        elif [ "$NUM_TASKS" -eq 3 ]; then
            am task resize "$1" 0 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" 0 "$HALF_H" "$HALF_W" "$H" >/dev/null 2>&1
            am task resize "$3" "$HALF_W" "$HALF_H" "$W" "$H" >/dev/null 2>&1
        elif [ "$NUM_TASKS" -ge 4 ]; then
            am task resize "$1" 0 0 "$HALF_W" "$HALF_H" >/dev/null 2>&1
            am task resize "$2" "$HALF_W" 0 "$W" "$HALF_H" >/dev/null 2>&1
            am task resize "$3" 0 "$HALF_H" "$HALF_W" "$H" >/dev/null 2>&1
            am task resize "$4" "$HALF_W" "$HALF_H" "$W" "$H" >/dev/null 2>&1
        fi
        
        NEEDS_LAYOUT=0
    fi

    sleep "$CHECK_INTERVAL"
done