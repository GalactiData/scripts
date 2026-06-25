#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bash/docker-install/docker-install.sh"
}

@test "-h prints usage and exits 0" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "running as non-root exits 1" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root would attempt a real install"
    fi
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}
