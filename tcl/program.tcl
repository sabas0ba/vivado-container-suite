# vivado-container-suite -- JTAG programming.
#
# The hw_server URL comes from VVD_HW_SERVER_URL, which the CLI sets according
# to --jtag:  TCP:host.docker.internal:3121 (host mode), TCP:localhost:3121
# (usb passthrough) or TCP:<host>:<port> (remote mode).

source [file join $::env(VVD_CONTAINER_TCL) lib.tcl]

set url [vvd::env VVD_HW_SERVER_URL]
if {$url eq ""} { vvd::fatal "VVD_HW_SERVER_URL is empty; JTAG is disabled" }

vvd::info_ "connecting to $url"
open_hw_manager
if {[catch {connect_hw_server -url $url -allow_non_jtag} err]} {
    vvd::fatal "cannot reach hw_server at $url\n  $err\n\
  host mode : start hw_server on the host, or run 'vvd hw-server'\n\
  usb  mode : check 'vvd jtag-rules --list' and 'vvd doctor'"
}

set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} {
    disconnect_hw_server
    vvd::fatal "hw_server is up but no JTAG target is attached.\n\
  Check the cable, the board power, and the udev rules ('vvd jtag-rules --print')."
}

vvd::info_ "targets: $targets"
current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices]
vvd::info_ "devices: $devices"

if {[vvd::env VVD_PROGRAM_LIST 0] eq "1"} {
    foreach d $devices {
        puts [format "  %-24s idcode=%s" $d [get_property IDCODE $d]]
    }
    close_hw_target
    disconnect_hw_server
    return
}

# Pick the device: an explicit --target pattern, else the only one present.
set want [vvd::env VVD_PROGRAM_TARGET]
if {$want ne ""} {
    set matched [lsearch -all -inline -glob $devices *$want*]
    if {[llength $matched] != 1} {
        vvd::fatal "--target '$want' matched [llength $matched] device(s) in: $devices"
    }
    set dev [lindex $matched 0]
} elseif {[llength $devices] == 1} {
    set dev [lindex $devices 0]
} else {
    vvd::fatal "the scan chain has [llength $devices] devices; choose one with --target\n  $devices"
}

set bit [vvd::env VVD_PROGRAM_BIT]
if {![file exists $bit]} { vvd::fatal "bitstream not found in the container: $bit" }

current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev

set probes [vvd::env VVD_PROGRAM_PROBES]
if {$probes ne ""} {
    if {![file exists $probes]} { vvd::fatal "probes file not found: $probes" }
    set_property PROBES.FILE $probes $dev
    set_property FULL_PROBES.FILE $probes $dev
}

vvd::info_ "programming $dev with [file tail $bit]"
program_hw_devices $dev
refresh_hw_device $dev

set done [get_property REGISTER.IR.BIT5_DONE $dev]
if {$done ne "" && $done ne "1"} {
    vvd::warn "DONE is not asserted after programming (value: $done)"
}

close_hw_target
disconnect_hw_server
vvd::info_ "programmed"
