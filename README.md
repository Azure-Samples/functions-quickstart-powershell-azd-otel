# functions-quickstart-powershell-azd-otel

## Overview

This end-to-end PowerShell sample demonstrates distributed tracing with OpenTelemetry across multiple Azure Functions in a Flex Consumption plan app with Durable Functions integration.

## Prerequisites

- PowerShell >= 7.4
- [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- An OTEL-compatible endpoint

## Setup Instructions

1. **Clone the repository:**

    ```sh
    git clone https://github.com/Azure-Samples/functions-quickstart-powershell-azd-otel.git
    cd functions-quickstart-powershell-azd-otel
    ```

2. **Run build.ps1:**

    ```powershell
    cd /src
    ./build.ps1
        ```

3. **Configure your OTEL endpoint:**

    - Update the environment variables in local.settings.json to point to your OTEL collector endpoint. You will need to add these settings to your functionapp's environment after deployment as well.

4. **Invoke the functions**

    - Start a Durable orchestration by sending a GET request to the StartDurableOrchestration HTTP URL exposed by the functionapp, either in Core Tools or Azure.

## Documentation

- [OpenTelemetry with Azure Functions (PowerShell)](https://learn.microsoft.com/en-us/azure/azure-functions/opentelemetry-howto?tabs=otlp-export%2Cihostapplicationbuilder%2Cmaven&pivots=programming-language-powershell)
- [Durable Functions PowerShell SDK](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-powershell-v2-sdk-migration-guide?tabs=azure-cli-set-indexing-flag)

## Additional Notes

- This sample demonstrates tracing across multiple Durable function invocations, including an HTTP starter function, orchestrations and activities. Additional telemetry filtering may be necessary to reduce the volume of Azure Storage operations performed by Durable Functions.
- This sample uses the standalone PowerShell SDK `AzureFunctions.PowerShell.Durable.SDK`
- This sample uses an OTLP collector endpoint because exporting OpenTelemetry + Distributed Tracing to Application Insights is currently not supported in PowerShell
