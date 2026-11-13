Set-StrictMode -Version Latest
function Assert-BastosNotCancelled {
    param([string]$CancellationPath)
    if($CancellationPath -and [IO.File]::Exists($CancellationPath)){
        throw [OperationCanceledException]::new('Annulation demandee au point d arret sur. Aucun arret force de processus.')
    }
}
function Lock-BastosCancellation {
    param([string]$CancellationPath,[string]$Reason)
    if(-not $CancellationPath){return}
    Assert-BastosNotCancelled -CancellationPath $CancellationPath
    Write-BastosJsonFile -Path ($CancellationPath+'.state.json') -Data @{State='Locked';Reason=$Reason}
}
Export-ModuleMember -Function Assert-BastosNotCancelled,Lock-BastosCancellation
