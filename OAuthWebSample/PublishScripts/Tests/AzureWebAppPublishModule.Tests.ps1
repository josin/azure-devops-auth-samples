$modulePath = Join-Path $PSScriptRoot '..\AzureWebAppPublishModule.psm1'
Import-Module $modulePath -Force

Describe 'Publish-WebPackage process invocation' {
    InModuleScope AzureWebAppPublishModule {
        BeforeEach {
            $script:capturedArgumentList = $null
            Mock Test-Path { $true }
            Mock Get-MSDeployCmd { 'C:\Program Files\IIS\Microsoft Web Deploy V3\MsDeploy.exe' }
            Mock Get-Item {
                [pscustomobject]@{ FullName = 'C:\packages\sample app.zip' }
            }

            Mock Start-Process {
                $script:capturedArgumentList = $ArgumentList
                [pscustomobject]@{ ExitCode = 0 }
            }
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

        $passwordCases = @(
            @{ Label = 'equals'; Value = 'secret=value==' }
            @{ Label = 'space'; Value = 'secret value' }
            @{ Label = 'semicolon'; Value = 'secret;value' }
            @{ Label = 'ampersand'; Value = 'secret&value' }
            @{ Label = 'pipe'; Value = 'secret|value' }
            @{ Label = 'angle brackets'; Value = 'secret<value>' }
            @{ Label = 'backtick'; Value = 'secret`value' }
            @{ Label = 'ordinary punctuation'; Value = 'secret!#$%''()+-./:?@[]^_{}~' }
        )

        It 'preserves direct-process-safe password characters: <Label>' -TestCases $passwordCases {
            param($Label, $Value)

            $result = Publish-WebPackage `
                -WebDeployPackage 'C:\packages\sample app.zip' `
                -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                -SiteName 'sample-site' `
                -UserName 'deploy-user' `
                -Password $Value `
                -ConnectionString @{ 'DefaultConnection' = 'Server=db,1433;Password=a=b;Value=space value' }

            $result | Should -BeTrue
            $script:capturedArgumentList | Should -Match ([regex]::Escape($Value))
            $script:capturedArgumentList |
                Should -Match ([regex]::Escape('Server=db,1433;Password=a=b;Value=space value'))
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

        $invalidPackagePaths = @(
            @{ Label = 'comma-delimited attribute'; Value = 'C:\packages\sample.zip,foo=bar' }
            @{ Label = 'double quote'; Value = 'C:\packages\sample".zip' }
            @{ Label = 'control character'; Value = "C:\packages\sample`n.zip" }
            @{ Label = 'delete character'; Value = 'C:\packages\sample' + [char]0x7F + '.zip' }
        )

        It 'rejects <Label> in the resolved package path' -TestCases $invalidPackagePaths {
            param($Label, $Value)

            $script:resolvedPackagePath = $Value
            Mock Get-Item {
                [pscustomobject]@{
                    FullName = $script:resolvedPackagePath
                }
            }

            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample-site' `
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

        It 'rejects PublishUrl msdeploy attribute injection' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd,userName=attacker' `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{}
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }

        It 'rejects connection value msdeploy attribute injection' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{
                        'DefaultConnection' = 'Server=db;Database=x,scope=DeploymentBinaryPath,match=.*'
                    }
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }

        It 'validates every connection value before invoking msdeploy' {
            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl 'https://server.example:8172/msdeploy.axd' `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{
                        'Malicious' = 'Server=db;Database=x,scope=DeploymentBinaryPath'
                        'Benign' = 'Server=db;Database=x'
                    }
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }

        $invalidPublishUrls = @(
            @{ Label = 'user info'; Value = 'https://user@server.example:8172/msdeploy.axd' }
            @{ Label = 'query'; Value = 'https://server.example:8172/msdeploy.axd?x=y' }
            @{ Label = 'fragment'; Value = 'https://server.example:8172/msdeploy.axd#fragment' }
            @{ Label = 'quote'; Value = 'https://server.example:8172/msdeploy".axd' }
        )

        It 'rejects PublishUrl with <Label>' -TestCases $invalidPublishUrls {
            param($Label, $Value)

            {
                Publish-WebPackage `
                    -WebDeployPackage 'C:\packages\sample app.zip' `
                    -PublishUrl $Value `
                    -SiteName 'sample-site' `
                    -UserName 'sample-user' `
                    -Password 'sample-password' `
                    -ConnectionString @{}
            } | Should -Throw

            Assert-MockCalled Start-Process -Times 0 -Exactly
        }
    }
}

Describe 'MSDeploy executable trust behavior' {
    InModuleScope AzureWebAppPublishModule {
        BeforeEach {
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{
                        Subject = 'CN=Microsoft Code Signing PCA, O=Microsoft Corporation, C=US'
                    }
                }
            }
        }

        It 'accepts an executable under an approved root with a valid exact Microsoft O component' {
            Test-MSDeployExecutableTrust `
                -ResolvedPath 'C:\Program Files\IIS\Microsoft Web Deploy V3\MsDeploy.exe' `
                -ApprovedRoots @('C:\Program Files') | Should -BeTrue
        }

        It 'rejects an approved-root prefix collision' {
            {
                Test-MSDeployExecutableTrust `
                    -ResolvedPath 'C:\Program FilesEvil\MsDeploy.exe' `
                    -ApprovedRoots @('C:\Program Files')
            } | Should -Throw
        }

        It 'rejects an invalid Authenticode signature' {
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::NotSigned
                    SignerCertificate = $null
                }
            }

            {
                Test-MSDeployExecutableTrust `
                    -ResolvedPath 'C:\Program Files\IIS\MsDeploy.exe' `
                    -ApprovedRoots @('C:\Program Files')
            } | Should -Throw
        }

        $invalidSignerCases = @(
            @{ Label = 'non-Microsoft O component'; Subject = 'CN=Contoso, O=Contoso, C=US' }
            @{ Label = 'Microsoft substring in O component'; Subject = 'CN=Signer, O=Microsoft Corporation Services, C=US' }
            @{ Label = 'Microsoft lookalike O component'; Subject = 'CN=Signer, O=Not Microsoft Corporation, C=US' }
            @{ Label = 'Microsoft text in OU component'; Subject = 'CN=Signer, OU=O=Microsoft Corporation, O=Contoso, C=US' }
            @{ Label = 'Microsoft text in CN component'; Subject = 'CN="O=Microsoft Corporation", O=Contoso, C=US' }
            @{ Label = 'Microsoft text after an escaped CN comma'; Subject = 'CN=Release\, O=Microsoft Corporation, O=Contoso, C=US' }
        )

        It 'rejects signer subject with <Label>' -TestCases $invalidSignerCases {
            param($Label, $Subject)

            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = $Subject }
                }
            }

            {
                Test-MSDeployExecutableTrust `
                    -ResolvedPath 'C:\Program Files\IIS\MsDeploy.exe' `
                    -ApprovedRoots @('C:\Program Files')
            } | Should -Throw
        }

        It 'returns null when registry discovery finds no msdeploy version' {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @() }

            Get-MSDeployCmd | Should -BeNullOrEmpty
        }
    }
}

Describe 'AzureWebAppPublishModule static-shape assertions' {
    It 'uses direct process execution rather than cmd.exe' {
        $moduleSource = Get-Content (Join-Path $PSScriptRoot '..\AzureWebAppPublishModule.psm1') -Raw

        $moduleSource | Should -Not -Match 'Start-Process\s+cmd\.exe'
    }
}
