param($Context)

$output = @()

$span = Start-FunctionsOpenTelemetrySpan -ActivityName 'HelloOrchestrator'

$output += Invoke-DurableActivity -FunctionName 'Hello' -Input 'Tokyo'
$output += Invoke-DurableActivity -FunctionName 'Hello' -Input 'Seattle'
$output += Invoke-DurableActivity -FunctionName 'Hello' -Input 'London'

Stop-FunctionsOpenTelemetrySpan -Span $span

$output
