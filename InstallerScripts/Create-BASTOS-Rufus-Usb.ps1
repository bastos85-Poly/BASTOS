[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RufusPath,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$TargetDriveLetter,
    [Parameter(Mandatory)][int]$TargetDiskNumber,
    [Parameter(Mandatory)][int64]$TargetSize,
    [string]$TargetSerialNumber,
    [string]$TargetUniqueId,
    [Parameter(Mandatory)][string]$TargetDescription,
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Write-ProgressState([int]$Percent,[string]$Phase,[string]$Message){
    $parent=Split-Path -Parent $ProgressPath
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ProgressPath,("{0}`t{1}`t{2}" -f $Percent,$Phase,$Message),[Text.UTF8Encoding]::new($true))
}
function Save-Result([bool]$Success,[string]$Message){
    $parent=Split-Path -Parent $ResultPath
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ResultPath,([pscustomobject]@{Success=$Success;Message=$Message;DiskNumber=$TargetDiskNumber;DriveLetter=$TargetDriveLetter}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
function Assert-TargetIdentity {
    $disk=Get-Disk -Number $TargetDiskNumber -ErrorAction Stop
    if($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or [int64]$disk.Size -ne $TargetSize){throw 'L identité physique de la clé USB a changé. Opération arrêtée avant formatage.'}
    if($TargetSerialNumber -and -not[string]::Equals(([string]$disk.SerialNumber).Trim(),$TargetSerialNumber,[StringComparison]::OrdinalIgnoreCase)){throw 'Le numéro de série de la clé USB ne correspond plus à la sélection.'}
    if(-not $TargetSerialNumber -and $TargetUniqueId -and -not[string]::Equals(([string]$disk.UniqueId).Trim(),$TargetUniqueId,[StringComparison]::OrdinalIgnoreCase)){throw 'L identifiant de la clé USB ne correspond plus à la sélection.'}
    foreach($protectedPath in @($env:SystemDrive,$RufusPath)){
        $root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($protectedPath))
        if($root -match '^([A-Za-z]):\\$'){
            $partition=Get-Partition -DriveLetter $Matches[1] -ErrorAction SilentlyContinue
            if($partition -and [int]$partition.DiskNumber -eq $TargetDiskNumber){throw 'Protection BASTOS : le disque cible contient Windows ou l application.'}
        }
    }
    $targetPartition=Get-Partition -DriveLetter $TargetDriveLetter -ErrorAction Stop
    if([int]$targetPartition.DiskNumber -ne $TargetDiskNumber){throw 'La lettre de la clé USB ne correspond plus au disque sélectionné.'}
    return $disk
}

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BastosRufusNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int id);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool SetDlgItemText(IntPtr hDlg, int id, string text);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
'@

$BM_CLICK=0x00F5
$CB_GETCOUNT=0x0146
$CB_GETLBTEXT=0x0148
$CB_GETLBTEXTLEN=0x0149
$CB_SETCURSEL=0x014E
$WM_CLOSE=0x0010
$WM_COMMAND=0x0111

