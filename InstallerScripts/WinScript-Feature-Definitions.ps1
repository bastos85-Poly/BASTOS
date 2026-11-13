Set-StrictMode -Version Latest

function New-BastosWinScriptRegistryTarget {
    param([string]$Path,[string]$Name,[ValidateSet('DWord','String')][string]$Kind,$Value)
    [pscustomobject]@{Path=$Path;Name=$Name;Kind=$Kind;Value=$Value}
}

function New-BastosWinScriptFeature {
    param(
        [string]$Key,[string]$Title,[string]$Category,[string]$Description,
        [ValidateSet('Faible','Modere','Eleve')][string]$Risk='Faible',
        [ValidateSet('Aucun','Explorateur','Session','Windows')][string]$Restart='Aucun',
        [object[]]$Registry=@(),[object[]]$Services=@(),[object[]]$Tasks=@(),
        [string[]]$DetectPaths=@(),[string[]]$DetectServices=@()
    )
    [pscustomobject]@{
        Key=$Key;Title=$Title;Category=$Category;Description=$Description;Risk=$Risk;Restart=$Restart
        Registry=@($Registry);Services=@($Services);Tasks=@($Tasks)
        DetectPaths=@($DetectPaths);DetectServices=@($DetectServices)
        Source='WinScript';SourceCommit='ff88ff2f03beff369912bcabf8ddbbf2fa55c52a'
    }
}

