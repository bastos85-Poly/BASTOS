Set-StrictMode -Version Latest

function Invoke-BastosRamMap {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory)][ValidateSet('Install','Uninstall')][string]$Action,
  [string]$PortableRoot=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BASTOS\Software\Portable'),
  [string]$DesktopPath=[Environment]::GetFolderPath('DesktopDirectory'),
  [string]$ProgramsPath=[Environment]::GetFolderPath('Programs')
 )
 $ErrorActionPreference='Stop'
 if (-not $DesktopPath -or -not $ProgramsPath) { throw 'Bureau ou menu Démarrer indisponible pour cet utilisateur.' }
 $root=[IO.Path]::GetFullPath($PortableRoot).TrimEnd('\')+'\'
 $folder=[IO.Path]::GetFullPath((Join-Path $root 'RAMMap'))
 if (-not ($folder+'\').StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Dossier RAMMap hors de la zone BASTOS.' }
 $target=Join-Path $folder 'RAMMap64.exe'
 $marker=Join-Path $folder 'BASTOS-installed.json'
 $links=@((Join-Path $DesktopPath 'RAMMap 64.lnk'),(Join-Path $ProgramsPath 'RAMMap 64.lnk'))
 $shell=New-Object -ComObject WScript.Shell
 $stage=$null
 try {
  # Never overwrite an unrelated shortcut with the same display name.
  foreach ($link in $links) {
   if (Test-Path -LiteralPath $link) {
    $existing=$shell.CreateShortcut($link)
    if ($existing.TargetPath -ne $target) { throw "Un raccourci RAMMap 64 différent existe déjà : $link" }
   }
  }
  if (Get-Process -Name RAMMap64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $target }) { throw 'Ferme RAMMap 64 avant de modifier son installation.' }
  if ($Action -eq 'Uninstall') {
   # Remove only BASTOS-managed files; preserve any memory snapshots the user saved here.
   if ((Test-Path -LiteralPath $folder) -and -not (Test-Path -LiteralPath $marker)) {
    throw 'Ce dossier RAMMap ne porte pas le marqueur BASTOS. Suppression refusée.'
   }
   foreach ($name in @('RAMMap64.exe','Eula.txt','BASTOS-installed.json')) {
    $managed=Join-Path $folder $name
    if (Test-Path -LiteralPath $managed) { Remove-Item -LiteralPath $managed -Force }
   }
   foreach ($link in $links) { if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force } }
   if ((Test-Path -LiteralPath $folder) -and @(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) { Remove-Item -LiteralPath $folder }
   return 'RAMMap 64 et ses raccourcis Bureau/menu Démarrer ont été désinstallés. Les éventuels instantanés mémoire sont conservés.'
  }
  if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $marker)) { throw 'Une copie RAMMap non gérée par BASTOS existe dans le dossier cible.' }
  $stage=Join-Path ([IO.Path]::GetTempPath()) ('BASTOS-RAMMap-'+[Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  $archivePath=Join-Path $stage 'RAMMap.zip'
  Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/RAMMap.zip' -OutFile $archivePath -UseBasicParsing
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
   foreach ($name in @('RAMMap64.exe','Eula.txt')) {
    $entry=$archive.GetEntry($name)
    if ($null -eq $entry) { throw "Fichier officiel absent de l’archive : $name" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $stage $name),$true)
   }
  } finally { $archive.Dispose() }
  $downloaded=Join-Path $stage 'RAMMap64.exe'
  $signature=Get-AuthenticodeSignature -LiteralPath $downloaded
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
   throw "La signature Microsoft de RAMMap64.exe n’est pas valide."
  }
  $bytes=[IO.File]::ReadAllBytes($downloaded)
  if ($bytes.Length -lt 64) { throw 'Exécutable RAMMap invalide.' }
  $pe=[BitConverter]::ToInt32($bytes,60)
  if ($pe -lt 0 -or $pe -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) {
   throw 'RAMMap téléchargé ne correspond pas à Windows x64.'
  }
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  # Validate the complete download before replacing the installed binary.
  foreach ($name in @('RAMMap64.exe','Eula.txt')) { Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $folder $name) -Force }
  # The ownership marker also allows recovery if a shortcut cannot be created.
  @{Name='RAMMap 64';Source='https://learn.microsoft.com/sysinternals/downloads/rammap';SHA256=(Get-FileHash -LiteralPath $target).Hash} |
   ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
  foreach ($link in $links) {
   New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force | Out-Null
   $shortcut=$shell.CreateShortcut($link)
   $shortcut.TargetPath=$target
   $shortcut.Arguments=''
   $shortcut.WorkingDirectory=$folder
   $shortcut.IconLocation=$target+',0'
   $shortcut.Description='RAMMap 64 — Microsoft Sysinternals'
   $shortcut.Save()
   if (-not (Test-Path -LiteralPath $link) -or $shell.CreateShortcut($link).TargetPath -ne $target) { throw 'Échec de vérification du raccourci RAMMap 64.' }
  }
  return 'RAMMap 64 est installé. Ses raccourcis sont disponibles sur le Bureau et dans le menu Démarrer.'
 } finally {
  if ($stage -and (Test-Path -LiteralPath $stage)) {
   $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
   $resolvedStage=[IO.Path]::GetFullPath($stage)
   if ($resolvedStage.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedStage) -like 'BASTOS-RAMMap-*') {
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
   }
  }
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
 }
}
Export-ModuleMember -Function Invoke-BastosRamMap
