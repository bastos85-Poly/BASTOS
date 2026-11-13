param([string]$WorkerPath)
if ($env:BASTOS_TEST_BROWSER_CAPTURE) {
    function global:Start-Process { param([string]$FilePath) [IO.File]::WriteAllText($env:BASTOS_TEST_BROWSER_CAPTURE, $FilePath) }
}
& $WorkerPath @args
exit $LASTEXITCODE
