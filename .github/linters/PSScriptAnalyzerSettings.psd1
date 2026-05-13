@{
    ExcludeRules = @(
        # All scripts use Write-Host intentionally for colored console output
        'PSAvoidUsingWriteHost',
        # Scripts implement their own confirmation gate rather than ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions',
        # Write-Log is not a built-in in PS 5.1 (only appeared in PS Core 6.1+)
        'PSAvoidOverwritingBuiltInCmdlets',
        # Internal helpers intentionally use plural nouns (e.g. Stop-AutodeskProcesses,
        # Remove-AutodeskFiles) because they operate on multiple items by design
        'PSUseSingularNouns',
        # PSScriptAnalyzer cannot see through nested function calls; parameters flagged
        # as unused are consumed by helper functions within the same script
        'PSReviewUnusedParameter'
    )
}
