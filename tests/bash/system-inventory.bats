#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/system-inventory/system-inventory.sh"
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "runs successfully and outputs expected sections" {
    run bash "$SCRIPT" --skip-packages
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYSTEM"* ]]
    [[ "$output" == *"CPU"* ]]
    [[ "$output" == *"MEMORY"* ]]
    [[ "$output" == *"NETWORK"* ]]
}

@test "--format csv produces a key,value header" {
    run bash "$SCRIPT" --format csv --skip-packages
    [ "$status" -eq 0 ]
    [[ "$output" == *"key,value"* ]]
}

@test "--skip-packages completes without error" {
    run bash "$SCRIPT" --skip-packages
    [ "$status" -eq 0 ]
}

@test "-o writes output to a file" {
    local tmpfile
    tmpfile="$(mktemp)"
    run bash "$SCRIPT" --skip-packages -o "$tmpfile"
    [ "$status" -eq 0 ]
    [ -s "$tmpfile" ]
    grep -q "SYSTEM" "$tmpfile"
    rm -f "$tmpfile"
}
