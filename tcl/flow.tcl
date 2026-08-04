# vivado-container-suite -- synthesis / implementation / bitstream.
#
#   vivado -mode batch -source flow.tcl -tclargs <synth|impl|bitstream|all>
#
# Two flows are supported:
#   nonproject  checkpoint driven, no .xpr on disk.  Deterministic and the one
#               to use in CI.  This is the default.
#   project     drives an existing .xpr through launch_runs, for designs whose
#               source of truth is the IDE project.

source [file join $::env(VCS_CONTAINER_TCL) lib.tcl]

set stage [lindex $argv 0]
if {$stage eq ""} { set stage all }
if {[lsearch -exact {synth impl bitstream all} $stage] < 0} {
    vcs::fatal "unknown stage '$stage' (expected synth, impl, bitstream or all)"
}

set bd        [vcs::build_dir]
set synth_dcp [file join $bd post_synth.dcp]
set route_dcp [file join $bd post_route.dcp]
set flow_mode [vcs::env VCS_FLOW_MODE nonproject]

# ---------------------------------------------------------------------------
# non-project flow
# ---------------------------------------------------------------------------
proc vcs::np_synth {} {
    global synth_dcp
    vcs::info_ "synthesising [vcs::top] for [vcs::part]"
    vcs::source_hook VCS_PRE_TCL
    vcs::read_sources

    set args [list -top [vcs::top] -part [vcs::part]]
    set bp [vcs::env VCS_BOARD_PART]
    if {$bp ne ""} { set_property board_part $bp [current_project] }
    eval [list synth_design] $args [vcs::generic_args] [vcs::env VCS_SYNTH_ARGS]

    write_checkpoint -force $synth_dcp
    vcs::write_reports synth
    vcs::info_ "checkpoint: $synth_dcp"
}

proc vcs::np_load_synth {} {
    global synth_dcp
    if {[llength [get_designs -quiet]] > 0} { return }
    if {[file exists $synth_dcp]} {
        vcs::info_ "opening $synth_dcp"
        open_checkpoint $synth_dcp
    } else {
        vcs::np_synth
    }
}

proc vcs::np_impl {} {
    global route_dcp
    vcs::np_load_synth
    set directive [vcs::env VCS_IMPL_DIRECTIVE]

    vcs::info_ "opt_design"
    if {$directive ne ""} { opt_design -directive $directive } else { opt_design }

    vcs::info_ "place_design"
    if {$directive ne ""} { place_design -directive $directive } else { place_design }

    vcs::info_ "phys_opt_design"
    phys_opt_design

    vcs::info_ "route_design"
    if {$directive ne ""} { route_design -directive $directive } else { route_design }

    write_checkpoint -force $route_dcp
    vcs::write_reports impl
    vcs::check_timing impl
    vcs::info_ "checkpoint: $route_dcp"
}

proc vcs::np_load_route {} {
    global route_dcp
    # A routed design left in memory by np_impl in this same session is reused;
    # otherwise fall back to the checkpoint, and only then re-run implementation.
    if {[llength [get_designs -quiet]] > 0} { return }
    if {[file exists $route_dcp]} {
        vcs::info_ "opening $route_dcp"
        open_checkpoint $route_dcp
    } else {
        vcs::np_impl
    }
}

proc vcs::np_bitstream {} {
    global bd
    vcs::np_load_route
    set bit [file join $bd [vcs::top].bit]
    vcs::info_ "write_bitstream -> $bit"
    write_bitstream -force $bit
    # A probes file only exists when the design instantiates debug cores.
    if {[llength [get_debug_cores -quiet]] > 0} {
        write_debug_probes -force [file join $bd [vcs::top].ltx]
    }
    vcs::source_hook VCS_POST_TCL
    vcs::info_ "bitstream: $bit"
}

# ---------------------------------------------------------------------------
# project flow
# ---------------------------------------------------------------------------
proc vcs::pr_open {} {
    set xpr [vcs::env VCS_XPR]
    if {$xpr eq ""} { vcs::fatal "VCS_FLOW_MODE=project requires VCS_XPR" }
    if {![file exists $xpr]} { vcs::fatal "project not found: $xpr" }
    if {[current_project -quiet] eq ""} {
        vcs::info_ "open_project $xpr"
        open_project $xpr
    }
}

proc vcs::pr_run {run args} {
    vcs::pr_open
    set r [get_runs $run]
    if {[get_property PROGRESS $r] eq "100%" && [get_property NEEDS_REFRESH $r] == 0} {
        vcs::info_ "$run is already up to date"
        return
    }
    reset_run $r
    eval [list launch_runs $r -jobs [vcs::jobs]] $args
    wait_on_run $r
    if {[get_property PROGRESS $r] ne "100%"} {
        vcs::fatal "$run failed; see [get_property DIRECTORY $r]"
    }
}

proc vcs::pr_collect {} {
    global bd
    vcs::pr_open
    set impl [get_runs impl_1]
    set dir [get_property DIRECTORY $impl]
    foreach ext {bit ltx} {
        foreach f [glob -nocomplain [file join $dir *.$ext]] {
            file copy -force $f [file join $bd [file tail $f]]
            vcs::info_ "collected [file tail $f] -> $bd"
        }
    }
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
if {$flow_mode eq "project"} {
    switch -- $stage {
        synth     { vcs::pr_run synth_1 }
        impl      { vcs::pr_run synth_1; vcs::pr_run impl_1 }
        bitstream -
        all       { vcs::pr_run synth_1
                    vcs::pr_run impl_1 -to_step write_bitstream
                    vcs::pr_collect }
    }
} else {
    switch -- $stage {
        synth     { vcs::np_synth }
        impl      { vcs::np_impl }
        bitstream { vcs::np_bitstream }
        all       { vcs::np_synth; vcs::np_impl; vcs::np_bitstream }
    }
}

vcs::info_ "stage '$stage' complete"
