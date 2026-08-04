# vivado-container-suite -- shared Tcl helpers.
#
# Everything here reads its inputs from the environment, which is populated by
# the `vcs` CLI from vcs.conf.  Nothing hard-codes a path: the working directory
# inside the container is always the project root.

namespace eval vcs {
    variable build_dir
    variable state
    array set state {synth 0 impl 0 route 0}
}

proc vcs::env {name {default ""}} {
    global env
    if {[info exists env($name)] && [string length $env($name)] > 0} {
        return $env($name)
    }
    return $default
}

proc vcs::info_ {msg} { puts "vcs-tcl  ▸ $msg" }
proc vcs::warn {msg}  { puts "vcs-tcl  ! $msg" }
proc vcs::fatal {msg} {
    puts stderr "vcs-tcl  ✗ $msg"
    # Exit non-zero so the CLI, make and CI all see the failure.
    exit 1
}

proc vcs::build_dir {} {
    variable build_dir
    if {![info exists build_dir]} {
        set build_dir [vcs::env VCS_BUILD_DIR build]
        file mkdir $build_dir
        file mkdir [file join $build_dir logs]
        file mkdir [file join $build_dir reports]
    }
    return $build_dir
}

proc vcs::report_dir {} {
    set d [file join [vcs::build_dir] reports]
    file mkdir $d
    return $d
}

# Expand a whitespace-separated list of glob patterns into an ordered, unique
# file list.  Patterns that match nothing are an error -- a typo in vcs.conf
# should not silently produce an empty design.
proc vcs::expand {patterns {what "source"}} {
    set out {}
    foreach pat $patterns {
        if {$pat eq ""} { continue }
        set hits [lsort [glob -nocomplain -- $pat]]
        if {[llength $hits] == 0} {
            vcs::fatal "$what pattern matched no files: $pat (cwd: [pwd])"
        }
        foreach h $hits {
            if {[lsearch -exact $out $h] < 0} { lappend out $h }
        }
    }
    return $out
}

proc vcs::read_sources {} {
    set verilog [vcs::env VCS_SOURCES]
    set sv      [vcs::env VCS_SV_SOURCES]
    set vhdl    [vcs::env VCS_VHDL_SOURCES]
    set xdc     [vcs::env VCS_CONSTRAINTS]
    set ip      [vcs::env VCS_IP]
    set bd      [vcs::env VCS_BD]

    if {$verilog eq "" && $sv eq "" && $vhdl eq "" && $ip eq "" && $bd eq ""} {
        vcs::fatal "no sources configured; set VCS_SOURCES / VCS_SV_SOURCES / VCS_VHDL_SOURCES in vcs.conf"
    }

    set incdirs [vcs::env VCS_INCLUDE_DIRS]

    if {$verilog ne ""} {
        set files [vcs::expand $verilog "Verilog source"]
        vcs::info_ "read_verilog: [llength $files] file(s)"
        read_verilog $files
    }
    if {$sv ne ""} {
        set files [vcs::expand $sv "SystemVerilog source"]
        vcs::info_ "read_verilog -sv: [llength $files] file(s)"
        read_verilog -sv $files
    }
    if {$vhdl ne ""} {
        set files [vcs::expand $vhdl "VHDL source"]
        vcs::info_ "read_vhdl: [llength $files] file(s)"
        read_vhdl $files
    }
    if {$ip ne ""} {
        set files [vcs::expand $ip "IP"]
        vcs::info_ "read_ip: [llength $files] file(s)"
        read_ip $files
        foreach f $files {
            if {[get_property IS_LOCKED [get_files $f]] eq "1"} {
                vcs::warn "IP is locked and may need upgrading: $f"
            }
        }
        generate_target all [get_ips]
        synth_ip [get_ips]
    }
    if {$bd ne ""} {
        set files [vcs::expand $bd "block design"]
        foreach f $files {
            vcs::info_ "read_bd: $f"
            read_bd $f
            generate_target all [get_files $f]
        }
    }
    if {$xdc ne ""} {
        set files [vcs::expand $xdc "constraint"]
        vcs::info_ "read_xdc: [llength $files] file(s)"
        read_xdc $files
    }
    if {$incdirs ne ""} {
        set_property include_dirs $incdirs [current_fileset]
    }
}

proc vcs::part {} {
    set p [vcs::env VCS_PART]
    if {$p eq ""} { vcs::fatal "VCS_PART is not set" }
    return $p
}

proc vcs::top {} {
    set t [vcs::env VCS_TOP]
    if {$t eq ""} { vcs::fatal "VCS_TOP is not set" }
    return $t
}

# Generics/parameters, given as "NAME=VALUE NAME2=VALUE2".
proc vcs::generic_args {} {
    set g [vcs::env VCS_GENERICS]
    if {$g eq ""} { return {} }
    return [list -generic $g]
}

proc vcs::source_hook {var} {
    set script [vcs::env $var]
    if {$script eq ""} { return }
    if {![file exists $script]} { vcs::fatal "$var points at a missing file: $script" }
    vcs::info_ "sourcing $var: $script"
    source $script
}

# Fail the build when timing is not met.  Vivado itself exits 0 on a design
# that misses timing, which is the wrong default for CI.
proc vcs::check_timing {{stage impl}} {
    set wns [get_property SLACK [get_timing_paths -delay_type max]]
    set whs [get_property SLACK [get_timing_paths -delay_type min]]
    vcs::info_ "$stage timing: WNS=$wns WHS=$whs"
    if {[vcs::env VCS_ALLOW_TIMING_VIOLATION 0] eq "1"} { return }
    set bad 0
    if {$wns ne "" && $wns < 0} { vcs::warn "setup violated (WNS=$wns)"; set bad 1 }
    if {$whs ne "" && $whs < 0} { vcs::warn "hold violated (WHS=$whs)";  set bad 1 }
    if {$bad} {
        vcs::fatal "timing not met. Set VCS_ALLOW_TIMING_VIOLATION=1 to continue anyway."
    }
}

proc vcs::write_reports {stage} {
    set d [vcs::report_dir]
    report_utilization    -file [file join $d ${stage}_utilization.rpt]
    report_timing_summary -file [file join $d ${stage}_timing.rpt] -warn_on_violation
    if {$stage ne "synth"} {
        report_drc        -file [file join $d ${stage}_drc.rpt]
        report_power      -file [file join $d ${stage}_power.rpt]
        report_io         -file [file join $d ${stage}_io.rpt]
    }
    vcs::info_ "reports written to $d"
}

proc vcs::jobs {} {
    set j [vcs::env VCS_JOBS 4]
    if {![string is integer -strict $j] || $j < 1} { set j 4 }
    return $j
}