function Get-BastosWinScriptFeatureDefinitions {
    $features=New-Object Collections.Generic.List[object]
    $add={param($f)[void]$features.Add($f)}
    $reg={param($p,$n,$k,$v) New-BastosWinScriptRegistryTarget $p $n $k $v}
    $task={param($name) [pscustomobject]@{TaskName=$name}}

    $capabilityRoot='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    $capabilities=@(
        @{Key='AppLocation';Title='Acces des applications a la localisation';Names=@('location');Text='Empêche les applications Store d accéder à la position de l appareil.'},
        @{Key='AppCamera';Title='Acces des applications a la camera';Names=@('webcam');Text='Empêche les applications Store d utiliser la caméra.'},
        @{Key='AppMicrophone';Title='Acces des applications au microphone';Names=@('microphone');Text='Empêche les applications Store d utiliser le microphone.'},
        @{Key='AppFiles';Title='Acces des applications aux fichiers';Names=@('documentsLibrary','picturesLibrary','videosLibrary','broadFileSystemAccess');Text='Bloque les bibliothèques Documents, Images, Vidéos et l accès étendu aux fichiers.'},
        @{Key='AppAccount';Title='Acces des applications au compte';Names=@('userAccountInformation');Text='Empêche les applications de lire les informations du compte.'},
        @{Key='AppContacts';Title='Acces des applications aux contacts';Names=@('contacts');Text='Empêche les applications de lire les contacts.'},
        @{Key='AppCalls';Title='Acces des applications a l historique des appels';Names=@('phoneCallHistory');Text='Empêche les applications de lire l historique des appels.'},
        @{Key='AppMessages';Title='Acces des applications aux messages';Names=@('chat');Text='Empêche les applications de lire les messages.'},
        @{Key='AppNotifications';Title='Acces des applications aux notifications';Names=@('userNotificationListener');Text='Empêche les applications de lire les notifications.'},
        @{Key='AppEmail';Title='Acces des applications aux e-mails';Names=@('email');Text='Empêche les applications de lire les e-mails.'},
        @{Key='AppTasks';Title='Acces des applications aux taches';Names=@('userDataTasks');Text='Empêche les applications de lire les tâches utilisateur.'},
        @{Key='AppDiagnostics';Title='Acces des applications aux diagnostics';Names=@('appDiagnostics');Text='Empêche les applications d accéder aux diagnostics des autres applications.'},
        @{Key='AppCalendar';Title='Acces des applications au calendrier';Names=@('appointments');Text='Empêche les applications de lire le calendrier.'},
        @{Key='AppMotion';Title='Acces des applications aux mouvements';Names=@('activity');Text='Empêche les applications d accéder aux capteurs de mouvement.'},
        @{Key='AppRadios';Title='Controle des radios par les applications';Names=@('radios');Text='Empêche les applications de piloter Bluetooth et les autres radios.'},
        @{Key='AppRecordings';Title='Acces des applications aux enregistrements';Names=@('graphicsCaptureProgrammatic');Text='Empêche la capture programmatique de l écran par les applications.'},
        @{Key='AppScreenshotBorders';Title='Masquage des bordures de capture';Names=@('graphicsCaptureWithoutBorder');Text='Interdit aux applications de capturer sans bordure visible.'},
        @{Key='AppAIModels';Title='Acces des applications aux modeles IA';Names=@('systemAIModels');Text='Empêche les applications d utiliser les modèles IA système.'}
    )
    foreach($item in $capabilities){
        $targets=@($item.Names|ForEach-Object{&$reg (Join-Path $capabilityRoot $_) 'Value' 'String' 'Deny'})
        &$add (New-BastosWinScriptFeature -Key $item.Key -Title $item.Title -Category 'Confidentialite' -Description $item.Text -Risk 'Modere' -Registry $targets)
    }
    &$add (New-BastosWinScriptFeature -Key 'VoiceActivation' -Title 'Activation vocale des applications' -Category 'Confidentialite' -Description 'Désactive l activation vocale globale pour les applications du compte actuel.' -Registry @(
        (&$reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' 'AgentActivationEnabled' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'PhoneAccess' -Title 'Acces des applications au telephone' -Category 'Confidentialite' -Description 'Force le refus d accès aux fonctions téléphoniques par stratégie Windows.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessPhone' 'DWord' 2)))
    &$add (New-BastosWinScriptFeature -Key 'CloudSync' -Title 'Synchronisation des reglages Windows' -Category 'Confidentialite' -Description 'Désactive la synchronisation cloud des thèmes, mots de passe, langue, personnalisation et réglages Windows.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSyncUserOverride' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSyncOnPaidNetwork' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableCredentialsSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableDesktopThemeSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisablePersonalizationSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableStartLayoutSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableWebBrowserSettingSync' 'DWord' 2),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableWindowsSettingSync' 'DWord' 2),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SettingSync' 'SyncPolicy' 'DWord' 5)))
    &$add (New-BastosWinScriptFeature -Key 'ActivityHistory' -Title 'Historique des activites Windows' -Category 'Confidentialite' -Description 'Désactive le flux d activité et la chronologie Windows.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'LockScreenCamera' -Title 'Camera sur l ecran de verrouillage' -Category 'Confidentialite' -Description 'Désactive l accès à la caméra depuis l écran de verrouillage.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreenCamera' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'Biometrics' -Title 'Biometrie et Windows Hello' -Category 'Confidentialite' -Description 'Désactive la biométrie. Les empreintes et Windows Hello ne fonctionneront plus.' -Risk 'Eleve' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics' 'Enabled' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider' 'Enabled' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'PreventDeviceEncryption' -Title 'Chiffrement automatique BitLocker' -Category 'Confidentialite' -Description 'Empêche uniquement le chiffrement automatique futur. Ne déchiffre aucun disque déjà protégé.' -Risk 'Eleve' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'DisableWPBT' -Title 'Windows Platform Binary Table (WPBT)' -Category 'Confidentialite' -Description 'Empêche l exécution automatique de logiciels OEM injectés par le firmware via WPBT.' -Risk 'Eleve' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 'DWord' 1)))

    &$add (New-BastosWinScriptFeature -Key 'WindowsTelemetry' -Title 'Telemetrie Windows' -Category 'Telemetrie' -Description 'Réduit la collecte de diagnostic, CEIP, rapports d erreurs et historique d activités par stratégies documentées.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 'DWord' 0)) -Services @(
        [pscustomobject]@{Name='DiagTrack';Startup='Manual';Stop=$false},[pscustomobject]@{Name='diagsvc';Startup='Manual';Stop=$false},
        [pscustomobject]@{Name='WerSvc';Startup='Manual';Stop=$false},[pscustomobject]@{Name='wercplsupport';Startup='Manual';Stop=$false}) -Tasks @(
        (&$task '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'),
        (&$task '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'),
        (&$task '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'),
        (&$task '\Microsoft\Windows\Autochk\Proxy'),
        (&$task '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'),
        (&$task '\Microsoft\Windows\Feedback\Siuf\DmClient'),
        (&$task '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'),
        (&$task '\Microsoft\Windows\Windows Error Reporting\QueueReporting'),
        (&$task '\Microsoft\Windows\Maps\MapsUpdateTask')))
    &$add (New-BastosWinScriptFeature -Key 'SearchTelemetry' -Title 'Recherche Web, Bing et cloud' -Category 'Telemetrie' -Description 'Désactive Bing, la recherche Web, les suggestions cloud et l historique de recherche sans arrêter l indexation locale.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'DWord' 1),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'FeedbackCollection' -Title 'Demandes de commentaires Windows' -Category 'Telemetrie' -Description 'Désactive les demandes et notifications de commentaires Windows.' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'HandwritingCollection' -Title 'Collecte ecriture et saisie' -Category 'Telemetrie' -Description 'Désactive la collecte implicite de saisie, d écriture manuscrite et de contacts.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'CloudSpeech' -Title 'Reconnaissance vocale en ligne' -Category 'Telemetrie' -Description 'Désactive la reconnaissance vocale reposant sur le cloud pour le compte actuel.' -Registry @(
        (&$reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'TargetedAds' -Title 'Publicite ciblee et experiences personnalisees' -Category 'Telemetrie' -Description 'Désactive l identifiant publicitaire, Spotlight et les expériences adaptées aux diagnostics.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 'DWord' 1),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'DWord' 0),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'OfficeTelemetry' -Title 'Telemetrie Microsoft Office' -Category 'Telemetrie' -Description 'Désactive la télémétrie et les commentaires Office si Office est installé.' -DetectPaths @('HKCU:\SOFTWARE\Microsoft\Office') -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Office\Common\ClientTelemetry' 'DisableTelemetry' 'DWord' 1),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry' 'DisableTelemetry' 'DWord' 1),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common' 'QMEnable' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Feedback' 'Enabled' 'DWord' 0)) -Tasks @(
        (&$task '\Microsoft\Office\OfficeTelemetryAgentFallBack'),
        (&$task '\Microsoft\Office\OfficeTelemetryAgentLogOn'),
        (&$task '\Microsoft\Office\OfficeTelemetryAgentFallBack2016'),
        (&$task '\Microsoft\Office\OfficeTelemetryAgentLogOn2016'),
        (&$task '\Microsoft\Office\Office 15 Subscription Heartbeat'),
        (&$task '\Microsoft\Office\Office 16 Subscription Heartbeat')))
    &$add (New-BastosWinScriptFeature -Key 'ApplicationExperienceTelemetry' -Title 'Telemetrie de compatibilite des applications' -Category 'Telemetrie' -Description 'Désactive les tâches de diagnostic de compatibilité et de démarrage des applications.' -Risk 'Modere' -Tasks @(
        (&$task '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'),
        (&$task '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp'),
        (&$task '\Microsoft\Windows\Application Experience\StartupAppTask'),
        (&$task '\Microsoft\Windows\Application Experience\PcaPatchDbTask'),
        (&$task '\Microsoft\Windows\Application Experience\MareBackup')))
    &$add (New-BastosWinScriptFeature -Key 'MediaPlayerTelemetry' -Title 'Telemetrie du lecteur multimedia' -Category 'Telemetrie' -Description 'Désactive le suivi d usage et la récupération en ligne des métadonnées de Windows Media Player.' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\MediaPlayer\Preferences' 'UsageTracking' 'DWord' 0),
        (&$reg 'HKCU:\Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventCDDVDMetadataRetrieval' 'DWord' 1),
        (&$reg 'HKCU:\Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventMusicFileMetadataRetrieval' 'DWord' 1),
        (&$reg 'HKCU:\Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventRadioPresetsRetrieval' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'WindowsDRMOnline' -Title 'Acces Internet de Windows DRM' -Category 'Telemetrie' -Description 'Empêche Windows Media DRM de contacter les services en ligne. Certains médias protégés peuvent ne plus fonctionner.' -Risk 'Eleve' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\WMDRM' 'DisableOnline' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'NvidiaTelemetry' -Title 'Telemetrie NVIDIA' -Category 'Telemetrie' -Description 'Désactive l envoi de télémétrie NVIDIA lorsque le pilote NVIDIA est présent.' -DetectPaths @('HKLM:\SOFTWARE\NVIDIA Corporation') -Registry @(
        (&$reg 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 'DWord' 0),
        (&$reg 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup' 'SendTelemetryData' 'DWord' 0)) -Services @(
        [pscustomobject]@{Name='NvTelemetryContainer';Startup='Disabled';Stop=$false}) -Tasks @(
        (&$task 'NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}'),
        (&$task 'NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}'),
        (&$task 'NvTmRepOnLogon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}')))
    &$add (New-BastosWinScriptFeature -Key 'VisualStudioTelemetry' -Title 'Telemetrie Visual Studio' -Category 'Telemetrie' -Description 'Désactive SQM, les commentaires et l analyse distante IntelliCode lorsque Visual Studio est installé.' -DetectPaths @('HKLM:\SOFTWARE\Microsoft\VisualStudio','HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio') -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM' 'OptIn' 'DWord' 0),
        (&$reg 'HKCU:\Software\Microsoft\VisualStudio\Telemetry' 'TurnOffSwitch' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' 'DisableFeedbackDialog' 'DWord' 1),
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\IntelliCode' 'DisableRemoteAnalysis' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'PowerShellTelemetry' -Title 'Telemetrie PowerShell' -Category 'Telemetrie' -Description 'Définit POWERSHELL_TELEMETRY_OPTOUT pour le compte actuel.' -Registry @(
        (&$reg 'HKCU:\Environment' 'POWERSHELL_TELEMETRY_OPTOUT' 'String' '1')))
    &$add (New-BastosWinScriptFeature -Key 'CCleanerTelemetry' -Title 'Telemetrie CCleaner' -Category 'Telemetrie' -Description 'Désactive la surveillance et les offres CCleaner si le logiciel est installé.' -DetectPaths @('HKCU:\Software\Piriform\CCleaner','HKLM:\Software\Piriform\CCleaner') -Registry @(
        (&$reg 'HKCU:\Software\Piriform\CCleaner' 'Monitoring' 'DWord' 0),
        (&$reg 'HKCU:\Software\Piriform\CCleaner' 'HelpImproveCCleaner' 'DWord' 0),
        (&$reg 'HKCU:\Software\Piriform\CCleaner' 'SystemMonitoring' 'DWord' 0),
        (&$reg 'HKCU:\Software\Piriform\CCleaner' 'UpdateCheck' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'GoogleUpdates' -Title 'Mises a jour Google en arriere-plan' -Category 'Telemetrie' -Description 'Désactive les services Google Update uniquement lorsqu ils existent.' -Risk 'Modere' -Services @(
        [pscustomobject]@{Name='gupdate';Startup='Disabled';Stop=$false},[pscustomobject]@{Name='gupdatem';Startup='Disabled';Stop=$false}) -DetectServices @('gupdate','gupdatem'))
    &$add (New-BastosWinScriptFeature -Key 'AdobeUpdates' -Title 'Mises a jour Adobe en arriere-plan' -Category 'Telemetrie' -Description 'Désactive les services et la tâche Adobe Update uniquement lorsqu ils existent.' -Risk 'Modere' -Services @(
        [pscustomobject]@{Name='AdobeARMservice';Startup='Disabled';Stop=$false},[pscustomobject]@{Name='adobeupdateservice';Startup='Disabled';Stop=$false}) -Tasks @(
        (&$task '\Adobe Acrobat Update Task')) -DetectPaths @('HKLM:\SOFTWARE\Adobe','HKLM:\SOFTWARE\WOW6432Node\Adobe'))

    &$add (New-BastosWinScriptFeature -Key 'DeliveryOptimization' -Title 'Delivery Optimization entre appareils' -Category 'Divers' -Description 'Désactive le partage pair à pair des téléchargements Windows Update.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'MeteredUpdates' -Title 'Mises a jour sur connexion limitee' -Category 'Divers' -Description 'Empêche Windows Update de télécharger sur une connexion définie comme limitée.' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'AllowAutoWindowsUpdateDownloadOverMeteredNetwork' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'UpdatePauseLimit' -Title 'Limite de pause Windows Update' -Category 'Divers' -Description 'Autorise une durée de pause étendue dans Paramètres sans désactiver Windows Update.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'FlightSettingsMaxPauseDays' 'DWord' 7300)))
    &$add (New-BastosWinScriptFeature -Key 'WindowsSearchService' -Title 'Indexation Windows Search' -Category 'Performances' -Description 'Arrête et désactive l indexation Windows. La recherche de fichiers sera moins rapide.' -Risk 'Eleve' -Services @(
        [pscustomobject]@{Name='WSearch';Startup='Disabled';Stop=$true}) -DetectServices @('WSearch'))
    &$add (New-BastosWinScriptFeature -Key 'StorageSense' -Title 'Assistant Stockage automatique' -Category 'Performances' -Description 'Désactive le nettoyage automatique Storage Sense pour le compte actuel.' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'FastStartup' -Title 'Demarrage rapide Windows' -Category 'Performances' -Description 'Désactive le démarrage hybride afin d éviter certains problèmes de pilotes et mises à jour.' -Risk 'Modere' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'Transparency' -Title 'Effets de transparence Windows' -Category 'Performances' -Description 'Désactive les effets de transparence du compte actuel.' -Registry @(
        (&$reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'MouseMenuDelay' -Title 'Delais des menus et du survol souris' -Category 'Performances' -Description 'Supprime le délai des menus et du survol. L interface peut devenir plus brusque.' -Registry @(
        (&$reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' 'String' '0'),
        (&$reg 'HKCU:\Control Panel\Mouse' 'MouseHoverTime' 'String' '0')))
    &$add (New-BastosWinScriptFeature -Key 'GameBar' -Title 'Xbox Game Bar' -Category 'Jeux' -Description 'Désactive l ouverture de Game Bar et son panneau de démarrage sans désinstaller Xbox.' -Risk 'Modere' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\GameBar' 'ShowStartupPanel' 'DWord' 0)))

    &$add (New-BastosWinScriptFeature -Key 'DarkMode' -Title 'Mode sombre Windows' -Category 'Divers' -Description 'Active le thème sombre pour les applications et l interface Windows.' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 'DWord' 0),
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'ShowFileExtensions' -Title 'Extensions des fichiers' -Category 'Divers' -Description 'Affiche les extensions connues dans l Explorateur.' -Restart 'Explorateur' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'ShowHiddenFiles' -Title 'Fichiers caches' -Category 'Divers' -Description 'Affiche les fichiers cachés dans l Explorateur.' -Restart 'Explorateur' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'ClassicContextMenu' -Title 'Menu clic droit classique' -Category 'Divers' -Description 'Restaure le menu contextuel complet de Windows 10 sous Windows 11.' -Restart 'Explorateur' -Registry @(
        (&$reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' 'String' '')))
    &$add (New-BastosWinScriptFeature -Key 'EndTaskMenu' -Title 'Terminer la tache depuis la barre des taches' -Category 'Divers' -Description 'Ajoute Terminer la tâche au menu contextuel des applications de la barre des tâches.' -Registry @(
        (&$reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'RemoveHomeGallery' -Title 'Accueil et Galerie dans l Explorateur' -Category 'Divers' -Description 'Masque Accueil et Galerie dans l Explorateur et ouvre Ce PC par défaut.' -Restart 'Explorateur' -Registry @(
        (&$reg 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' 'System.IsPinnedToNameSpaceTree' 'DWord' 0),
        (&$reg 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 'DWord' 0),
        (&$reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'TaskbarLeft' -Title 'Icones de barre des taches a gauche' -Category 'Divers' -Description 'Aligne les icônes de la barre des tâches à gauche.' -Restart 'Explorateur' -Registry @(
        (&$reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'StickyKeys' -Title 'Raccourci Touches remanentes' -Category 'Divers' -Description 'Désactive le déclenchement gênant des Touches rémanentes par cinq appuis sur Maj.' -Registry @(
        (&$reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' 'String' '58')))
    &$add (New-BastosWinScriptFeature -Key 'SnapFlyout' -Title 'Menu Ancrer les fenetres' -Category 'Divers' -Description 'Désactive le menu Snap Assist affiché au survol du bouton Agrandir.' -Registry @(
        (&$reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'EnableSnapAssistFlyout' 'DWord' 0)))
    &$add (New-BastosWinScriptFeature -Key 'DetailedBSOD' -Title 'Ecran bleu detaille' -Category 'Divers' -Description 'Affiche davantage de paramètres techniques sur les écrans bleus.' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 'DWord' 1)))
    &$add (New-BastosWinScriptFeature -Key 'VerboseLogon' -Title 'Messages de connexion detailles' -Category 'Divers' -Description 'Affiche les étapes détaillées pendant la connexion, la fermeture et les mises à jour.' -Restart 'Windows' -Registry @(
        (&$reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 'DWord' 1)))

    return $features.ToArray()
}
