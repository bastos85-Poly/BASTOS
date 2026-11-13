[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mounted = $false

function Save-AuditResult {
    param([bool]$Success,[string]$Message,[string]$SigningChannel='')
    $parent=Split-Path -Parent $ResultPath
    if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $payload=[ordered]@{Success=$Success;Message=$Message;IsoPath=[IO.Path]::GetFullPath($IsoPath);SigningChannel=$SigningChannel;Date=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Depth 3),[Text.UTF8Encoding]::new($false))
}

try {
    if(-not(Test-Path -LiteralPath $IsoPath -PathType Leaf) -or [IO.Path]::GetExtension($IsoPath) -ine '.iso'){
        throw 'Selectionne une ISO Windows officielle.'
    }
    $image=Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    $mounted=$true
    $volume=$image|Get-Volume|Where-Object DriveLetter|Select-Object -First 1
    if(-not $volume){throw 'Le volume de l ISO ne peut pas etre monte.'}
    $root="$($volume.DriveLetter):\"
    foreach($required in @('setup.exe','sources\boot.wim')){
        if(-not(Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)){throw "ISO Windows incomplete : $required absent."}
    }
    if(-not(Test-Path -LiteralPath (Join-Path $root 'sources\install.wim') -PathType Leaf) -and
       -not(Test-Path -LiteralPath (Join-Path $root 'sources\install.esd') -PathType Leaf)){
        throw 'ISO Windows incomplete : install.wim ou install.esd absent.'
    }
    $setup=Join-Path $root 'setup.exe'
    $signature=Get-AuthenticodeSignature -LiteralPath $setup
    $subject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}
    $channel=''
    if($signature.Status -eq 'Valid' -and $subject -match '(?i)Microsoft'){$channel='Retail'}
    elseif($signature.SignerCertificate -and $subject -match '(?i)^CN=Microsoft Corporation,'){$channel='Insider'}
    else{throw 'Le programme Windows Setup de cette ISO ne porte pas une signature Microsoft acceptee.'}

    $answer=Join-Path $root 'autounattend.xml'
    if(Test-Path -LiteralPath $answer -PathType Leaf){
        $answerText=[IO.File]::ReadAllText($answer,[Text.Encoding]::UTF8)
        if($answerText -match '(?i)KernelOS|KernelPan|KRNLGame|KOS[ -]?Post'){
            throw 'ISO KernelOS/KOS refusee : utilise l ISO Microsoft officielle afin de remplacer KOS Post-Install et KRNLGame par BASTOS.'
        }
        throw 'Cette ISO contient deja un fichier autounattend.xml. Le mode autonome exige une ISO Microsoft non personnalisee.'
    }
    $oemRoot=Join-Path $root 'sources\$OEM$'
    if(Test-Path -LiteralPath $oemRoot -PathType Container){
        $foreign=@(Get-ChildItem -LiteralPath $oemRoot -Recurse -File -ErrorAction SilentlyContinue|Select-Object -First 1)
        if($foreign.Count -gt 0){throw 'Cette ISO contient deja des scripts OEM/Post-Install. Le mode autonome exige une ISO Microsoft non personnalisee.'}
    }
    $foreignNames=@(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue|
        Where-Object Name -match '(?i)KRNLGame\.exe|KernelOS|KOS[ -]?Post'|Select-Object -First 5 -ExpandProperty FullName)
    if($foreignNames.Count -gt 0){throw 'Des fichiers KernelOS/KRNLGame ont ete detectes dans le media : '+($foreignNames -join ', ')}
    Save-AuditResult -Success $true -Message 'ISO Microsoft non personnalisee : aucun script KOS, KernelOS ou KRNLGame detecte.' -SigningChannel $channel
    exit 0
}catch{
    Save-AuditResult -Success $false -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
}finally{
    if($mounted){Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue|Out-Null}
}
