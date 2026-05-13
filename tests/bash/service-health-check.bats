#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/service-health-check/service-health-check.sh"
    if ! command -v systemctl &>/dev/null; then
        skip "systemctl not available on this runner"
    fi
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "no services specified shows usage" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "-f with a missing file exits 1" {
    run bash "$SCRIPT" -f /nonexistent/services.txt
    [ "$status" -eq 1 ]
}

@test "nonexistent service name exits 2" {
    run bash "$SCRIPT" nonexistent-service-xyz-abc
    [ "$status" -eq 2 ]
}
