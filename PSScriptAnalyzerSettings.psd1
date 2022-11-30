@{
    'Rules'        = @{
        PSAvoidUsingPositionalParameters = @{
            CommandAllowList = 'az', 'Join-Path'
            Enable           = $true
        }
    }
    'ExcludeRules' = @('PSAvoidUsingWriteHost')
}
