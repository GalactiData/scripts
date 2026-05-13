#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/disk-space-report/disk-space-report.sh"
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "runs with default thresholds without error" {
    run bash "$SCRIPT"
    [ "$status" -le 2 ]
}

@test "-w 1 -c 99 exits 1 when any filesystem exceeds 1% used" {
    run bash "$SCRIPT" -w 1 -c 99
    [ "$status" -eq 1 ]
}

@test "-w 1 -c 1 exits 2 when any filesystem exceeds 1% used" {
    run bash "$SCRIPT" -w 1 -c 1
    [ "$status" -eq 2 ]
}

@test "-o appends results to a log file" {
    local tmpfile
    tmpfile="$(mktemp)"
    run bash "$SCRIPT" -o "$tmpfile"
    [ -s "$tmpfile" ]
    rm -f "$tmpfile"
}
