$modulePath = Join-Path $PSScriptRoot '..\AzureWebAppPublishModule.psm1'
Import-Module $modulePath -Force

Describe 'Publish-WebPackage process invocation' {
    InModuleScope AzureWebAppPublishModule {
        BeforeEach {
            Mock Test-Path { $true }
            Mock Get-MSDeployCmd { 'C:\Program Files\IIS\Microsoft Web Deploy V3\MsDeploy.exe' }
            Mock Get-Item {
                [pscustomobject]@{ FullName = 'C:\packages\sample app.zip' }
            }

            Mock Start-Process {
                [pscustomobject]@{ ExitCode = 0 }
            }
        }

        It 'requires a trusted Microsoft-signed msdeploy executable' {
            $moduleSource = Get-Content (Join-Path $PSScriptRoot '..\AzureWebAppPublishModule.psm1') -Raw

            $moduleSource | Should -Match 'Get-AuthenticodeSignature'
            $moduleSource | Should -Match 'SignatureStatus\]::Valid'
            $moduleSource | Should -Match 'O=Microsoft Corporation'
            $moduleSource | Should -Match "GetFolderPath\('ProgramFiles'\)"
        }

        It 'launches msdeploy directly and preserves allowed punctuation as argument data' {
            $password = 'secret!value'
            $connections = @{
                'DefaultConnection' = 'Server=db;Database=sample'
            }

            $result = Publish-WebPackage `
                -WebDeployPackage 'C:\packages\sample app.zip' `
                -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                -SiteName 'sample-site' `
                -UserName 'deploy-user' `
                -Password $password `
                -ConnectionString $connections

            $result | Should -BeTrue
            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\Program Files\IIS\Microsoft Web Deploy V3\MsDeploy.exe' -and
                $FilePath -ne 'cmd.exe' -and
                $ArgumentList -match '-Source:Package=' -and
                $ArgumentList -match '-dest:auto,computername='
            }
            Assert-MockCalled Start-Process -Times 1 -Exactly
        }

        It 'quotes native arguments with spaces, embedded quotes, and trailing backslashes' {
            ConvertTo-NativeCommandLineArgument 'plain' |
                Should -Be 'plain'
            ConvertTo-NativeCommandLineArgument 'value with spaces' |
                Should -Be '"value with spaces"'
            ConvertTo-NativeCommandLineArgument 'value "quoted"' |
                Should -Be '"value \"quoted\""'
            ConvertTo-NativeCommandLineArgument 'C:\path with spaces\' |
                Should -Be '"C:\path with spaces\\"'
        }

        It 'does not write credentials to the verbose stream' {
            $password = 'do-not-log-this-password'
            $verboseOutput = & {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password $password `
                    -ConnectionString @{}
            } -Verbose 4>&1 | Out-String

            $verboseOutput | Should -Not -Match [regex]::Escape($password)
        }

        It 'returns false when msdeploy exits with an error' {
            Mock Start-Process {
                [pscustomobject]@{ ExitCode = 1 }
            }

            $result = Publish-WebPackage `
                -WebDeployPackage 'C:\packages\sample app.zip' `
                -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                -SiteName 'sample-site' `
                -UserName 'sample-user' `
                -Password 'sample-password' `
                -ConnectionString @{}

            $result | Should -BeFalse
        }

        It 'rejects deployment values containing command injection characters' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'site&whoami' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{}
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }

        It 'rejects invalid connection string parameter names' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{ 'Default&Name' = 'Server=db' }
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }

        It 'rejects msdeploy grammar injection in scalar values' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample,userName=attacker' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{}
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }
    }
}
