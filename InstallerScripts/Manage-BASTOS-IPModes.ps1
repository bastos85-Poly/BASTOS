[CmdletBinding()]
param(
    [Alias('Action')][ValidateSet('Get','PreferApply','PreferRestore','OnlyApply','OnlyRestore')][string]$IpAction='Get',
    [Alias('AdapterId')][string]$IpAdapterId,
    [Alias('ResultPath')][string]$IpResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Manage-BASTOS-Network.ps1')
# The shared Ethernet worker is dot-sourced for identity, secure storage and the
# same operation lock only. Its top-level entry point never runs here.
$script:IpRegistrySubkey='SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
$script:IpComponents=@('ms_tcpip','ms_tcpip6','ms_msclient','ms_server','ms_lltdio','ms_rspndr','ms_lldp','ms_pacer','ms_implat')

function Get-IpMachineId { [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop) }
function Get-IpBootId { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o') }
function Get-IpRegistryState {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:IpRegistrySubkey)
    try {
        if($null -eq $key -or 'DisabledComponents' -notin $key.GetValueNames()) {
            return [pscustomobject]@{Exists=$false;Kind='';Value=0}
        }
        [pscustomobject]@{Exists=$true;Kind=[string]$key.GetValueKind('DisabledComponents');Value=$key.GetValue('DisabledComponents')}
    } finally {if($null -ne $key){$key.Dispose()}}
}
function Set-IpRegistryState($State) {
    # Only the fixed DWORD value can be changed. No registry paths come from JSON.
    if($State.Exists -and ($State.Kind -ne 'DWord' -or [long]$State.Value -notin @(0,32))){throw 'Valeur IPv6 non standard : modification refusee.'}
    if($State.Exists){$key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($script:IpRegistrySubkey)}
    else {$key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:IpRegistrySubkey,$true)}
    try {
        if($State.Exists){$key.SetValue('DisabledComponents',[int]$State.Value,[Microsoft.Win32.RegistryValueKind]::DWord)}
        elseif($null -ne $key){$key.DeleteValue('DisabledComponents',$false)}
    } finally {if($null -ne $key){$key.Dispose()}}
}
function Test-IpRegistryEqual($A,$B) {
    return $A.Exists -eq $B.Exists -and (-not $A.Exists -or ($A.Kind -eq $B.Kind -and [string]$A.Value -eq [string]$B.Value))
}
function Get-IpBackupPath([string]$Kind,[string]$Id='') {
    if($Kind -eq 'Prefer'){return Join-Path $script:NetworkBackupRoot 'prefer-ipv4.json'}
    Join-Path $script:NetworkBackupRoot ('ipv4-only-'+([guid]$Id).ToString('D')+'.json')
}
function Read-IpBackup([string]$Kind,[string]$Id='') {
    $path=Get-IpBackupPath $Kind $Id
    if(-not(Test-Path -LiteralPath $path)){return $null}
    $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($state.Schema -ne 1 -or $state.Kind -ne $Kind -or $state.MachineId -ne (Get-IpMachineId) -or $state.Active -isnot [bool]){throw 'Sauvegarde IP invalide ou provenant d''un autre PC.'}
    if($Kind -eq 'Prefer'){
        if($state.Original.Exists -isnot [bool] -or ($state.Original.Exists -and ($state.Original.Kind -ne 'DWord' -or [long]$state.Original.Value -notin @(0,32)))){throw 'Valeur originale IPv6 invalide.'}
    } else {
        if($state.AdapterId -ne ([guid]$Id).ToString('D') -or -not $state.PnpId){throw 'Identite de sauvegarde IP invalide.'}
        $seen=@()
        foreach($entry in @($state.Entries)){
            if($entry.Component -notmatch '^[A-Za-z0-9_.{}-]{1,180}$' -or $entry.Component -in $seen -or
                $entry.Managed -isnot [bool] -or $entry.Managed -ne ($entry.Component -in $script:IpComponents) -or
                $entry.Original -isnot [bool] -or $entry.Target -isnot [bool] -or $entry.Touched -isnot [bool]){throw 'Liaison de sauvegarde IP invalide.'}
            $seen+=$entry.Component
        }
        foreach($entry in @($state.RestorePlan)){
            if($entry.Component -notin $seen -or $entry.Desired -isnot [bool]){throw 'Plan de restauration IP invalide.'}
        }
    }
    $state
}
function Write-IpBackup($State) {
    $path=Get-IpBackupPath $State.Kind $(if($State.Kind -eq 'Only'){$State.AdapterId}else{''})
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,($State | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,($path+'.previous'))}
    else{[IO.File]::Move($temp,$path)}
}
function Archive-IpBackup([string]$Kind,[string]$Id='') {
    $path=Get-IpBackupPath $Kind $Id
    if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination ($path+'.'+[guid]::NewGuid().ToString('N')+'.history')}
}
function Get-ActiveOnlyBackups {
    if(Test-Path -LiteralPath $script:NetworkBackupRoot){
        foreach($file in @(Get-ChildItem -LiteralPath $script:NetworkBackupRoot -Filter 'ipv4-only-*.json' -File)){
            $id=$file.BaseName.Substring('ipv4-only-'.Length)
            $backup=Read-IpBackup Only $id
            if($backup.Active){$backup}
        }
    }
}
function Get-AllIpBindings($Nic) {
    @(Get-NetAdapterBinding -Name ([WildcardPattern]::Escape([string]$Nic.Name)) -AllBindings -ErrorAction Stop)
}
function Get-IpBindings($Nic) {
    @(Get-AllIpBindings $Nic | Where-Object ComponentID -in $script:IpComponents)
}
function Get-IpBinding($Nic,[string]$Component) {
    $live=Get-SelectedNic (Get-NicId $Nic)
    if($live.PnPDeviceID -ne $Nic.PnPDeviceID){throw 'La carte reseau a ete remplacee.'}
    $binding=@(Get-AllIpBindings $live | Where-Object ComponentID -eq $Component)
    if($binding.Count -ne 1){throw ('Composant absent ou ambigu : '+$Component)}
    $binding[0]
}
function Set-IpBinding($Nic,[string]$Component,[bool]$Enabled,[switch]$Restoring) {
    if($Component -notin $script:IpComponents -and -not $Restoring){throw 'Composant reseau refuse.'}
    $binding=Get-IpBinding $Nic $Component
    # No wildcard writes. This API may automatically restart the adapter.
    Set-NetAdapterBinding -InputObject $binding -Enabled $Enabled -Confirm:$false -ErrorAction Stop | Out-Null
    if([bool](Get-IpBinding $Nic $Component).Enabled -ne $Enabled){throw ('Verification echouee : '+$Component)}
}
function Invoke-PreferIpv4 {
    if(@(Get-ActiveOnlyBackups).Count){throw 'Restaurer les modes IPv4 uniquement avant d''activer Preferer IPv4.'}
    $backup=Read-IpBackup Prefer
    $current=Get-IpRegistryState
    $target=[pscustomobject]@{Exists=$true;Kind='DWord';Value=32}
    if($null -ne $backup -and $backup.Active){
        if(Test-IpRegistryEqual $current $target){return 'Preference IPv4 deja configuree. Sauvegarde originale conservee.'}
        throw 'Preference IP modifiee hors Bastos ou operation incomplete. Restaurer avant de continuer.'
    }
    if($current.Exists -and ($current.Kind -ne 'DWord' -or [long]$current.Value -notin @(0,32))){
        throw 'IPv6 possede deja une configuration speciale. Elle est conservee : restaurer ce reglage dans son outil d''origine avant de preferer IPv4.'
    }
    Initialize-NicStorage
    Archive-IpBackup Prefer
    $backup=[pscustomobject]@{Schema=1;Kind='Prefer';MachineId=(Get-IpMachineId);Active=$true
        CreatedUtc=[DateTime]::UtcNow.ToString('o');Original=$current;Touched=$false;RebootFrom=''}
    Write-IpBackup $backup
    if(Test-IpRegistryEqual $current $target){return 'Preference IPv4 deja presente. Etat sauvegarde, sans changement.'}
    $boot=Get-IpBootId
    $backup.Touched=$true;$backup.RebootFrom=$boot
    Write-IpBackup $backup
    try {
        if(-not(Test-IpRegistryEqual (Get-IpRegistryState) $current)){throw 'Preference modifiee pendant l''operation.'}
        Set-IpRegistryState $target
        if(-not(Test-IpRegistryEqual (Get-IpRegistryState) $target)){throw 'Verification de la preference IPv4 echouee.'}
    } catch {
        $reason=$_.Exception.Message
        try {
            $live=Get-IpRegistryState
            if(-not(Test-IpRegistryEqual $live $target) -and -not(Test-IpRegistryEqual $live $current)){throw 'Modification externe detectee.'}
            Set-IpRegistryState $current
            if(-not(Test-IpRegistryEqual (Get-IpRegistryState) $current)){throw 'Retour arriere non verifie.'}
            $backup.Touched=$false;$backup.Active=$false;Write-IpBackup $backup
        } catch {throw ($reason+' Retour arriere incomplet. Sauvegarde conservee : '+$_.Exception.Message)}
        throw ($reason+' Etat initial restaure. Redemarrage conseille.')
    }
    'Preference IPv4 configuree. IPv6 et les liaisons reseau sont conserves. Redemarrer Windows pour la prise en compte.'
}
function Restore-PreferIpv4 {
    $backup=Read-IpBackup Prefer
    if($null -eq $backup -or -not $backup.Active){return 'Aucune preference IP de ce module a restaurer.'}
    $current=Get-IpRegistryState
    $target=[pscustomobject]@{Exists=$true;Kind='DWord';Value=32}
    if($backup.Touched -and -not(Test-IpRegistryEqual $current $backup.Original)){
        if(-not(Test-IpRegistryEqual $current $target)){throw 'Valeur modifiee hors Bastos. Restauration bloquee pour ne pas l''ecraser.'}
        $backup.RebootFrom=Get-IpBootId
        Write-IpBackup $backup
        Set-IpRegistryState $backup.Original
        if(-not(Test-IpRegistryEqual (Get-IpRegistryState) $backup.Original)){throw 'Verification de restauration echouee. Sauvegarde conservee.'}
    }
    $backup.Active=$false;$backup.Touched=$false
    Write-IpBackup $backup
    'Preference IP initiale restauree (y compris l''absence de valeur). Redemarrer Windows si la valeur a change.'
}
function Invoke-Ipv4Only([string]$Id) {
    $prefer=Read-IpBackup Prefer
    if($null -ne $prefer -and $prefer.Active){throw 'Restaurer Preferer IPv4 avant d''activer IPv4 uniquement.'}
    $nic=Get-SelectedNic $Id
    if([string]$nic.Status -eq 'Disabled'){throw 'Activer la carte dans Windows avant cette operation.'}
    $bindings=@(Get-AllIpBindings $nic)
    foreach($required in @('ms_tcpip','ms_tcpip6')){
        if(@($bindings | Where-Object ComponentID -eq $required).Count -ne 1){throw ('Liaison necessaire absente ou ambigue : '+$required)}
    }
    $backup=Read-IpBackup Only $Id
    if($null -ne $backup -and $backup.Active){
        if($backup.PnpId -ne $nic.PnPDeviceID){throw 'Sauvegarde appartenant a une autre carte.'}
        if($backup.Pending -or @($backup.RestorePlan).Count){throw 'Operation incomplete. Restaurer avant de continuer.'}
        foreach($entry in @($backup.Entries | Where-Object Managed)){
            if([bool](Get-IpBinding $nic $entry.Component).Enabled -ne $entry.Target){throw 'Mode IPv4 uniquement incomplet ou modifie ailleurs. Restaurer avant de continuer.'}
        }
        return 'IPv4 uniquement deja configure sur cette carte. Originaux conserves.'
    }
    Initialize-NicStorage
    Archive-IpBackup Only $Id
    $entries=@(foreach($component in @($script:IpComponents)+@($bindings.ComponentID | Where-Object {$_ -notin $script:IpComponents})){
        $found=@($bindings | Where-Object ComponentID -eq $component)
        if($found.Count -gt 1){throw ('Liaison ambigue : '+$component)}
        if($found.Count -eq 1){[pscustomobject]@{Component=$component;Original=[bool]$found[0].Enabled
            Target=$(if($component -in $script:IpComponents){$component -eq 'ms_tcpip'}else{[bool]$found[0].Enabled})
            Managed=($component -in $script:IpComponents);Touched=$false}}
    })
    $backup=[pscustomobject]@{Schema=1;Kind='Only';MachineId=(Get-IpMachineId);Active=$true
        CreatedUtc=[DateTime]::UtcNow.ToString('o');AdapterId=(Get-NicId $nic);PnpId=[string]$nic.PnPDeviceID
        Name=[string]$nic.Name;Entries=$entries;Pending=$true;RestorePlan=@()}
    Write-IpBackup $backup # Includes the IPv4 binding, even if initially disabled.
    try {
        foreach($entry in @($backup.Entries | Where-Object Managed)){
            if([bool](Get-IpBinding $nic $entry.Component).Enabled -ne $entry.Original){throw ('Liaison modifiee pendant l''operation : '+$entry.Component)}
            if($entry.Original -eq $entry.Target){continue}
            $entry.Touched=$true;Write-IpBackup $backup
            Set-IpBinding $nic $entry.Component $entry.Target
        }
        foreach($entry in $backup.Entries){
            if([bool](Get-IpBinding $nic $entry.Component).Enabled -ne $entry.Target){throw ('Verification finale echouee : '+$entry.Component)}
        }
        $backup.Pending=$false;Write-IpBackup $backup
    } catch {
        $reason=$_.Exception.Message
        try {Restore-Ipv4Only $Id | Out-Null}
        catch {throw ($reason+' Retour arriere incomplet. '+$_.Exception.Message)}
        throw ($reason+' Modifications de cette tentative annulees.')
    }
    $skipped=@($script:IpComponents | Where-Object {$_ -notin @($backup.Entries.Component)})
    'IPv4 uniquement verifie sur '+$nic.Name+'. '+@($backup.Entries | Where-Object Managed).Count+' liaison(s) geree(s), '+$skipped.Count+' absente(s) ignoree(s). Autres liaisons verifiees et sauvegarde conservee.'
}
function Restore-Ipv4Only([string]$Id) {
    $backup=Read-IpBackup Only $Id
    if($null -eq $backup -or -not $backup.Active){return 'Aucune sauvegarde IPv4 uniquement pour cette carte.'}
    $nic=Get-SelectedNic $Id
    if($nic.PnPDeviceID -ne $backup.PnpId){throw 'Sauvegarde appartenant a une autre carte. Aucune modification.'}
    if(@($backup.RestorePlan).Count -eq 0){
        # Preserve unrelated current settings when restoring a completed profile.
        # If activation crashed, its full pre-operation snapshot is the fallback.
        $plan=@(foreach($entry in $backup.Entries){
            if($entry.Touched -or $backup.Pending){$desired=$entry.Original}
            else{try{$desired=[bool](Get-IpBinding $nic $entry.Component).Enabled}catch{continue}}
            [pscustomobject]@{Component=$entry.Component;Desired=[bool]$desired}
        })
        $backup.RestorePlan=$plan;Write-IpBackup $backup
    }
    # Binding APIs can implicitly modify other bindings. Save/verify the entire
    # restoration plan, and allow one settling pass. Never report partial success.
    $ordered=@($backup.RestorePlan | Where-Object Component -ne 'ms_tcpip')+@($backup.RestorePlan | Where-Object Component -eq 'ms_tcpip')
    for($pass=0;$pass -lt 2;$pass++){
        foreach($entry in $ordered){
            try{
                if([bool](Get-IpBinding $nic $entry.Component).Enabled -ne $entry.Desired){
                    Set-IpBinding $nic $entry.Component $entry.Desired -Restoring
                }
            }catch{} # All failures are checked and retained in the final readback.
        }
    }
    $failures=@()
    foreach($entry in $ordered){
        try{if([bool](Get-IpBinding $nic $entry.Component).Enabled -ne $entry.Desired){$failures+=('Non restaure : '+$entry.Component)}}
        catch{$failures+=$_.Exception.Message}
    }
    $backup.Active=$failures.Count -gt 0
    if(-not $backup.Active){
        foreach($entry in $backup.Entries){$entry.Touched=$false}
        $backup.Pending=$false;$backup.RestorePlan=@()
    }
    Write-IpBackup $backup
    if($failures.Count){throw ('Restauration partielle. Sauvegarde conservee : '+($failures -join ' / '))}
    'Liaisons originales restaurees et verifiees sur '+$nic.Name+'. Les autres cartes restent inchangees.'
}
function Get-IpSnapshot {
    $current=Get-IpRegistryState
    $prefer=Read-IpBackup Prefer
    $onlyBackups=@(Get-ActiveOnlyBackups)
    $preferActive=$null -ne $prefer -and $prefer.Active
    $compatible=(-not $current.Exists -or ($current.Kind -eq 'DWord' -and [long]$current.Value -in @(0,32)))
    $state='Non active dans ce module'
    if($current.Exists -and $current.Kind -eq 'DWord' -and [long]$current.Value -eq 32){$state='Priorite IPv4 configuree'}
    if(-not $compatible){$state='Configuration IPv6 externe conservee - activation bloquee'}
    $reboot=$null -ne $prefer -and $prefer.RebootFrom -and $prefer.RebootFrom -eq (Get-IpBootId)
    if($reboot){$state+=' - redemarrage Windows requis'}
    if($onlyBackups.Count){$state+=' - restaurer IPv4 uniquement avant activation'}
    $adapters=@(foreach($nic in @(Get-EthernetAdapters)){
        try {
            $id=Get-NicId $nic
            $backup=Read-IpBackup Only $id
            if($null -ne $backup -and $backup.PnpId -ne $nic.PnPDeviceID){throw 'Sauvegarde d''une autre carte.'}
            $bindings=@(Get-IpBindings $nic)
            $active=$null -ne $backup -and $backup.Active
            $onlyState=if($active){'IPv4 uniquement configure dans ce module'}else{'Non active dans ce module'}
            $ready=@($bindings | Where-Object ComponentID -eq 'ms_tcpip').Count -eq 1 -and @($bindings | Where-Object ComponentID -eq 'ms_tcpip6').Count -eq 1
            if($active){foreach($entry in @($backup.Entries | Where-Object Managed)){
                $match=@($bindings | Where-Object ComponentID -eq $entry.Component)
                if($match.Count -ne 1 -or [bool]$match[0].Enabled -ne $entry.Target){$onlyState='Etat incomplet ou modifie ailleurs - restauration disponible';break}
            }}
            if($active -and ($backup.Pending -or @($backup.RestorePlan).Count)){$onlyState='Operation incomplete - restauration disponible'}
            if($preferActive){$onlyState+=' - restaurer Preferer IPv4 avant activation'}
            [pscustomobject]@{Id=$id;State=$onlyState;CanApply=($ready -and -not $active -and -not $preferActive -and [string]$nic.Status -ne 'Disabled');CanRestore=$active
                Bindings=@($bindings | Select-Object ComponentID,DisplayName,Enabled)}
        } catch {[pscustomobject]@{Id=(Get-NicId $nic);State=$_.Exception.Message;CanApply=$false;CanRestore=$false;Bindings=@()}}
    })
    [pscustomobject]@{PreferState=$state;CanPreferApply=($compatible -and -not $preferActive -and $onlyBackups.Count -eq 0)
        CanPreferRestore=$preferActive;RestartRequired=[bool]$reboot;Adapters=$adapters;ActiveOnlyCount=$onlyBackups.Count}
}
if($MyInvocation.InvocationName -eq '.'){return}
$result=[ordered]@{Success=$false;Message='';State=$null}
$lock=$null
try {
    if($IpAction -eq 'Get'){$result.State=Get-IpSnapshot;$result.Message='Lecture IP terminee. Aucun reglage modifie.'}
    else {
        Assert-NicAdministrator
        Initialize-NicStorage
        $lock=[IO.File]::Open((Join-Path $script:NetworkBackupRoot 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $result.Message=switch($IpAction){
            'PreferApply'{Invoke-PreferIpv4}
            'PreferRestore'{Restore-PreferIpv4}
            'OnlyApply'{Invoke-Ipv4Only $IpAdapterId}
            'OnlyRestore'{Restore-Ipv4Only $IpAdapterId}
        }
    }
    $result.Success=$true
} catch {$result.Message=$_.Exception.Message}
finally {if($null -ne $lock){$lock.Dispose()}}
$json=$result | ConvertTo-Json -Depth 10
if($IpResultPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($IpResultPath),$json,[Text.UTF8Encoding]::new($false))}else{$json}
if(-not $result.Success){exit 1}
