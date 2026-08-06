# vivado-container-suite -- synthesis / implementation / bitstream.
#
#   vivado -mode batch -source flow.tcl -tclargs <synth|impl|bitstream|all>
#
# Two flows are supported:
#   nonproject  checkpoint driven, no .xpr on disk.  Deterministic and the one
#               to use in CI.  This is the default.
#   project     drives an existing .xpr through launch_runs, for designs whose
#               source of truth is the IDE project.

source [file join $::env(VVD_CONTAINER_TCL) lib.tcl]

set stage [lindex $argv 0]
if {$stage eq ""} { set stage all }
if {[lsearch -exact {synth impl bitstream all} $stage] < 0} {
    vvd::fatal "unknown stage '$stage' (expected synth, impl, bitstream or all)"
}

set bd        [vvd::build_dir]
set synth_dcp [file join $bd post_synth.dcp]
set route_dcp [file join $bd post_route.dcp]
set flow_mode [vvd::env VVD_FLOW_MODE nonproject]

# ---------------------------------------------------------------------------
# non-project flow
# ---------------------------------------------------------------------------
proc vvd::np_synth {} {
    global synth_dcp
    vvd::info_ "synthesising [vvd::top] for [vvd::part]"
    vvd::source_hook VVD_PRE_TCL
    vvd::read_sources

    set args [list -top [vvd::top] -part [vvd::part]]
    set bp [vvd::env VVD_BOARD_PART]
    if {$bp ne ""} { set_property board_part $bp [current_project] }
    eval [list synth_design] $args [vvd::generic_args] [vvd::env VVD_SYNTH_ARGS]

    write_checkpoint -force $synth_dcp
    vvd::write_reports synth
    vvd::info_ "checkpoint: $synth_dcp"
}

proc vvd::np_load_synth {} {
    global synth_dcp
    if {[llength [get_designs -quiet]] > 0} { return }
    if {[file exists $synth_dcp]} {
        vvd::info_ "opening $synth_dcp"
        open_checkpoint $synth_dcp
    } else {
        vvd::np_synth
    }
}

proc vvd::np_impl {} {
    global route_dcp
    vvd::np_load_synth
    set directive [vvd::env VVD_IMPL_DIRECTIVE]

    vvd::info_ "opt_design"
    if {$directive ne ""} { opt_design -directive $directive } else { opt_design }

    vvd::info_ "place_design"
    if {$directive ne ""} { place_design -directive $directive } else { place_design }

    vvd::info_ "phys_opt_design"
    phys_opt_design

    vvd::info_ "route_design"
    if {$directive ne ""} { route_design -directive $directive } else { route_design }

    write_checkpoint -force $route_dcp
    vvd::write_reports impl
    vvd::check_timing impl
    vvd::info_ "checkpoint: $route_dcp"
}

proc vvd::np_load_route {} {
    global route_dcp
    # A routed design left in memory by np_impl in this same session is reused;
    # otherwise fall back to the checkpoint, and only then re-run implementation.
    if {[llength [get_designs -quiet]] > 0} { return }
    if {[file exists $route_dcp]} {
        vvd::info_ "opening $route_dcp"
        open_checkpoint $route_dcp
    } else {
        vvd::np_impl
    }
}

proc vvd::np_bitstream {} {
    global bd
    vvd::np_load_route
    set bit [file join $bd [vvd::top].bit]
    vvd::info_ "write_bitstream -> $bit"
    write_bitstream -force $bit
    # A probes file only exists when the design instantiates debug cores.
    if {[llength [get_debug_cores -quiet]] > 0} {
        write_debug_probes -force [file join $bd [vvd::top].ltx]
    }
    vvd::source_hook VVD_POST_TCL
    vvd::info_ "bitstream: $bit"
}

# ---------------------------------------------------------------------------
# project flow
# ---------------------------------------------------------------------------
proc vvd::pr_open {} {
    set xpr [vvd::env VVD_XPR]
    if {$xpr eq ""} { vvd::fatal "VVD_FLOW_MODE=project requires VVD_XPR" }
    if {![file exists $xpr]} { vvd::fatal "project not found: $xpr" }
    if {[current_project -quiet] eq ""} {
        vvd::info_ "open_project $xpr"
        open_project $xpr
    }
}

proc vvd::pr_run {run args} {
    vvd::pr_open
    set r [get_runs $run]
    if {[get_property PROGRESS $r] eq "100%" && [get_property NEEDS_REFRESH $r] == 0} {
        vvd::info_ "$run is already up to date"
        return
    }
    reset_run $r
    eval [list launch_runs $r -jobs [vvd::jobs]] $args
    wait_on_run $r
    if {[get_property PROGRESS $r] ne "100%"} {
        vvd::fatal "$run failed; see [get_property DIRECTORY $r]"
    }
}

proc vvd::pr_collect {} {
    global bd
    vvd::pr_open
    set impl [get_runs impl_1]
    set dir [get_property DIRECTORY $impl]
    foreach ext {bit ltx} {
        foreach f [glob -nocomplain [file join $dir *.$ext]] {
            file copy -force $f [file join $bd [file tail $f]]
            vvd::info_ "collected [file tail $f] -> $bd"
        }
    }
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
if {$flow_mode eq "project"} {
    switch -- $stage {
        synth     { vvd::pr_run synth_1 }
        impl      { vvd::pr_run synth_1; vvd::pr_run impl_1 }
        bitstream -
        all       { vvd::pr_run synth_1
                    vvd::pr_run impl_1 -to_step write_bitstream
                    vvd::pr_collect }
    }
} else {
    switch -- $stage {
        synth     { vvd::np_synth }
        impl      { vvd::np_impl }
        bitstream { vvd::np_bitstream }
        all       { vvd::np_synth; vvd::np_impl; vvd::np_bitstream }
    }
}

vvd::info_ "stage '$stage' complete"
