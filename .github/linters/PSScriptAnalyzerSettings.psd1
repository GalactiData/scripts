@{
    ExcludeRules = @(
        # All scripts use Write-Host intentionally for colored console output
        'PSAvoidUsingWriteHost',
        # Scripts implement their own confirmation gate rather than ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
