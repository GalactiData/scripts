#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/ssl-cert-check/ssl-cert-check.sh"
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "no domains specified shows usage" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "example.com has a valid certificate" {
    run bash "$SCRIPT" example.com
    # OK (0) or WARNING (1) — not expired (2) and not a crash
    [ "$status" -le 1 ]
    [[ "$output" == *"example.com"* ]]
}

@test "-o appends results to a log file" {
    local tmpfile
    tmpfile="$(mktemp)"
    run bash "$SCRIPT" -o "$tmpfile" example.com
    [ -s "$tmpfile" ]
    grep -q "example.com" "$tmpfile"
    rm -f "$tmpfile"
}