function Get-Text([IntPtr]$Handle){
    $builder=[Text.StringBuilder]::new(4096)
    [void][BastosRufusNative]::GetWindowText($Handle,$builder,$builder.Capacity)
    return $builder.ToString()
}
function Get-RufusDialogs([int]$ProcessId){
    $items=New-Object Collections.Generic.List[object]
    $callback=[BastosRufusNative+EnumWindowsProc]{
        param([IntPtr]$handle,[IntPtr]$state)
        [uint32]$pid=0
        [void][BastosRufusNative]::GetWindowThreadProcessId($handle,[ref]$pid)
        if($pid -eq $ProcessId){
            $classBuilder=[Text.StringBuilder]::new(128)
            [void][BastosRufusNative]::GetClassName($handle,$classBuilder,$classBuilder.Capacity)
            if($classBuilder.ToString() -eq '#32770'){
                $texts=New-Object Collections.Generic.List[string]
                $childCallback=[BastosRufusNative+EnumWindowsProc]{
                    param([IntPtr]$child,[IntPtr]$unused)
                    $value=Get-Text $child
                    if($value){$texts.Add($value)}
                    return $true
                }
                [void][BastosRufusNative]::EnumChildWindows($handle,$childCallback,[IntPtr]::Zero)
                $items.Add([pscustomobject]@{Handle=$handle;Title=(Get-Text $handle);Text=($texts -join ' | ')})
            }
        }
        return $true
    }
    [void][BastosRufusNative]::EnumWindows($callback,[IntPtr]::Zero)
    return @($items)
}
function Click-Control([IntPtr]$Window,[int]$Id){
    $control=[BastosRufusNative]::GetDlgItem($Window,$Id)
    if($control -eq [IntPtr]::Zero){return $false}
    [void][BastosRufusNative]::SendMessage($control,$BM_CLICK,[IntPtr]::Zero,[IntPtr]::Zero)
    return $true
}
function Select-TargetDevice([IntPtr]$Window,[string]$Letter){
    $combo=[BastosRufusNative]::GetDlgItem($Window,1001)
    if($combo -eq [IntPtr]::Zero){throw 'Liste des périphériques Rufus introuvable.'}
    $count=[int][BastosRufusNative]::SendMessage($combo,$CB_GETCOUNT,[IntPtr]::Zero,[IntPtr]::Zero)
    $match=-1
    for($index=0;$index -lt $count;$index++){
        $length=[int][BastosRufusNative]::SendMessage($combo,$CB_GETLBTEXTLEN,[IntPtr]$index,[IntPtr]::Zero)
        $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(($length+2)*2)
        try{
            [void][BastosRufusNative]::SendMessage($combo,$CB_GETLBTEXT,[IntPtr]$index,$buffer)
            $text=[Runtime.InteropServices.Marshal]::PtrToStringUni($buffer)
            if($text -match ("\({0}:\)" -f [regex]::Escape($Letter)) -or $text -match ("(?i)\b{0}:" -f [regex]::Escape($Letter))){$match=$index;break}
        }finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)}
    }
    if($match -lt 0){throw "Rufus ne présente pas le lecteur $Letter`: correspondant au disque $TargetDiskNumber. Opération arrêtée avant tout formatage."}
    [void][BastosRufusNative]::SendMessage($combo,$CB_SETCURSEL,[IntPtr]$match,[IntPtr]::Zero)
    $selectionChanged=[IntPtr](1001 -bor (1 -shl 16))
    [void][BastosRufusNative]::SendMessage($Window,$WM_COMMAND,$selectionChanged,$combo)
    Start-Sleep -Milliseconds 700
}

