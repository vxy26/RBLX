#!/system/bin/sh

su -c "
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
"