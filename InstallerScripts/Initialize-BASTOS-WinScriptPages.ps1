Set-StrictMode -Version Latest

function Set-BastosWinScriptToggleVisual {
    param([Parameter(Mandatory)][Windows.Forms.CheckBox]$Toggle)
    if($Toggle -is [BastosToggleSwitch]){
        $Toggle.OnColor=$script:Colors.Accent2
        $Toggle.OffColor=[Drawing.ColorTranslator]::FromHtml('#45475A')
        $Toggle.BackColor=$script:Colors.Panel
    }
    $Toggle.Text='';$Toggle.Invalidate()
}

function Get-BastosWinScriptStateText {
    param($Item)
    if(-not [bool]$Item.Available){return 'Non installé ou non applicable'}
    if([bool]$Item.Active){return "Appliqué · risque $($Item.Risk.ToLower())"}
    if([bool]$Item.BackupAvailable){return 'Modifié ou partiel · restauration disponible'}
    return 'Configuration Windows actuelle'
}

function Set-BastosWinScriptStatusReport {
    param([Parameter(Mandatory)]$Report,[switch]$FromCache)
    if(-not [bool]$Report.Success){throw [string]$Report.Error}
    $script:UpdatingWinScriptSwitches=$true
    try{
        foreach($item in @($Report.Items)){
            $key=[string]$item.Option
            if($script:WinScriptFeatureStatusLabels.ContainsKey($key)){
                $label=$script:WinScriptFeatureStatusLabels[$key]
                $label.Text=(Get-BastosWinScriptStateText $item)+$(if($FromCache){' · dernier état connu'}else{''})
                $label.ForeColor=if(-not [bool]$item.Available){$script:Colors.Muted}elseif([bool]$item.Active){$script:Colors.Positive}else{$script:Colors.Muted}
            }
            if($script:WinScriptFeatureSwitches.ContainsKey($key)){
                $toggle=$script:WinScriptFeatureSwitches[$key]
                $toggle.BastosStatusUpdate=$true
                try{$toggle.Checked=[bool]$item.Active;$toggle.Enabled=[bool]$item.Available;if($toggle.Parent){$toggle.Parent.Visible=[bool]$item.Available};Set-BastosWinScriptToggleVisual $toggle}
                finally{$toggle.BastosStatusUpdate=$false}
            }
        }
    }finally{$script:UpdatingWinScriptSwitches=$false}
}

