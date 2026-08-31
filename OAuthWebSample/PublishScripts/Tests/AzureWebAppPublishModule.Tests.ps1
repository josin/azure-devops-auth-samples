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

        It 'launches msdeploy directly and preserves metacharacters as argument data' {
            $password = 'secret&whoami|echo "quoted"'
            $connections = @{
                'Default&Name' = 'Server=db;Password=p@ss&whoami|echo injected>file'
            }

            $result = Publish-WebPackage `
                -WebDeployPackage 'C:\packages\sample app.zip' `
                -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                -SiteName 'site&whoami' `
                -UserName 'deploy|user' `
                -Password $password `
                -ConnectionString $connections

            $result | Should -BeTrue
            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\Program Files\IIS\Microsoft Web Deploy V3\MsDeploy.exe' -and
                $FilePath -ne 'cmd.exe'
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
    }
}
