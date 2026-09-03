Describe 'TestMIHttpTrigger behavior' {
    BeforeAll {
        $previousRollForward = $env:DOTNET_ROLL_FORWARD
        $env:DOTNET_ROLL_FORWARD = 'Major'
        $sampleProject = Join-Path $PSScriptRoot '3-AzureFunction-ManagedIdentity.csproj'
        $harnessDirectory = Join-Path $TestDrive 'AuthorizationHarness'
        $harnessProject = Join-Path $harnessDirectory 'AuthorizationHarness.csproj'
        New-Item -ItemType Directory -Path $harnessDirectory | Out-Null

        @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$sampleProject" />
  </ItemGroup>
</Project>
"@ | Set-Content -Path $harnessProject

        @'
using System.Security.Claims;
using System.Text.Json;
using Company.Function;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

var scenario = args.Single();
var context = new DefaultHttpContext
{
    TraceIdentifier = $"trace-{scenario}"
};
context.Request.Headers["Authorization"] = "Bearer sensitive-token";
context.Request.QueryString = new QueryString("?workItemId=-1&sensitive=sensitive-query");

var claims = new List<Claim>();
var authenticationType = scenario == "unauthenticated" ? null : "TestAuthentication";
if (scenario == "mapped-role")
{
    claims.Add(new Claim(ClaimTypes.Role, "AzureDevOpsWorkItemReader"));
}
else if (scenario == "raw-role")
{
    claims.Add(new Claim("roles", "AzureDevOpsWorkItemReader"));
}

context.User = new ClaimsPrincipal(new ClaimsIdentity(claims, authenticationType));
var logger = new CapturingLogger();
var result = await TestMIHttpTrigger.Run(context.Request, logger);
var statusCode = result switch
{
    StatusCodeResult status => status.StatusCode,
    ObjectResult value => value.StatusCode,
    _ => null
};

Console.WriteLine(JsonSerializer.Serialize(new
{
    ResultType = result.GetType().FullName,
    StatusCode = statusCode,
    Logs = logger.Entries
}));

sealed class CapturingLogger : ILogger
{
    public List<LogEntry> Entries { get; } = new();

    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        var properties = state is IEnumerable<KeyValuePair<string, object?>> values
            ? values.ToDictionary(pair => pair.Key, pair => pair.Value?.ToString())
            : new Dictionary<string, string?>();
        Entries.Add(new LogEntry(logLevel.ToString(), formatter(state, exception), properties));
    }
}

sealed record LogEntry(
    string Level,
    string Message,
    IReadOnlyDictionary<string, string?> Properties);
'@ | Set-Content -Path (Join-Path $harnessDirectory 'Program.cs')

        $buildOutput = & dotnet build $harnessProject --nologo --verbosity quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Harness build failed:`n$($buildOutput -join [Environment]::NewLine)"
        }

        function Invoke-AuthorizationScenario {
            param([Parameter(Mandatory)][string]$Name)

            $output = & dotnet run --project $harnessProject --no-build -- $Name 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Harness scenario '$Name' failed:`n$($output -join [Environment]::NewLine)"
            }

            return ($output | Select-Object -Last 1 | ConvertFrom-Json)
        }
    }

    AfterAll {
        $env:DOTNET_ROLL_FORWARD = $previousRollForward
    }

    It 'returns an exact StatusCodeResult with 401 for an unauthenticated caller' {
        $result = Invoke-AuthorizationScenario -Name 'unauthenticated'

        $result.ResultType | Should -Be 'Microsoft.AspNetCore.Mvc.StatusCodeResult'
        $result.StatusCode | Should -Be 401
    }

    It 'returns an exact StatusCodeResult with 403 for a caller without the required role' {
        $result = Invoke-AuthorizationScenario -Name 'missing-role'

        $result.ResultType | Should -Be 'Microsoft.AspNetCore.Mvc.StatusCodeResult'
        $result.StatusCode | Should -Be 403
    }

    It 'records an opaque trace identifier as structured denial log data without sensitive input' -ForEach @(
        @{ Scenario = 'unauthenticated'; ExpectedLevel = 'Warning' }
        @{ Scenario = 'missing-role'; ExpectedLevel = 'Warning' }
    ) {
        $result = Invoke-AuthorizationScenario -Name $Scenario
        $log = $result.Logs | Where-Object Level -EQ $ExpectedLevel | Select-Object -First 1
        $serializedLog = $log | ConvertTo-Json -Depth 5 -Compress

        $log.Properties.TraceId | Should -Be "trace-$Scenario"
        $serializedLog | Should -Not -Match 'sensitive-token|sensitive-query'
    }

    It 'accepts the mapped ClaimTypes.Role claim without reaching Azure DevOps' {
        $result = Invoke-AuthorizationScenario -Name 'mapped-role'

        $result.ResultType | Should -Be 'Microsoft.AspNetCore.Mvc.BadRequestObjectResult'
        $result.StatusCode | Should -Be 400
    }

    It 'accepts the raw roles claim without reaching Azure DevOps' {
        $result = Invoke-AuthorizationScenario -Name 'raw-role'

        $result.ResultType | Should -Be 'Microsoft.AspNetCore.Mvc.BadRequestObjectResult'
        $result.StatusCode | Should -Be 400
    }
}

Describe 'TestMIHttpTrigger source contracts (static)' {
    BeforeAll {
        $sourcePath = Join-Path $PSScriptRoot 'TestMIHttpTrigger.cs'
        $source = Get-Content $sourcePath -Raw
    }

    It 'requires a function key at the trigger boundary' {
        $source | Should -Match 'HttpTrigger\(AuthorizationLevel\.Function'
        $source | Should -Not -Match 'HttpTrigger\(AuthorizationLevel\.Anonymous'
    }

    It 'retains the required role and positive work item ID boundaries' {
        $source | Should -Match 'RequiredRole\s*=\s*"AzureDevOpsWorkItemReader"'
        $source | Should -Match 'workItemId\s*<=\s*0'
        $source | Should -Match 'BadRequestObjectResult\("A positive work item ID is required\."\)'
    }

    It 'correlates downstream failures without returning exception details' {
        $source | Should -Match 'LogError\(ex,\s*"Failed to retrieve work item \{WorkItemId\}\. TraceId=\{TraceId\}"'
        $source | Should -Match 'requestId\s*=\s*req\.HttpContext\.TraceIdentifier'
        $source | Should -Not -Match 'ObjectResult\(ex\.Message\)'
    }
}
