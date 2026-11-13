[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('ThirdParty','Microsoft','Extensions','Xbox')][string]$Category,
    [switch]$AnalyzeOnly,
    [switch]$Restore,
    [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$patterns=@{
    ThirdParty=@('*Minecraft*','*DropboxOEM*','*RandomSaladGamesLLC*','*McAfee*','ShazamEntertainmentLtd.Shazam','ClearChannelRadioDigital.iHeartRadio','SpotifyAB.SpotifyMusic','*EclipseManager*','*ActiproSoftwareLLC*','*AdobeSystemsIncorporated.AdobePhotoshopExpress*','*Duolingo-LearnLanguagesforFree*','*PandoraMediaInc*','*CandyCrush*','*BubbleWitch3Saga*','*Wunderlist*','*Flipboard*','*Twitter*','*Facebook*','*Royal Revolt*','*Sway*','*Speed Test*','*Dolby*','*Viber*','*ACGMediaPlayer*','*Netflix*','*OneCalendar*','*LinkedInForWindows*','*HiddenCity*','*Hulu*','*AdobePhotoshopExpress*')
    Microsoft=@('Microsoft.ZuneMusic','Microsoft.Whiteboard','*UserExperienceImprovementProgram*','Microsoft.Office.Lens','Microsoft.News','Microsoft.GetHelp','*BingSearch*','Microsoft.BingTravel','Microsoft.BingHealthAndFitness','Microsoft.BingFoodAndDrink','Microsoft.BingTranslator','Microsoft.AppConnector','MicrosoftCorporationII.MicrosoftFamily','*QuickAssist*','Microsoft.OutlookForWindows','Clipchamp.Clipchamp','Microsoft.3DBuilder','Microsoft.Microsoft3DViewer','Microsoft.BingWeather','Microsoft.BingSports','Microsoft.BingFinance','Microsoft.MicrosoftOfficeHub','Microsoft.BingNews','Microsoft.Office.OneNote','Microsoft.Office.Sway','Microsoft.WindowsPhone','Microsoft.CommsPhone','Microsoft.YourPhone','Microsoft.Getstarted','Microsoft.549981C3F5F10','Microsoft.Messaging','Microsoft.WindowsSoundRecorder','Microsoft.MixedReality.Portal','Microsoft.WindowsFeedbackHub','Microsoft.WindowsAlarms','Microsoft.MSPaint','Microsoft.WindowsMaps','Microsoft.MinecraftUWP','Microsoft.People','Microsoft.Wallet','Microsoft.Print3D','Microsoft.OneConnect','Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftStickyNotes','microsoft.windowscommunicationsapps','Microsoft.SkypeApp','Microsoft.GroupMe10','MSTeams','Microsoft.Todos')
    Extensions=@('Microsoft.HEIFImageExtension','Microsoft.VP9VideoExtensions','Microsoft.WebpImageExtension','Microsoft.HEVCVideoExtension','Microsoft.RawImageExtension','Microsoft.WebMediaExtensions')
    Xbox=@('Microsoft.XboxApp','Microsoft.Xbox.TCUI','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.GamingApp')
}
function Test-Match([string]$Name){foreach($pattern in $patterns[$Category]){if($Name -like $pattern){return $true}};return $false}
$backupRoot=Join-Path $env:ProgramData 'BASTOS\Backups\AppxCategories';if(-not(Test-Path -LiteralPath $backupRoot)){New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null};$backupPath=Join-Path $backupRoot ($Category+'.json')
$result=[ordered]@{Success=$false;Category=$Category;AnalyzeOnly=[bool]$AnalyzeOnly;Restore=[bool]$Restore;Detected=@();Removed=@();Restored=@();Failed=@();Remaining=@()}
try{
    if($Restore){
        if(-not(Test-Path -LiteralPath $backupPath -PathType Leaf)){throw 'Aucune sauvegarde BASTOS disponible pour cette catégorie.'}
        $backup=Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($package in @($backup.Packages)){
            try{$manifest=Join-Path ([string]$package.InstallLocation) 'AppxManifest.xml';if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'Manifeste Windows absent'};Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop;$result.Restored+=,[string]$package.Name}catch{$result.Failed+=,"$($package.Name) : $($_.Exception.Message)"}
        }
        if($result.Failed.Count -eq 0){Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue}
        $result.Success=$result.Failed.Count -eq 0
        return
    }
    $allUsers=$Category -eq 'Xbox'
    if($allUsers){try{$installed=@(Get-AppxPackage -AllUsers -ErrorAction Stop|Where-Object{Test-Match ([string]$_.Name)})}catch{if($AnalyzeOnly){$installed=@(Get-AppxPackage -ErrorAction Stop|Where-Object{Test-Match ([string]$_.Name)})}else{throw}}}else{$installed=@(Get-AppxPackage -ErrorAction Stop|Where-Object{Test-Match ([string]$_.Name)})}
    $result.Detected=@($installed|Select-Object -ExpandProperty Name -Unique)
    if(-not $AnalyzeOnly){
        if(-not(Test-Path -LiteralPath $backupPath -PathType Leaf)){[IO.File]::WriteAllText($backupPath,([pscustomobject]@{Category=$Category;SavedAt=(Get-Date).ToString('o');Packages=@($installed|Select-Object Name,PackageFullName,InstallLocation)}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
        foreach($package in $installed){try{if($allUsers){Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop}else{Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop};$result.Removed+=,[string]$package.Name}catch{$result.Failed+=,"$($package.Name) : $($_.Exception.Message)"}}
        if($allUsers){foreach($package in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue|Where-Object{Test-Match ([string]$_.DisplayName)})){try{Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop|Out-Null}catch{$result.Failed+=,"$($package.DisplayName) provisionne : $($_.Exception.Message)"}};foreach($service in @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')){Set-Service -Name $service -StartupType Manual -ErrorAction SilentlyContinue}}
    }
    $remaining=if($AnalyzeOnly){@($installed)}elseif($allUsers){@(Get-AppxPackage -AllUsers -ErrorAction Stop|Where-Object{Test-Match ([string]$_.Name)})}else{@(Get-AppxPackage -ErrorAction Stop|Where-Object{Test-Match ([string]$_.Name)})}
    $result.Remaining=@($remaining|Select-Object -ExpandProperty Name -Unique);$result.Success=$result.Failed.Count -eq 0
}catch{$result['Error']=$_.Exception.Message}
finally{[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
if($result.Success){exit 0}else{exit 1}
