[CmdletBinding()]
param(
    [ValidateSet('Monitor','Once','Status')][string]$Action='Monitor',
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$StatusPath,
    [string]$StopPath='',
    [string]$LogPath=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if(-not ('BastosGameNative' -as [type])){
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class BastosGameNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE {
        public UInt32 Version;
        public UInt32 ControlMask;
        public UInt32 StateMask;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern IntPtr OpenProcess(UInt32 access, bool inheritHandle, UInt32 processId);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool SetProcessInformation(IntPtr handle, Int32 informationClass, ref PROCESS_POWER_THROTTLING_STATE state, UInt32 size);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GetProcessInformation(IntPtr handle, Int32 informationClass, out PROCESS_POWER_THROTTLING_STATE state, UInt32 size);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(IntPtr handle, Int32 flags, StringBuilder path, ref Int32 size);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool DestroyIcon(IntPtr handle);

    public static string GetProcessImagePath(int processId) {
        const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        IntPtr handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (UInt32)processId);
        if (handle == IntPtr.Zero) return "";
        try {
            Int32 size = 32768;
            StringBuilder path = new StringBuilder(size);
            return QueryFullProcessImageName(handle, 0, path, ref size) ? path.ToString() : "";
        } finally { CloseHandle(handle); }
    }

    public static int GetExecutionSpeedThrottling(int processId) {
        const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        const UInt32 EXECUTION_SPEED = 0x1;
        IntPtr handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (UInt32)processId);
        if (handle == IntPtr.Zero) return -1;
        try {
            PROCESS_POWER_THROTTLING_STATE state;
            if (!GetProcessInformation(handle, 4, out state, (UInt32)Marshal.SizeOf(typeof(PROCESS_POWER_THROTTLING_STATE)))) return -1;
            if ((state.ControlMask & EXECUTION_SPEED) == 0) return 0;
            return (state.StateMask & EXECUTION_SPEED) != 0 ? 1 : 0;
        } finally { CloseHandle(handle); }
    }

    public static bool SetExecutionSpeedThrottling(int processId, bool enabled) {
        const UInt32 PROCESS_SET_INFORMATION = 0x0200;
        const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        const UInt32 EXECUTION_SPEED = 0x1;
        IntPtr handle = OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION, false, (UInt32)processId);
        if (handle == IntPtr.Zero) return false;
        try {
            PROCESS_POWER_THROTTLING_STATE state = new PROCESS_POWER_THROTTLING_STATE();
            state.Version = 1;
            state.ControlMask = EXECUTION_SPEED;
            state.StateMask = enabled ? EXECUTION_SPEED : 0;
            return SetProcessInformation(handle, 4, ref state, (UInt32)Marshal.SizeOf(state));
        } finally { CloseHandle(handle); }
    }
}
'@
}

function Write-BastosGameLog {
    param([string]$Message)
    if([string]::IsNullOrWhiteSpace($LogPath)){return}
    try{
        $parent=Split-Path -Parent $LogPath
        if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        Add-Content -LiteralPath $LogPath -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message) -Encoding UTF8
    }catch{}
}

function Read-BastosGameConfig {
    if(-not(Test-Path -LiteralPath $ConfigPath -PathType Leaf)){
        return [pscustomobject]@{Version=2;Enabled=$true;AutoDetect=$true;RunAtStartup=$true;OptimizeBackground=$false;Games=@();BlockedApps=@()}
    }
    $config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
    $games=@()
    foreach($game in @($config.Games)){
        $path=[string]$game.Path
        if([string]::IsNullOrWhiteSpace($path) -or -not[IO.Path]::IsPathRooted($path)){continue}
        try{$path=[IO.Path]::GetFullPath($path)}catch{continue}
        $games+=[pscustomobject]@{Path=$path;Name=[IO.Path]::GetFileName($path)}
    }
    $blocked=@()
    $blockedSource=if($null -ne $config.PSObject.Properties['BlockedApps']){@($config.BlockedApps)}else{@()}
    foreach($app in $blockedSource){
        $path=[string]$app.Path;$name=[string]$app.Name
        if($path){try{$path=[IO.Path]::GetFullPath($path)}catch{$path=''}}
        if(-not $name -and $path){$name=[IO.Path]::GetFileName($path)}
        if($name){$blocked+=[pscustomobject]@{Path=$path;Name=$name}}
    }
    return [pscustomobject]@{
        Version=2
        Enabled=if($null -ne $config.PSObject.Properties['Enabled']){[bool]$config.Enabled}else{$true}
        AutoDetect=if($null -ne $config.PSObject.Properties['AutoDetect']){[bool]$config.AutoDetect}else{$true}
        RunAtStartup=if($null -ne $config.PSObject.Properties['RunAtStartup']){[bool]$config.RunAtStartup}else{$true}
        OptimizeBackground=if($null -ne $config.PSObject.Properties['OptimizeBackground']){[bool]$config.OptimizeBackground}else{$false}
        Games=$games
        BlockedApps=$blocked
    }
}

