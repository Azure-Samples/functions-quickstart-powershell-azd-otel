# functions-quickstart-powershell-azd-otel

## Overview

This end-to-end PowerShell sample demonstrates distributed tracing with OpenTelemetry across multiple Azure Functions in a function app using **Durable Functions** with the **Azure Durable Task Scheduler (DTS)** backend.

State for orchestrations and activities is managed by **Azure Durable Task Scheduler** (not Azure Storage queues/tables). DTS emits OpenTelemetry spans which flow through the same OTLP pipeline the sample already uses, so the distributed trace for `StartDurableOrchestration → HelloOrchestrator → Hello` stays intact end-to-end.

## Prerequisites

- PowerShell >= 7.4
- [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker](https://www.docker.com/) (to run the DTS emulator locally)
- An OTLP-compatible trace collector endpoint (e.g. an OTel Collector, Aspire dashboard, Jaeger, Grafana Tempo, ...)

## Run locally with the DTS emulator

1. **Start the Durable Task Scheduler emulator:**

    ```sh
    docker run --rm -p 8080:8080 -p 8082:8082 mcr.microsoft.com/dts/dts-emulator:latest
    ```

    The emulator dashboard is available at <http://localhost:8082>.

2. **Build PowerShell dependencies:**

    ```powershell
    cd src
    ./build.ps1
    ```

3. **Configure your OTLP endpoint** by editing `src/local.settings.json` — update `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` to point at your collector. The DTS connection string in the same file already points at the local emulator (`Endpoint=http://localhost:8080;Authentication=None`).

4. **Start the Functions host:**

    ```sh
    func start
    ```

5. **Invoke the orchestration** by hitting the `StartDurableOrchestration` endpoint (GET or POST) that `func start` prints. Open the emulator dashboard at <http://localhost:8082> to watch the orchestration reach `Completed`.

## Deploy to Azure

```sh
azd auth login
azd up
```

`azd up` provisions:

- User-assigned managed identity (used by the function app to reach DTS)
- Flex Consumption Function App (PowerShell 7.4) with `DURABLE_TASK_SCHEDULER_CONNECTION_STRING` and `TASKHUB_NAME` wired in
- Storage account (blob only — for `AzureWebJobsStorage` host state and the `azd` deployment package)
- Log Analytics workspace + Application Insights component
- `Microsoft.DurableTask/schedulers` + task hub, plus the `Durable Task Data Contributor` role assignment on the UAMI

Set the OTLP target before `azd up` if you want the deployed app to export traces:

```sh
azd env set OTEL_EXPORTER_OTLP_ENDPOINT "https://<your-collector>"
azd env set --secret OTEL_EXPORTER_OTLP_HEADERS "<your-headers>"
```

## Monitor

- **DTS dashboard** (per-environment): `https://dashboard.durabletask.io` — find the task hub URL with `azd show`.
- **Application Insights / Log Analytics**: host-side logs and metrics.
- **Your OTLP collector**: distributed traces across HTTP trigger, orchestrator and activities, now including DTS spans.

## Documentation

- [Azure Durable Task Scheduler overview](https://learn.microsoft.com/azure/azure-functions/durable/durable-task-scheduler/durable-task-scheduler)
- [OpenTelemetry with Azure Functions (PowerShell)](https://learn.microsoft.com/azure/azure-functions/opentelemetry-howto?tabs=otlp-export%2Cihostapplicationbuilder%2Cmaven&pivots=programming-language-powershell)
- [Durable Functions PowerShell SDK](https://learn.microsoft.com/azure/azure-functions/durable/durable-functions-powershell-v2-sdk-migration-guide?tabs=azure-cli-set-indexing-flag)

## Additional Notes

- This sample demonstrates tracing across an HTTP starter, an orchestrator and multiple activities. With DTS, there are no Azure Storage queue/table operations to filter out.
- This sample uses the standalone PowerShell SDK `AzureFunctions.PowerShell.Durable.SDK` and the standard extension bundle (`Microsoft.Azure.Functions.ExtensionBundle`, `[4.*, 5.0.0)`), which provides the `azureManaged` storage provider for the Durable Task Scheduler backend.
- PowerShell does not currently export OpenTelemetry + distributed tracing to Application Insights, so an OTLP collector is still required for distributed traces.
