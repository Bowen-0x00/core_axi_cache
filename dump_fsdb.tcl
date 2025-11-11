if { [info exists env(fsdb_file)] && $env(fsdb_file) ne "" } {
    fsdbDumpfile "$env(fsdb_file).fsdb"
    fsdbDumpvars 0 "tb" "+all" "+trace_process"
}

run
exit