try{
    $signature=Get-AuthenticodeSignature -LiteralPath $RufusPath
    if($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)Akeo Consulting'){throw 'Signature officielle Rufus invalide.'}
    if(-not(Test-Path -LiteralPath $IsoPath -PathType Leaf) -or [IO.Path]::GetExtension($IsoPath) -ine '.iso'){throw 'ISO Windows invalide.'}
    $disk=Assert-TargetIdentity

    Write-ProgressState 4 'Création de la clé USB' 'Ouverture ou réutilisation de Rufus...'
    $instances=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -like 'rufus*' -and $_.MainWindowHandle -ne 0})
    if($instances.Count -gt 1){throw 'Plusieurs fenêtres Rufus sont ouvertes. Ferme-les puis recommence.'}
    $process=if($instances.Count -eq 1){$instances[0]}else{Start-Process -FilePath $RufusPath -PassThru}
    $deadline=[DateTime]::UtcNow.AddSeconds(25)
    while($process.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 250;$process.Refresh()}
    $window=[IntPtr]$process.MainWindowHandle
    if($window -eq [IntPtr]::Zero){throw 'Fenêtre Rufus introuvable.'}
    if($instances.Count -eq 1){
        $existingPath=try{$process.Path}catch{''}
        if(-not $existingPath -or -not[string]::Equals([IO.Path]::GetFullPath($existingPath),[IO.Path]::GetFullPath($RufusPath),[StringComparison]::OrdinalIgnoreCase)){throw 'La fenêtre Rufus existante ne correspond pas à l exécutable officiel géré par BASTOS.'}
        $existingStart=[BastosRufusNative]::GetDlgItem($window,1003)
        $existingStatus=Get-Text ([BastosRufusNative]::GetDlgItem($window,1010))
        if((Get-Text $existingStart) -match '(?i)ANNULER|CANCEL' -or $existingStatus -notmatch '^(?i:PRÊT|READY)$'){throw 'Rufus travaille déjà. Attends sa fin ou ferme-le avant de recommencer.'}
    }

    [void](Assert-TargetIdentity)
    Select-TargetDevice $window $TargetDriveLetter
    Write-ProgressState 8 'Création de la clé USB' 'Chargement de l ISO sélectionnée...'
    if(-not(Click-Control $window 1014)){throw 'Bouton de sélection ISO Rufus introuvable.'}
    $dialogDeadline=[DateTime]::UtcNow.AddSeconds(15)
    $fileDialog=$null
    while(-not $fileDialog -and [DateTime]::UtcNow -lt $dialogDeadline){
        Start-Sleep -Milliseconds 200
        $fileDialog=@(Get-RufusDialogs $process.Id|Where-Object{$_.Text -match '(?i)nom de fichier|file name'}|Select-Object -First 1)
    }
    if(-not $fileDialog){throw 'Fenêtre de sélection ISO Rufus introuvable.'}
    if(-not[BastosRufusNative]::SetDlgItemText($fileDialog.Handle,1148,$IsoPath)){throw 'Impossible de renseigner le chemin ISO.'}
    if(-not(Click-Control $fileDialog.Handle 1)){throw 'Bouton Ouvrir introuvable.'}

    $start=[BastosRufusNative]::GetDlgItem($window,1003)
    $readyDeadline=[DateTime]::UtcNow.AddSeconds(45)
    while((-not[BastosRufusNative]::IsWindowEnabled($start)) -and [DateTime]::UtcNow -lt $readyDeadline){Start-Sleep -Milliseconds 300}
    if(-not[BastosRufusNative]::IsWindowEnabled($start)){throw 'Rufus n a pas validé l ISO; aucun formatage n a été lancé.'}
    Write-ProgressState 12 'Création de la clé USB' "Dernière vérification : $TargetDescription"
    [void](Assert-TargetIdentity)
    Select-TargetDevice $window $TargetDriveLetter
    if(-not(Click-Control $window 1003)){throw 'Bouton Démarrer Rufus introuvable.'}

    $started=$false
    $confirmationDeadline=[DateTime]::UtcNow.AddMinutes(3)
    while(-not $started -and [DateTime]::UtcNow -lt $confirmationDeadline){
        Start-Sleep -Milliseconds 250
        foreach($dialog in @(Get-RufusDialogs $process.Id)){
            $combined="$($dialog.Title) | $($dialog.Text)"
            if($combined -match '(?i)Windows User Experience|Expérience utilisateur Windows|Personnaliser.*installation'){
                if(-not(Click-Control $dialog.Handle 1)){throw 'Validation des options Windows Rufus impossible.'}
                continue
            }
            if($combined -match '(?i)données.*(détruites|effacées)|data.*destroyed|ATTENTION.*USB'){
                [void](Assert-TargetIdentity)
                if(-not(Click-Control $dialog.Handle 6)){throw 'Confirmation de formatage Rufus impossible.'}
                continue
            }
            if($combined -match '(?i)\berreur\b|\berror\b|\béchec\b|\bfailed\b'){throw "Rufus signale une erreur : $combined"}
        }
        $startText=Get-Text $start
        $status=Get-Text ([BastosRufusNative]::GetDlgItem($window,1010))
        if($startText -match '(?i)ANNULER|CANCEL' -or $status -notmatch '^(?i:PRÊT|READY)$'){$started=$true}
    }
    if(-not $started){throw 'Rufus n a pas commencé l écriture. Aucun formatage automatique n a été confirmé.'}

    $completionDeadline=[DateTime]::UtcNow.AddHours(4)
    while([DateTime]::UtcNow -lt $completionDeadline){
        if($process.HasExited){throw 'Rufus s est fermé avant la fin de la création.'}
        foreach($dialog in @(Get-RufusDialogs $process.Id)){
            $combined="$($dialog.Title) | $($dialog.Text)"
            if($combined -match '(?i)\berreur\b|\berror\b|\béchec\b|\bfailed\b'){throw "Rufus signale une erreur : $combined"}
        }
        $startText=Get-Text $start
        $status=Get-Text ([BastosRufusNative]::GetDlgItem($window,1010))
        Write-ProgressState 55 'Écriture de Windows sur la clé USB' $(if($status){$status}else{'Rufus travaille...'})
        if($startText -match '^(?i:DÉMARRER|DEMARRER|START)$' -and $status -match '^(?i:PRÊT|READY)$' -and [BastosRufusNative]::IsWindowEnabled($start)){break}
        Start-Sleep -Seconds 1
    }
    if([DateTime]::UtcNow -ge $completionDeadline){throw 'Délai maximal atteint pendant l écriture Rufus.'}
    Write-ProgressState 94 'Création de la clé USB' 'Écriture Rufus terminée; finalisation par BASTOS...'
    [void][BastosRufusNative]::PostMessage($window,$WM_CLOSE,[IntPtr]::Zero,[IntPtr]::Zero)
    Save-Result $true 'Rufus a formaté et créé la clé USB avec l ISO sélectionnée.'
    exit 0
}catch{
    Save-Result $false $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
}
