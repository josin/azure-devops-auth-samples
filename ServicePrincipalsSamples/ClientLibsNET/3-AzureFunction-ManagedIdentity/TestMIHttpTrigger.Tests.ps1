Describe 'TestMIHttpTrigger authorization' {
    It 'requires a function key' {
        $sourcePath = Join-Path $PSScriptRoot 'TestMIHttpTrigger.cs'
        $source = Get-Content $sourcePath -Raw

        $source | Should -Match 'HttpTrigger\(AuthorizationLevel\.Function'
        $source | Should -Not -Match 'HttpTrigger\(AuthorizationLevel\.Anonymous'
    }
}