function Get-ProcessExecutablePath {
    param([Diagnostics.Process]$Process)
    try{return [IO.Path]::GetFullPath([string]$Process.MainModule.FileName)}catch{}
    try{
        $path=[BastosGameNative]::GetProcessImagePath($Process.Id)
        if($path){return [IO.Path]::GetFullPath($path)}
    }catch{}
    return ''
}

function Write-BastosGameStatus {
    param([object[]]$ActiveGames,[int]$OptimizedBackground,[string]$State='Ready',[string]$Error='')
    try{
        $parent=Split-Path -Parent $StatusPath
        if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        $report=[ordered]@{
            Version=1;UpdatedUtc=[datetime]::UtcNow.ToString('o');ProcessId=$PID;State=$State;Error=$Error
            ActiveGames=@($ActiveGames);OptimizedBackground=$OptimizedBackground
        }
        [IO.File]::WriteAllText($StatusPath,($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    }catch{}
}

$gameOriginal=@{}
$backgroundOriginal=@{}
$backgroundNames=@('Discord','chrome','msedge','firefox','opera','brave','steamwebhelper','EpicGamesLauncher','Battle.net','OneDrive')
$internalBlockedNames=@('steam','steamservice','steamwebhelper','EpicGamesLauncher','GalaxyClient','Battle.net','Agent','Discord','obs32','obs64','Streamlabs OBS','Streamlabs','flameshot','ShareX','NVIDIA Share','RadeonSoftware','GameBar','GameBarFTServer','XboxGameBar','Overwolf','Medal','Action','XSplit.Core','XSplit.Broadcaster','chrome','msedge','firefox','opera','brave','explorer','ApplicationFrameHost','SystemSettings','devenv','Code','powershell','pwsh','cmd','conhost','WindowsTerminal','Taskmgr','Bastos-Control-Center')
$gamePathMarkers=@('\steamapps\common\','\Epic Games\','\XboxGames\','\GOG Galaxy\Games\','\GOG Games\','\Riot Games\','\Battle.net\','\Ubisoft\Ubisoft Game Launcher\games\','\EA Games\')

function Test-BastosGameBlocked {
    param([Diagnostics.Process]$Process,[string]$Path,$Config)
    if($internalBlockedNames -contains $Process.ProcessName){return $true}
    foreach($blocked in @($Config.BlockedApps)){
        $blockedName=[IO.Path]::GetFileNameWithoutExtension([string]$blocked.Name)
        if($blockedName -and [string]::Equals($blockedName,$Process.ProcessName,[StringComparison]::OrdinalIgnoreCase)){return $true}
        if($Path -and $blocked.Path -and [string]::Equals([string]$blocked.Path,$Path,[StringComparison]::OrdinalIgnoreCase)){return $true}
    }
    return $false
}

function Test-BastosGameAutomaticCandidate {
    param([Diagnostics.Process]$Process,[string]$Path,$Config)
    if(-not $Config.AutoDetect -or -not $Path -or (Test-BastosGameBlocked $Process $Path $Config)){return $false}
    try{if($Process.MainWindowHandle -eq [IntPtr]::Zero){return $false}}catch{return $false}
    if($Path.StartsWith($env:windir,[StringComparison]::OrdinalIgnoreCase)){return $false}
    foreach($marker in $gamePathMarkers){if($Path.IndexOf($marker,[StringComparison]::OrdinalIgnoreCase) -ge 0){return $true}}
    return $false
}

function Set-BastosGameProcess {
    param([Diagnostics.Process]$Process,[hashtable]$OriginalTable,[bool]$IsGame)
    if(-not $OriginalTable.ContainsKey($Process.Id)){
        try{$original=[string]$Process.PriorityClass}catch{$original='Normal'}
        try{$throttling=[BastosGameNative]::GetExecutionSpeedThrottling($Process.Id)}catch{$throttling=-1}
        $OriginalTable[$Process.Id]=[pscustomobject]@{Process=$Process;Priority=$original;Throttling=$throttling}
    }
    try{$Process.PriorityClass=if($IsGame){[Diagnostics.ProcessPriorityClass]::High}else{[Diagnostics.ProcessPriorityClass]::BelowNormal}}catch{}
    try{[void][BastosGameNative]::SetExecutionSpeedThrottling($Process.Id,(-not $IsGame))}catch{}
}

function Restore-BastosGameProcesses {
    param([hashtable]$Table)
    foreach($entry in @($Table.Values)){
        try{
            $process=$entry.Process
            if(-not $process.HasExited){
                try{$process.PriorityClass=[Diagnostics.ProcessPriorityClass][Enum]::Parse([Diagnostics.ProcessPriorityClass],[string]$entry.Priority,$true)}catch{$process.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal}
                if([int]$entry.Throttling -ge 0){try{[void][BastosGameNative]::SetExecutionSpeedThrottling($process.Id,([int]$entry.Throttling -eq 1))}catch{}}
            }
        }catch{}
    }
    $Table.Clear()
}

function Invoke-BastosGameCycle {
    param($Config)
    $active=New-Object Collections.Generic.List[object]
    $allowed=@{}
    foreach($game in @($Config.Games)){$allowed[[string]$game.Path]=[string]$game.Name}
    if([bool]$Config.Enabled){
        foreach($process in @(Get-Process -ErrorAction SilentlyContinue)){
            $path=Get-ProcessExecutablePath $process
            if(-not $path -or (Test-BastosGameBlocked $process $path $Config)){continue}
            $forced=$allowed.ContainsKey($path)
            $automatic=if($forced){$false}else{Test-BastosGameAutomaticCandidate $process $path $Config}
            if(-not $forced -and -not $automatic){continue}
            Set-BastosGameProcess -Process $process -OriginalTable $gameOriginal -IsGame $true
            $active.Add([pscustomobject]@{Name=$process.ProcessName;Path=$path;ProcessId=$process.Id;Detection=if($forced){'Forced'}else{'Automatic'}})
        }
    }
    foreach($id in @($gameOriginal.Keys)){
        try{if($gameOriginal[$id].Process.HasExited){$gameOriginal.Remove($id)}}catch{$gameOriginal.Remove($id)}
    }
    if($active.Count -gt 0 -and [bool]$Config.OptimizeBackground){
        $gameIds=@($active|ForEach-Object{[int]$_.ProcessId})
        foreach($process in @(Get-Process -Name $backgroundNames -ErrorAction SilentlyContinue)){
            if($process.Id -in $gameIds -or $process.Id -eq $PID){continue}
            Set-BastosGameProcess -Process $process -OriginalTable $backgroundOriginal -IsGame $false
        }
    }else{Restore-BastosGameProcesses -Table $backgroundOriginal}
    foreach($id in @($backgroundOriginal.Keys)){
        try{if($backgroundOriginal[$id].Process.HasExited){$backgroundOriginal.Remove($id)}}catch{$backgroundOriginal.Remove($id)}
    }
    return @($active|ForEach-Object{$_})
}

function New-BastosGameTrayIcon {
    $assetPath=Join-Path $PSScriptRoot 'Assets\Bastos-Game-Tray.png'
    if(-not(Test-Path -LiteralPath $assetPath -PathType Leaf)){return [Drawing.SystemIcons]::Application}
    $source=[Drawing.Image]::FromFile($assetPath)
    try{
        $bitmap=[Drawing.Bitmap]::new(32,32,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try{
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.CompositingQuality=[Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,32,32))
        }finally{$graphics.Dispose()}
        $handle=$bitmap.GetHicon()
        try{return [Drawing.Icon]([Drawing.Icon]::FromHandle($handle).Clone())}
        finally{[void][BastosGameNative]::DestroyIcon($handle);$bitmap.Dispose()}
    }finally{$source.Dispose()}
}

function Open-BastosGamePage {
    $nativeApp=Join-Path $PSScriptRoot 'Bastos.Native\BASTOS-Native.exe'
    if(Test-Path -LiteralPath $nativeApp -PathType Leaf){Start-Process -FilePath $nativeApp -ArgumentList '--page game'}
}

$mutex=$null
$trayIcon=$null
$trayBrandIcon=$null
try{
    if($Action -eq 'Monitor'){
        $created=$false
        $mutex=New-Object Threading.Mutex($true,'Local\BASTOS-Game-Monitor',[ref]$created)
        if(-not $created){exit 0}
        try{
            Add-Type -AssemblyName System.Windows.Forms,System.Drawing
            $trayMenu=New-Object Windows.Forms.ContextMenuStrip
            $trayStatus=New-Object Windows.Forms.ToolStripMenuItem('Bastos Game : prêt')
            $trayStatus.Enabled=$false;[void]$trayMenu.Items.Add($trayStatus);[void]$trayMenu.Items.Add('-')
            $trayOpen=New-Object Windows.Forms.ToolStripMenuItem('Ouvrir Bastos Game')
            $trayOpen.Add_Click({Open-BastosGamePage})
            [void]$trayMenu.Items.Add($trayOpen)
            $trayLists=New-Object Windows.Forms.ToolStripMenuItem('Jeux autorisés et applications bloquées')
            $trayLists.Add_Click({Open-BastosGamePage})
            [void]$trayMenu.Items.Add($trayLists);[void]$trayMenu.Items.Add('-')
            $trayStop=New-Object Windows.Forms.ToolStripMenuItem('Arrêter Bastos Game')
            $trayStop.Add_Click({try{[IO.File]::WriteAllText($StopPath,[datetime]::UtcNow.ToString('o'))}catch{}})
            [void]$trayMenu.Items.Add($trayStop)
            $trayIcon=New-Object Windows.Forms.NotifyIcon
            $trayBrandIcon=New-BastosGameTrayIcon
            $trayIcon.Icon=$trayBrandIcon;$trayIcon.Text='Bastos Game - prêt'
            $trayIcon.Add_DoubleClick({Open-BastosGamePage})
            $trayIcon.ContextMenuStrip=$trayMenu;$trayIcon.Visible=$true
        }catch{$trayIcon=$null}
    }
    $config=Read-BastosGameConfig
    if($Action -eq 'Status'){Write-BastosGameStatus -ActiveGames @() -OptimizedBackground 0 -State 'Stopped';exit 0}
    if($Action -eq 'Once'){
        $active=@(Invoke-BastosGameCycle -Config $config)
        Write-BastosGameStatus -ActiveGames $active -OptimizedBackground $backgroundOriginal.Count
        Restore-BastosGameProcesses -Table $backgroundOriginal
        Restore-BastosGameProcesses -Table $gameOriginal
        exit 0
    }
    Write-BastosGameLog 'Moniteur démarré.'
    while($true){
        if($StopPath -and (Test-Path -LiteralPath $StopPath -PathType Leaf)){break}
        $config=Read-BastosGameConfig
        if(-not[bool]$config.Enabled){break}
        $active=@(Invoke-BastosGameCycle -Config $config)
        Write-BastosGameStatus -ActiveGames $active -OptimizedBackground $backgroundOriginal.Count
        if($trayIcon){
            $label=if($active.Count){'Optimise : '+(($active|ForEach-Object Name)-join ', ')}else{'Bastos Game - prêt'}
            if($label.Length -gt 63){$label=$label.Substring(0,63)}
            $trayIcon.Text=$label;$trayStatus.Text=$label;[Windows.Forms.Application]::DoEvents()
        }
        Start-Sleep -Milliseconds 750
    }
}catch{
    Write-BastosGameLog ('Erreur : '+$_.Exception.Message)
    Write-BastosGameStatus -ActiveGames @() -OptimizedBackground 0 -State 'Error' -Error $_.Exception.Message
    exit 1
}finally{
    Restore-BastosGameProcesses -Table $backgroundOriginal
    Restore-BastosGameProcesses -Table $gameOriginal
    if($trayIcon){$trayIcon.Visible=$false;$trayIcon.Dispose()}
    if($trayBrandIcon){$trayBrandIcon.Dispose()}
    if($Action -eq 'Monitor'){Write-BastosGameStatus -ActiveGames @() -OptimizedBackground 0 -State 'Stopped';Write-BastosGameLog 'Moniteur arrêté.'}
    if($mutex){try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
}
