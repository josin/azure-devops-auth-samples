Describe 'TestMIHttpTrigger authorization' {
    BeforeAll {
        $sourcePath = Join-Path $PSScriptRoot 'TestMIHttpTrigger.cs'
        $source = Get-Content $sourcePath -Raw
    }

    It 'requires platform authentication before the function executes' {
        $source | Should -Match 'HttpTrigger\(AuthorizationLevel\.Function'
        $source | Should -Not -Match 'HttpTrigger\(AuthorizationLevel\.Anonymous'
    }

    It 'defaults to denying callers without an authenticated identity' {
        $source | Should -Match 'req\.HttpContext\.User\.Identity\?\.IsAuthenticated\s*!=\s*true'
        $source | Should -Match 'UnauthorizedResult'
    }

    It 'requires the configured reader role' {
        $source | Should -Match 'RequiredRole\s*=\s*"AzureDevOpsWorkItemReader"'
        $source | Should -Match 'ClaimTypes\.Role'
        $source | Should -Match 'claim\.Value\s*==\s*RequiredRole'
        $source | Should -Match 'ForbidResult'
    }

    It 'logs denied authentication and authorization attempts without request data' {
        $source | Should -Match 'LogWarning\("Unauthenticated request rejected\."\)'
        $source | Should -Match 'LogWarning\("Authenticated request without required role rejected\."\)'
    }

    It 'validates work item IDs before calling Azure DevOps' {
        $source | Should -Match 'workItemId\s*<=\s*0'
        $source | Should -Match 'BadRequestObjectResult\("A positive work item ID is required\."\)'
    }
}