function Save-BastosWinScriptStatusCache {
    param([Parameter(Mandatory)]$Report)
    $itemsByKey=@{}
    if(Test-Path -LiteralPath $script:WinScriptStatusCachePath -PathType Leaf){
        try{$old=Get-Content -LiteralPath $script:WinScriptStatusCachePath -Raw -Encoding UTF8|ConvertFrom-Json;foreach($item in @($old.Items)){$itemsByKey[[string]$item.Option]=$item}}catch{}
    }
    foreach($item in @($Report.Items)){$itemsByKey[[string]$item.Option]=$item}
    $cache=[pscustomobject]@{Success=$true;CachedUtc=[datetime]::UtcNow.ToString('o');Items=@($itemsByKey.Values|Sort-Object Category,Title)}
    $parent=Split-Path -Parent $script:WinScriptStatusCachePath;if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($script:WinScriptStatusCachePath,($cache|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}

function Import-BastosWinScriptStatusCache {
    if(-not(Test-Path -LiteralPath $script:WinScriptStatusCachePath -PathType Leaf)){return $false}
    try{
        $cache=Get-Content -LiteralPath $script:WinScriptStatusCachePath -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not [bool]$cache.Success -or @($cache.Items).Count -eq 0){return $false}
        Set-BastosWinScriptStatusReport -Report $cache -FromCache
        if($script:WinScriptStatusSummaryLabel){$script:WinScriptStatusSummaryLabel.Text='États : dernier contrôle chargé · vérification silencieuse...';$script:WinScriptStatusSummaryLabel.ForeColor=$script:Colors.LightBlue}
        Write-UiLog "Dernier état des optimisations chargé immédiatement : $(@($cache.Items).Count) options." 'OK'
        return $true
    }catch{Write-UiLog "Cache des états d optimisation ignoré : $($_.Exception.Message)" 'WARN';return $false}
}

function Complete-BastosWinScriptStatusRefresh {
    $process=$script:WinScriptStatusProcess
    if(-not $process -or -not $process.HasExited){return}
    $resultPath=$script:WinScriptStatusResultPath
    $completedOption=$script:WinScriptStatusCurrentOption
    try{
        if($process.ExitCode -ne 0){throw "Le contrôle des optimisations a retourné le code $($process.ExitCode)."}
        if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Aucun rapport d état des optimisations n a été produit.'}
        $report=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json
        Set-BastosWinScriptStatusReport -Report $report
        Save-BastosWinScriptStatusCache -Report $report
        if($script:WinScriptStatusSummaryLabel){$script:WinScriptStatusSummaryLabel.Text="États : à jour · $(Get-Date -Format 'HH:mm:ss')";$script:WinScriptStatusSummaryLabel.ForeColor=$script:Colors.Positive}
        if($completedOption -eq 'All'){Write-UiLog "États des optimisations actualisés en arrière-plan : $(@($report.Items).Count) options." 'OK'}
    }catch{if($script:WinScriptStatusSummaryLabel){$script:WinScriptStatusSummaryLabel.Text='États : vérification à relancer';$script:WinScriptStatusSummaryLabel.ForeColor=$script:Colors.Warning};Write-UiLog "État des optimisations indisponible : $($_.Exception.Message)" 'WARN'}
    finally{
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
        try{$process.Dispose()}catch{}
        $script:WinScriptStatusProcess=$null;$script:WinScriptStatusResultPath='';$script:WinScriptStatusCurrentOption=''
    }
    $pending=$script:WinScriptPendingStatusCategory;$script:WinScriptPendingStatusCategory=''
    if($pending){Start-BastosWinScriptFeatureStatusRefresh -Category $pending}elseif($script:WinScriptStatusTimer){$script:WinScriptStatusTimer.Stop()}
}

function Start-BastosWinScriptFeatureStatusRefresh {
    param([string]$Category='')
    if($UiSmokeTest -or -not(Test-Path -LiteralPath $script:WinScriptFeatureWorkerScript -PathType Leaf)){return}
    $workerOption=if([string]::IsNullOrWhiteSpace($Category)){'All'}else{"Category:$Category"}
    if($script:WinScriptStatusProcess -and -not $script:WinScriptStatusProcess.HasExited){
        if($Category -and $workerOption -ne $script:WinScriptStatusCurrentOption){$script:WinScriptPendingStatusCategory=$Category}
        return
    }
    if($script:WinScriptStatusProcess){Complete-BastosWinScriptStatusRefresh;if($script:WinScriptStatusProcess){return}}
    $resultPath=Join-Path $script:LogRoot ("WinScript-Status-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try{
        $script:WinScriptStatusResultPath=$resultPath;$script:WinScriptStatusCurrentOption=$workerOption
        if($script:WinScriptStatusSummaryLabel){$script:WinScriptStatusSummaryLabel.Text=$(if($workerOption -eq 'All'){'États : vérification complète en arrière-plan...'}else{'États : actualisation de la catégorie...'});$script:WinScriptStatusSummaryLabel.ForeColor=$script:Colors.LightBlue}
        $script:WinScriptStatusProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Option "{1}" -Action Status -ResultPath "{2}"' -f $script:WinScriptFeatureWorkerScript,$workerOption,$resultPath) -PassThru -WindowStyle Hidden
        if(-not $script:WinScriptStatusTimer){
            $script:WinScriptStatusTimer=New-Object Windows.Forms.Timer;$script:WinScriptStatusTimer.Interval=200
            $script:WinScriptStatusTimer.Add_Tick({Complete-BastosWinScriptStatusRefresh})
        }
        $script:WinScriptStatusTimer.Start()
    }catch{$script:WinScriptStatusProcess=$null;Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue;Write-UiLog "Démarrage du contrôle des optimisations impossible : $($_.Exception.Message)" 'WARN'}
}

function Refresh-BastosWinScriptFeatureStatus {
    param([string]$Category='')
    Start-BastosWinScriptFeatureStatusRefresh -Category $Category
}

function Initialize-BastosWinScriptStatusAtStartup {
    if($UiSmokeTest){return}
    [void](Import-BastosWinScriptStatusCache)
    Start-BastosWinScriptFeatureStatusRefresh
}

function Invoke-BastosWinScriptFeature {
    param([Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Action)
    $title=[string]$Definition.Title
    if([string]$Definition.Risk -eq 'Eleve'){
        $impact="Option avancée à risque élevé.`r`n`r`n$($Definition.Description)`r`n`r`nRedémarrage : $($Definition.Restart).`r`nRestauration : sauvegarde exacte BASTOS créée avant application.`r`n`r`nContinuer ?"
        if([Windows.Forms.MessageBox]::Show($impact,$title,'YesNo','Warning') -ne [Windows.Forms.DialogResult]::Yes){Refresh-BastosWinScriptFeatureStatus -Category ([string]$Definition.Category);return}
    }
    $resultPath=Join-Path $script:LogRoot ("WinScript-{0}-{1}.json" -f $Definition.Key,[guid]::NewGuid().ToString('N'))
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Option "{1}" -Action {2} -ResultPath "{3}"' -f $script:WinScriptFeatureWorkerScript,$Definition.Key,$Action,$resultPath
    try{
        $run=Invoke-ElevatedExternal -FilePath 'powershell.exe' -Arguments $arguments -Reason $(if($Action -eq 'Apply'){"Appliquer $title avec sauvegarde de l état actuel."}else{"Restaurer l état sauvegardé avant $title."}) -Title $title -Direct
        if($run.ExitCode -eq 1223){return}
        if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Aucun rapport n a été produit par le moteur BASTOS.'}
        $report=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not [bool]$report.Success){throw [string]$report.Error}
        $item=@($report.Items|Select-Object -First 1)
        Write-UiLog ("{0} : {1}. Redémarrage : {2}." -f $title,$(if($Action -eq 'Apply'){'appliqué'}else{'restauré'}),$Definition.Restart) 'OK'
        if($Definition.Restart -ne 'Aucun'){$script:StatusLabel.Text="$title : redémarrage $($Definition.Restart.ToLower()) conseillé"}
    }catch{Write-UiLog "$title : $($_.Exception.Message)" 'ERROR';Show-BastosErrorDialog -Title $title -Message $_.Exception.Message}
    finally{Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue;Refresh-BastosWinScriptFeatureStatus -Category ([string]$Definition.Category)}
}

function New-BastosWinScriptFeatureCard {
    param([Parameter(Mandatory)]$Definition)
    $card=New-CardPanel -Width 900 -Height 82
    $title=New-Object Windows.Forms.Label;$title.Text=[string]$Definition.Title;$title.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$title.ForeColor=$script:Colors.Text;$title.Location=New-Object Drawing.Point(18,9);$title.Size=New-Object Drawing.Size(570,23);$card.Controls.Add($title)
    $description=New-Object Windows.Forms.Label;$description.Text=[string]$Definition.Description;$description.Font=New-Object Drawing.Font('Segoe UI',8.5);$description.ForeColor=$script:Colors.Muted;$description.Location=New-Object Drawing.Point(18,34);$description.Size=New-Object Drawing.Size(620,38);$card.Controls.Add($description)
    $state=New-Object Windows.Forms.Label;$state.Text="Vérification en attente · risque $([string]$Definition.Risk.ToLower())";$state.Font=New-Object Drawing.Font('Segoe UI Semibold',8.3);$state.ForeColor=$script:Colors.Muted;$state.TextAlign='MiddleRight';$state.Location=New-Object Drawing.Point(620,22);$state.Size=New-Object Drawing.Size(205,35);$card.Controls.Add($state);$script:WinScriptFeatureStatusLabels[[string]$Definition.Key]=$state
    $toggle=New-Object BastosToggleSwitch;$toggle.Location=New-Object Drawing.Point(837,29);$toggle.Size=New-Object Drawing.Size(42,20);$toggle.Tag=[string]$Definition.Key
    $toggle|Add-Member -NotePropertyName BastosStatusUpdate -NotePropertyValue $false
    Set-BastosWinScriptToggleVisual $toggle
    $toggle.Add_CheckedChanged({
        Set-BastosWinScriptToggleVisual $this
        if([bool]$this.BastosStatusUpdate){return}
        $featureKey=[string]$this.Tag
        $selectedFeature=@($script:WinScriptFeatureDefinitions|Where-Object Key -eq $featureKey|Select-Object -First 1)[0]
        if($selectedFeature){Invoke-BastosWinScriptFeature -Definition $selectedFeature -Action $(if([bool]$this.Checked){'Apply'}else{'Restore'})}
    })
    $card.Controls.Add($toggle);$script:WinScriptFeatureSwitches[[string]$Definition.Key]=$toggle
    return $card
}

function New-BastosWinScriptFeaturePage {
    param([string]$Category,[string]$Title,[string]$Description,[Parameter(Mandatory)][Windows.Forms.Control]$Parent,[object[]]$Definitions)
    $page=New-Object Windows.Forms.Panel;$page.Dock='Fill';$page.BackColor=$script:Colors.Background;$Parent.Controls.Add($page);$script:OptimizationPages+=$page
    $flow=New-Object Windows.Forms.FlowLayoutPanel;$flow.Dock='Fill';$flow.AutoScroll=$true;$flow.WrapContents=$true;$flow.Padding=New-Object Windows.Forms.Padding(14);$flow.BackColor=$script:Colors.Background;$page.Controls.Add($flow)
    $header=New-CardPanel -Width 900 -Height 86
    $heading=New-Object Windows.Forms.Label;$heading.Text=$Title;$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',14);$heading.ForeColor=$script:Colors.Text;$heading.Location=New-Object Drawing.Point(20,14);$heading.AutoSize=$true;$header.Controls.Add($heading)
    $info=New-Object Windows.Forms.Label;$info.Text=$Description;$info.ForeColor=$script:Colors.Muted;$info.Location=New-Object Drawing.Point(21,48);$info.Size=New-Object Drawing.Size(850,42);$header.Controls.Add($info);$flow.Controls.Add($header)
    foreach($definition in $Definitions){$flow.Controls.Add((New-BastosWinScriptFeatureCard $definition))}
    $script:WinScriptPageIndexes[$Category]=$script:OptimizationPages.Count-1
    return $flow
}

function Initialize-BastosWinScriptFeaturePages {
    param([Parameter(Mandatory)][Windows.Forms.Control]$OptimizationContent,[Parameter(Mandatory)][Windows.Forms.FlowLayoutPanel]$PerformanceFlow,[Windows.Forms.Control[]]$GamingControls=@(),[Windows.Forms.FlowLayoutPanel]$WindowsUpdateFlow)
    if(-not(Test-Path -LiteralPath $script:WinScriptFeatureDefinitionsPath -PathType Leaf)){throw 'Le catalogue d optimisations BASTOS est introuvable.'}
    . $script:WinScriptFeatureDefinitionsPath
    $script:WinScriptFeatureDefinitions=@(Get-BastosWinScriptFeatureDefinitions)

    foreach($definition in @($script:WinScriptFeatureDefinitions|Where-Object Category -eq 'Performances')){$PerformanceFlow.Controls.Add((New-BastosWinScriptFeatureCard $definition))}
    $script:WinScriptPageIndexes['Performances']=0
    [void](New-BastosWinScriptFeaturePage -Category 'Confidentialite' -Title 'Confidentialité Windows' -Description 'Autorisations des applications, synchronisation cloud et options avancées. Chaque changement est indépendant, détecté et restaurable.' -Parent $OptimizationContent -Definitions @($script:WinScriptFeatureDefinitions|Where-Object Category -eq 'Confidentialite'))
    [void](New-BastosWinScriptFeaturePage -Category 'Telemetrie' -Title 'Télémétrie' -Description 'Réglages Windows et logiciels tiers. Une option non installée reste visible mais désactivée, sans erreur.' -Parent $OptimizationContent -Definitions @($script:WinScriptFeatureDefinitions|Where-Object Category -eq 'Telemetrie'))
    $gamingFlow=New-BastosWinScriptFeaturePage -Category 'Jeux' -Title 'Jeux' -Description 'Options de jeu indépendantes. Aucun profil global n applique ces réglages automatiquement.' -Parent $OptimizationContent -Definitions @($script:WinScriptFeatureDefinitions|Where-Object Category -eq 'Jeux')
    foreach($control in @($GamingControls)){if($control){$gamingFlow.Controls.Add($control)}}
    if($GamingControls.Count -gt 0 -and $GamingControls[0]){
        # L'en-tête reste en position 0 ; Bastos Game devient la première carte de la page Jeux.
        $gamingFlow.Controls.SetChildIndex($GamingControls[0],1)
    }
    $miscFlow=New-BastosWinScriptFeaturePage -Category 'Divers' -Title 'Windows Update et interface' -Description 'Réglages Windows Update, Explorateur et interface. Les changements qui exigent Explorer, une session ou Windows sont signalés.' -Parent $OptimizationContent -Definitions @($script:WinScriptFeatureDefinitions|Where-Object Category -eq 'Divers')
    if($WindowsUpdateFlow){foreach($control in @($WindowsUpdateFlow.Controls|ForEach-Object{$_})){$miscFlow.Controls.Add($control)}}

    foreach($item in $script:OptimizationCategoryPanels){
        $key=switch([string]$item.Label.Text){'Confidentialité'{'Confidentialite'};'Télémétrie'{'Telemetrie'};'Jeux'{'Jeux'};'Performances'{'Performances'};'Divers'{'Divers'};default{''}}
        if($key -and $script:WinScriptPageIndexes.ContainsKey($key)){$item.Index=[int]$script:WinScriptPageIndexes[$key];$item.Panel.Tag=[int]$item.Index}
    }
}
