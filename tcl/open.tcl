# vivado-container-suite -- open a project or checkpoint in the IDE.
#   vivado -source open.tcl -tclargs <file.xpr|file.dcp>

set target [lindex $argv 0]
if {$target eq ""} { return }
if {![file exists $target]} {
    puts stderr "vcs-tcl  ✗ not found: $target"
    return
}

switch -- [file extension $target] {
    .xpr { open_project  $target }
    .dcp { open_checkpoint $target }
    .bd  { open_bd_design  $target }
    default {
        puts stderr "vcs-tcl  ✗ don't know how to open [file extension $target]; expected .xpr, .dcp or .bd"
    }
}
