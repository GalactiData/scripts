#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/patch-report/patch-report.sh"
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "unknown option shows usage" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "unwritable -o path is rejected" {
    run bash "$SCRIPT" -o /proc/no-such-dir/report.log
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot write"* ]]
}

@test "produces a report with expected fields" {
    run bash "$SCRIPT"
    # 0 = up to date, 1 = updates pending, 2 = security/reboot — never a crash
    [ "$status" -le 2 ]
    [[ "$output" == *"Patch Report"* ]]
    [[ "$output" == *"Pending updates"* ]]
    [[ "$output" == *"Reboot required"* ]]
}

@test "-o appends a summary line to the log file" {
    local tmpfile
    tmpfile="$(mktemp)"
    run bash "$SCRIPT" -o "$tmpfile"
    [ -s "$tmpfile" ]
    grep -q "updates=" "$tmpfile"
    rm -f "$tmpfile"
}
