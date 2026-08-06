# vivado-container-suite -- shared Tcl helpers.
#
# Everything here reads its inputs from the environment, which is populated by
# the `vvd` CLI from vvd.conf.  Nothing hard-codes a path: the working directory
# inside the container is always the project root.

namespace eval vvd {
    variable build_dir
    variable state
    array set state {synth 0 impl 0 route 0}
}

proc vvd::env {name {default ""}} {
    global env
    if {[info exists env($name)] && [string length $env($name)] > 0} {
        return $env($name)
    }
    return $default
}

proc vvd::info_ {msg} { puts "vvd-tcl  ▸ $msg" }
proc vvd::warn {msg}  { puts "vvd-tcl  ! $msg" }
proc vvd::fatal {msg} {
    puts stderr "vvd-tcl  ✗ $msg"
    # Exit non-zero so the CLI, make and CI all see the failure.
    exit 1
}

proc vvd::build_dir {} {
    variable build_dir
    if {![info exists build_dir]} {
        set build_dir [vvd::env VVD_BUILD_DIR build]
        file mkdir $build_dir
        file mkdir [file join $build_dir logs]
        file mkdir [file join $build_dir reports]
    }
    return $build_dir
}

proc vvd::report_dir {} {
    set d [file join [vvd::build_dir] reports]
    file mkdir $d
    return $d
}

# Expand a whitespace-separated list of glob patterns into an ordered, unique
# file list.  Patterns that match nothing are an error -- a typo in vvd.conf
# should not silently produce an empty design.
proc vvd::expand {patterns {what "source"}} {
    set out {}
    foreach pat $patterns {
        if {$pat eq ""} { continue }
        set hits [lsort [glob -nocomplain -- $pat]]
        if {[llength $hits] == 0} {
            vvd::fatal "$what pattern matched no files: $pat (cwd: [pwd])"
        }
        foreach h $hits {
            if {[lsearch -exact $out $h] < 0} { lappend out $h }
        }
    }
    return $out
}

proc vvd::read_sources {} {
    set verilog [vvd::env VVD_SOURCES]
    set sv      [vvd::env VVD_SV_SOURCES]
    set vhdl    [vvd::env VVD_VHDL_SOURCES]
    set xdc     [vvd::env VVD_CONSTRAINTS]
    set ip      [vvd::env VVD_IP]
    set bd      [vvd::env VVD_BD]

    if {$verilog eq "" && $sv eq "" && $vhdl eq "" && $ip eq "" && $bd eq ""} {
        vvd::fatal "no sources configured; set VVD_SOURCES / VVD_SV_SOURCES / VVD_VHDL_SOURCES in vvd.conf"
    }

    set incdirs [vvd::env VVD_INCLUDE_DIRS]

    if {$verilog ne ""} {
        set files [vvd::expand $verilog "Verilog source"]
        vvd::info_ "read_verilog: [llength $files] file(s)"
        read_verilog $files
    }
    if {$sv ne ""} {
        set files [vvd::expand $sv "SystemVerilog source"]
        vvd::info_ "read_verilog -sv: [llength $files] file(s)"
        read_verilog -sv $files
    }
    if {$vhdl ne ""} {
        set files [vvd::expand $vhdl "VHDL source"]
        vvd::info_ "read_vhdl: [llength $files] file(s)"
        read_vhdl $files
    }
    if {$ip ne ""} {
        set files [vvd::expand $ip "IP"]
        vvd::info_ "read_ip: [llength $files] file(s)"
        read_ip $files
        foreach f $files {
            if {[get_property IS_LOCKED [get_files $f]] eq "1"} {
                vvd::warn "IP is locked and may need upgrading: $f"
            }
        }
        generate_target all [get_ips]
        synth_ip [get_ips]
    }
    if {$bd ne ""} {
        set files [vvd::expand $bd "block design"]
        foreach f $files {
            vvd::info_ "read_bd: $f"
            read_bd $f
            generate_target all [get_files $f]
        }
    }
    if {$xdc ne ""} {
        set files [vvd::expand $xdc "constraint"]
        vvd::info_ "read_xdc: [llength $files] file(s)"
        read_xdc $files
    }
    if {$incdirs ne ""} {
        set_property include_dirs $incdirs [current_fileset]
    }
}

proc vvd::part {} {
    set p [vvd::env VVD_PART]
    if {$p eq ""} { vvd::fatal "VVD_PART is not set" }
    return $p
}

proc vvd::top {} {
    set t [vvd::env VVD_TOP]
    if {$t eq ""} { vvd::fatal "VVD_TOP is not set" }
    return $t
}

# Generics/parameters, given as "NAME=VALUE NAME2=VALUE2".
proc vvd::generic_args {} {
    set g [vvd::env VVD_GENERICS]
    if {$g eq ""} { return {} }
    return [list -generic $g]
}

proc vvd::source_hook {var} {
    set script [vvd::env $var]
    if {$script eq ""} { return }
    if {![file exists $script]} { vvd::fatal "$var points at a missing file: $script" }
    vvd::info_ "sourcing $var: $script"
    source $script
}

# Fail the build when timing is not met.  Vivado itself exits 0 on a design
# that misses timing, which is the wrong default for CI.
proc vvd::check_timing {{stage impl}} {
    set wns [get_property SLACK [get_timing_paths -delay_type max]]
    set whs [get_property SLACK [get_timing_paths -delay_type min]]
    vvd::info_ "$stage timing: WNS=$wns WHS=$whs"
    if {[vvd::env VVD_ALLOW_TIMING_VIOLATION 0] eq "1"} { return }
    set bad 0
    if {$wns ne "" && $wns < 0} { vvd::warn "setup violated (WNS=$wns)"; set bad 1 }
    if {$whs ne "" && $whs < 0} { vvd::warn "hold violated (WHS=$whs)";  set bad 1 }
    if {$bad} {
        vvd::fatal "timing not met. Set VVD_ALLOW_TIMING_VIOLATION=1 to continue anyway."
    }
}

proc vvd::write_reports {stage} {
    set d [vvd::report_dir]
    report_utilization    -file [file join $d ${stage}_utilization.rpt]
    report_timing_summary -file [file join $d ${stage}_timing.rpt] -warn_on_violation
    if {$stage ne "synth"} {
        report_drc        -file [file join $d ${stage}_drc.rpt]
        report_power      -file [file join $d ${stage}_power.rpt]
        report_io         -file [file join $d ${stage}_io.rpt]
    }
    vvd::info_ "reports written to $d"
}

proc vvd::jobs {} {
    set j [vvd::env VVD_JOBS 4]
    if {![string is integer -strict $j] || $j < 1} { set j 4 }
    return $j
}
