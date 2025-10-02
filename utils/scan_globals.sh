#!/bin/bash

scan_file() {
    awk '
BEGIN { in_function=0; local_vars="" }
/function [a-zA-Z_][a-zA-Z0-9_]* *\(\)|[a-zA-Z_][a-zA-Z0-9_]* *\(\)/ {
    in_function=1
    local_vars=""
    func_name=$2
    func_start=NR
}
/}/ && in_function {
    in_function=0
    local_vars=""
}
/^[ \t]*local[ \t]+/ && in_function {
    sub(/^[ \t]*local[ \t]+/, "")
    split($0, vars, /[ \t]*=[^=]*|[ \t]+/)
    for (i in vars) {
        if (vars[i] ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) {
            local_vars = local_vars (local_vars == "" ? "" : ",") vars[i]
        }
    }
}
/^[ \t]*[a-zA-Z_][a-zA-Z0-9_]*=/ && in_function {
    var_name = $0
    sub(/=.*/, "", var_name)
    sub(/^[ \t]*/, "", var_name)
    if (local_vars == "" || !match(local_vars, "(^|,)" var_name "(,|$)")) {
        print "Potential global variable in function at line", NR, ":", $0
    }
}
' "$1"
}

sdir="$(readlink -f "$(dirname "$(dirname "$0"))")")"
to_scan="$sdir/jas.sh $(echo "$sdir/scripts"/*.sh)"
[ -n "$1" ] && to_scan="$*"

for file in $to_scan; do
    [ ! -f "$file" ] && { echo "$file not found" >&2; continue; }
    output="$(scan_file "$file")"
    if [ -n "$output" ]; then
        echo -e "$file:\n"
        echo "$output"
        echo
    fi
done
