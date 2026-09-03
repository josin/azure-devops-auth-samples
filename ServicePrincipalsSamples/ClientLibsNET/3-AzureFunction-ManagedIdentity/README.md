# Azure Function using an Azure AD Managed Identity to get a work item

This sample shows how to get an Azure AD access token for a Managed Identity using [Azure Identity client library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme?view=azure-dotnet) and authenticate to Azure DevOps to create or get a work item.

## How to run this sample

**Prerequisites**

- [.NET Core SDK](https://dotnet.microsoft.com/en-us/download) - 6.0 or higher
- [Azure DevOps .NET client libraries](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/dotnet-client-libraries?view=azure-devops) - 19.219.0-preview or higher
- [Visual Studio / Visual Studio Code](https://aka.ms/vsdownload)

### Step 1: Clone or download this repository

From a shell or command line: 

```ps
git clone https://github.com/microsoft/azure-devops-auth-samples.git
```

### Step 2: Create an Azure Function with a Managed Identity assigned

1. To create an Azure Function, see [Create your first function in the Azure portal](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-function-app-portal).
2. To assign it a Managed Identiy, see [How to use managed identities for App Service and Azure Functions](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity?tabs=portal%2Chttp).

### Step 3: Add the Managed Identity to your Azure DevOps Organization

Once the Managed Identity is created, [add it to your Azure DevOps organization](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity#step-by-step-configuration).

### Step 4: Configure the sample

Update constants in the file `TestMIHttpTrigger.cs` with the information about your Azure AD Managed Identity and Azure DevOps organization.

```cs
public const string AdoOrgName = "Your organization name";

public const string AadTenantId = "Your Azure AD tenant id";
// ClientId for User Assigned Managed Identity. Leave null for System Assigned Managed Identity
public const string AadUserAssignedManagedIdentityClientId = null;
```

### Step 5: Configure App Service authentication and app roles

1. Configure App Service Authentication for the Function App with Microsoft Entra ID, require authentication for all requests, and configure the unauthenticated action to return HTTP 401.
2. Define the `AzureDevOpsWorkItemReader` app role on the Function App registration and assign it only to identities that need this sample's read operation.

App Service Authentication (Easy Auth) validates the Microsoft Entra ID token and populates `HttpContext.User`. Easy Auth surfaces Entra app roles as `roles` claims. ASP.NET inbound claim mapping can instead expose them as `ClaimTypes.Role`, so the function deliberately accepts either claim type.

The function applies default-deny access control at three independent layers: (1) `AuthorizationLevel.Function` requires a valid function key, (2) App Service Authentication rejects requests without a Microsoft Entra ID token, and (3) the function rejects authenticated callers that do not carry the `AzureDevOpsWorkItemReader` app role. Do not change the trigger to `Anonymous`, permit unauthenticated App Service requests, or grant the reader role broadly.

### Step 6: Build, deploy, and invoke the sample

The sample will use different credentials depending on the environment.

- **In Azure**, the managed identity will be used.

**Test in dev environment**

In Visual Studio:

1. Open the solution file `../ServicePrincipalsSamples.sln`.
2. Configure the Azure account to be used in `Tools -> Options -> Azure Service Authentication -> Account Selection`.
3. Build the project and run using the profile `AzureFunctionTest`.
4. Publish the project to the Function App configured in Step 5.
5. In the output you will get the function URL and a function key. Call the function with a positive work item ID, a function key, and a Microsoft Entra bearer token for an identity assigned the `AzureDevOpsWorkItemReader` role.

> **Warning:** A function key is a bearer secret. Prefer the `x-functions-key` header over the `?code=` query parameter so the key is less likely to appear in proxy or access logs. Store keys in a secure secret store, distribute them only to callers that need access, and never embed them in client applications, commit them to source control, or write them to logs. Rotate keys regularly from the Function App **App keys** blade in the Azure portal, and revoke a key immediately when it is no longer needed or may have been exposed.

Grant the managed identity only the minimum Azure DevOps permissions required to read the intended work items. Enable App Service authentication logs and Application Insights, monitor rejected authentication and authorization attempts, and alert on unusual rejection rates. Validate deployment with an unauthenticated request (401), an authenticated caller without the app role (403), and an authorized caller (successful work-item retrieval).

See [Azure Identity client library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme?view=azure-dotnet#defaultazurecredential) for more details and options for providing local development credentials.

**Run in the Azure VM**

Follow the following steps from the guide [Quickstart: Create your first C# function in Azure using Visual Studio](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-your-first-function-visual-studio?tabs=in-process#publish-the-project-to-azure):

1. Publish the project to Azure
2. Verify your function in Azure
    
# References 

- [Introduction to Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview)
- [Azure.Identity - ManagedIdentityCredential.GetTokenAsync Method](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.managedidentitycredential.gettokenasync?view=azure-dotnet)