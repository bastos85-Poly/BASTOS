using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Threading;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Microsoft.VisualBasic;
using Microsoft.Win32;

namespace Bastos.Native.ViewModels;

public sealed partial class MainViewModel : ObservableObject, IDisposable
{
    public CleanerViewModel Cleaner { get; }
	private readonly AppPaths paths = new AppPaths();

	private readonly SystemStateService systemState = new SystemStateService();

	private readonly BackgroundSampler<SystemPerformanceService, PerformanceSnapshot> performance = new(() => new SystemPerformanceService(), service => service.Read());
	private bool performanceReadRunning, disposed;
	private readonly ReadRefreshCoordinator readRefreshes = new(TimeSpan.FromSeconds(30));

	private readonly DispatcherTimer performanceTimer;

	private readonly ProcessExecutionService runner = new ProcessExecutionService();

	private readonly Dictionary<string, PageViewModel> pages = new Dictionary<string, PageViewModel>();

	private readonly OperationLogService log;

	private readonly PowerShellWorkerService workers;

	private readonly NativeActionService nativeActions;

	private readonly WindowsTuningService tuning;

	private readonly PackageManagerService packages;

	private readonly SoftwareFavoritesService softwareFavorites;

	private readonly HardwareProfileService hardwareProfiles;

	private readonly BastosGameService game;

	private readonly ModuleOperationService operations;
	private readonly InterruptAffinityService interruptAffinity;
	private readonly Dictionary<string, StatusCard> interruptAffinityCards = new(StringComparer.Ordinal);

	private readonly ReinstallService reinstallService;

	private readonly TroubleshootingService troubleshooting;

	private readonly TweakingService tweaking;

	private NavigationItem? selectedNavigation;

	private PageViewModel? currentPage;

	private string browserOperationDetail = "";
	public string BrowserOperationDetail { get => browserOperationDetail; private set => SetProperty(ref browserOperationDetail, value); }

	private string browserOperationStatus = "Aucune opération en cours.";

	private bool browserProgressVisible;
	private bool browserOperationRunning;
	private double browserProgressValue;
	private string browserProgressStep = string.Empty;

	private bool chromeSelected;

	private bool firefoxSelected;

	private bool libreWolfSelected;

	private bool braveSelected;

	private bool ungoogledSelected;

	private bool thoriumSelected;
	private bool operaSelected;
	private bool heliumSelected;

	private string softwareOperationDetail = "";
	public string SoftwareOperationDetail { get => softwareOperationDetail; private set => SetProperty(ref softwareOperationDetail, value); }

	private string softwareOperationStatus = "Aucune opération en cours.";

	private string softwareSearchText = string.Empty;

	private string selectedSoftwareCategory = "Toutes les catégories";

	private int selectedSoftwareCount;

	private string administratorFullName = Environment.UserName;

	private string troubleshootingStatus = "Lecture de l’état réel de Windows…";

	private string tweakingStatus = "Lecture de l’état réel de Windows…";

	private string riskyOptimizationStatus = "Lecture des options expérimentales…";

	private string selectedTweakingCategory = "general";

	private string dashboardStatus = "Initialisation des compteurs Windows…";

	private string dashboardUpdatedAt = "";

	private PerformanceMetric selectedPrimaryMetric;

	private string selectedHardwareName = "Processeur";

	private string cpuHardwareName = "Processeur";

	private string gpuHardwareName = "Carte graphique";

	private string memoryHardwareName = "Mémoire physique";

	private string diskHardwareName = "Disque système";

	private string networkHardwareName = "Carte réseau";

	private bool hardwareProfileReady;

	private bool hardwareProfileDetectionPending;
	private readonly Dictionary<string, StatusCard> securityCardsById = new(StringComparer.OrdinalIgnoreCase);

	public string Version => paths.Version;

	public string LogoPath => paths.Script("Assets\\Bastos-Logo-Header-v4-SmoothTrails.png");

	public string MigrationLabel => "Votre PC, vos réglages.";

	public ObservableCollection<NavigationItem> Navigation { get; }

	public ReinstallViewModel Reinstall { get; }

	public NetworkOptimizationViewModel NetworkOptimization { get; }

	public OptimizationCategoriesViewModel OptimizationCategories { get; } = new OptimizationCategoriesViewModel();


	public ObservableCollection<StatusCard> GpuOptimizationCards { get; } = new();
	public ObservableCollection<StatusCard> CpuOptimizationCards { get; } = new();
	private string[] detectedGpuVendors = Array.Empty<string>();
	private bool gpuInventoryAvailable;
	internal string[]? GpuDeviceIds { get; private set; }
	public string GpuOptimizationSummary => !gpuInventoryAvailable
		? "Identification des cartes graphiques en cours… Si elle reste indisponible, relance Bastos."
		: detectedGpuVendors.Length == 0 ? "Aucun GPU AMD, NVIDIA ou Intel identifié. Aucun réglage spécifique à afficher."
		: "Réglages adaptés aux cartes détectées : " + string.Join(", ", detectedGpuVendors.Select(v => v == "intel" ? "Intel" : v.ToUpperInvariant())) + ".";
	public ObservableCollection<StatusCard> KeyboardOptimizationCards { get; } = new();
	public ObservableCollection<StatusCard> SecurityPrivacyCards { get; } = new();
	public NetworkDiscoveryViewModel NetworkDiscovery { get; }

	public RelayCommand RefreshCommand { get; }

	public RelayCommand ShowCpuMetricCommand { get; }

	public RelayCommand ShowGpuMetricCommand { get; }

	public RelayCommand ShowMemoryMetricCommand { get; }

	public AsyncRelayCommand InstallChromeCommand { get; }

	public AsyncRelayCommand InstallFirefoxCommand { get; }

	public AsyncRelayCommand InstallLibreWolfCommand { get; }

	public AsyncRelayCommand InstallBraveCommand { get; }

	public AsyncRelayCommand InstallUngoogledCommand { get; }

	public AsyncRelayCommand InstallThoriumCommand { get; }
	public AsyncRelayCommand InstallOperaCommand { get; }
	public AsyncRelayCommand InstallHeliumCommand { get; }

	public AsyncRelayCommand DebloatBraveCommand { get; }

	public AsyncRelayCommand DebloatEdgeCommand { get; }

	public AsyncRelayCommand UninstallChromeCommand { get; }

	public AsyncRelayCommand UninstallFirefoxCommand { get; }

	public AsyncRelayCommand UninstallLibreWolfCommand { get; }

	public AsyncRelayCommand UninstallBraveCommand { get; }

	public AsyncRelayCommand UninstallUngoogledCommand { get; }

	public AsyncRelayCommand UninstallThoriumCommand { get; }
	public AsyncRelayCommand UninstallOperaCommand { get; }
	public AsyncRelayCommand UninstallHeliumCommand { get; }

	public AsyncRelayCommand InstallSelectedBrowsersCommand { get; }

	public AsyncRelayCommand UninstallSelectedBrowsersCommand { get; }

	public RelayCommand ClearBrowserSelectionCommand { get; }

	public string ChromeIconPath => paths.Script("Assets\\Browsers\\google-chrome.png");

	public string FirefoxIconPath => paths.Script("Assets\\Browsers\\firefox.png");

	public string LibreWolfIconPath => paths.Script("Assets\\Browsers\\librewolf.png");

	public string BraveIconPath => paths.Script("Assets\\Browsers\\brave.png");

	public string ChromiumIconPath => paths.Script("Assets\\Browsers\\chromium.png");

	public string ThoriumIconPath => paths.Script("Assets\\Browsers\\thorium.png");
	public string HeliumIconPath => paths.Script("Assets\\Browsers\\helium.png");
	public string OperaIconPath => paths.Script("Assets\\Browsers\\opera.png");
	public string SecurityPrivacyLogoPath => paths.Script("Assets\\Security-Privacy.png");

	public string BrowserOperationStatus
	{
		get
		{
			return browserOperationStatus;
		}
		private set
		{
			SetProperty(ref browserOperationStatus, value, "BrowserOperationStatus");
		}
	}

	public bool BrowserProgressVisible
	{
		get
		{
			return browserProgressVisible;
		}
		private set
		{
			SetProperty(ref browserProgressVisible, value, "BrowserProgressVisible");
		}
	}

	public bool IsChromeInstalled => BrowserInstalled("chrome");

	public bool IsFirefoxInstalled => BrowserInstalled("firefox");

	public bool IsLibreWolfInstalled => BrowserInstalled("librewolf");

	public bool IsBraveInstalled => BrowserInstalled("brave");

	public bool IsUngoogledInstalled => Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop", "apps", "ungoogled-chromium"));

	public bool IsThoriumInstalled => Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop", "apps", "thorium-avx2"));
	public bool IsOperaInstalled => BrowserInstalled("opera");
	public bool IsHeliumInstalled => BrowserInstalled("helium");

	public bool IsChromeSelected
	{
		get
		{
			return chromeSelected;
		}
		set
		{
			if (SetProperty(ref chromeSelected, value, "IsChromeSelected"))
			{
				if (value) DeselectBrowsersExcept("chrome");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public bool IsFirefoxSelected
	{
		get
		{
			return firefoxSelected;
		}
		set
		{
			if (SetProperty(ref firefoxSelected, value, "IsFirefoxSelected"))
			{
				if (value) DeselectBrowsersExcept("firefox");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public bool IsLibreWolfSelected
	{
		get
		{
			return libreWolfSelected;
		}
		set
		{
			if (SetProperty(ref libreWolfSelected, value, "IsLibreWolfSelected"))
			{
				if (value) DeselectBrowsersExcept("librewolf");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public bool IsBraveSelected
	{
		get
		{
			return braveSelected;
		}
		set
		{
			if (SetProperty(ref braveSelected, value, "IsBraveSelected"))
			{
				if (value) DeselectBrowsersExcept("brave");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public bool IsUngoogledSelected
	{
		get
		{
			return ungoogledSelected;
		}
		set
		{
			if (SetProperty(ref ungoogledSelected, value, "IsUngoogledSelected"))
			{
				if (value) DeselectBrowsersExcept("ungoogled-chromium");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public bool IsThoriumSelected
	{
		get
		{
			return thoriumSelected;
		}
		set
		{
			if (SetProperty(ref thoriumSelected, value, "IsThoriumSelected"))
			{
				if (value) DeselectBrowsersExcept("thorium-avx2");
				UpdateBrowserSelectionCommands();
			}
		}
	}

	public int SelectedBrowserCount => new bool[8] { IsChromeSelected, IsFirefoxSelected, IsLibreWolfSelected, IsBraveSelected, IsUngoogledSelected, IsThoriumSelected, IsOperaSelected, IsHeliumSelected }.Count((bool v) => v);

	public string SelectedBrowserLabel
	{
		get
		{
			if (SelectedBrowserCount != 1)
			{
				return $"{SelectedBrowserCount} navigateurs sélectionnés";
			}
			return "1 navigateur sélectionné";
		}
	}

	public string SoftwareOperationStatus
	{
		get
		{
			return softwareOperationStatus;
		}
		private set
		{
			SetProperty(ref softwareOperationStatus, value, "SoftwareOperationStatus");
		}
	}

	public ObservableCollection<SoftwareTile> SoftwareApps { get; }

	public ObservableCollection<string> SoftwareCategories { get; }

	public ICollectionView SoftwareAppsView { get; }

	public string SoftwareSearchText
	{
		get
		{
			return softwareSearchText;
		}
		set
		{
			if (SetProperty(ref softwareSearchText, value, "SoftwareSearchText"))
			{
				RefreshSoftwareFilter();
			}
		}
	}

	public string SelectedSoftwareCategory
	{
		get
		{
			return selectedSoftwareCategory;
		}
		set
		{
			if (SetProperty(ref selectedSoftwareCategory, value, "SelectedSoftwareCategory"))
			{
				RefreshSoftwareFilter();
			}
		}
	}

	public string VisibleSoftwareLabel
	{
		get
		{
			int num = SoftwareAppsView.Cast<object>().Count();
			if (num != 1)
			{
				return $"{num} logiciels affichés";
			}
			return "1 logiciel affiché";
		}
	}

	public AsyncRelayCommand UpdateAllSoftwareCommand { get; }

	public AsyncRelayCommand UpdateRadeonTunerCommand { get; }

	public AsyncRelayCommand InstallSelectedSoftwareCommand { get; }

	public AsyncRelayCommand UninstallSelectedSoftwareCommand { get; }

	public RelayCommand ClearSoftwareSelectionCommand { get; }

	public int SelectedSoftwareCount
	{
		get
		{
			return selectedSoftwareCount;
		}
		private set
		{
			SetProperty(ref selectedSoftwareCount, value, "SelectedSoftwareCount");
		}
	}

	public ObservableCollection<TroubleshootingToggle> TroubleshootingToggles { get; }

	public ObservableCollection<TroubleshootingChoice> TroubleshootingChoices { get; }

	public AsyncRelayCommand SetAdministratorFullNameCommand { get; }

	public AsyncRelayCommand RefreshTroubleshootingCommand { get; }

	public string AdministratorFullName
	{
		get
		{
			return administratorFullName;
		}
		set
		{
			SetProperty(ref administratorFullName, value, "AdministratorFullName");
		}
	}

	public string TroubleshootingStatus
	{
		get
		{
			return troubleshootingStatus;
		}
		private set
		{
			SetProperty(ref troubleshootingStatus, value, "TroubleshootingStatus");
		}
	}

	public ObservableCollection<TroubleshootingToggle> TweakingToggles { get; }

	public ObservableCollection<TroubleshootingToggle> RiskyOptimizationToggles { get; }

	public ObservableCollection<TroubleshootingChoice> TweakingChoices { get; }

	public TroubleshootingToggle NvidiaPStateToggle { get; }

	public ObservableCollection<TweakingTool> GeneralTweakingTools { get; }

	public ObservableCollection<TweakingTool> AmdTweakingTools { get; }

	public ObservableCollection<TweakingTool> NvidiaTweakingTools { get; }

	public QuantumSchedulerModel QuantumScheduler { get; }

	public RelayCommand ShowTweakingGeneralCommand { get; }

	public RelayCommand ShowQuantumSchedulerCommand { get; }
	public RelayCommand ShowTweakingDisplayCommand { get; }

	public AsyncRelayCommand RefreshTweakingCommand { get; }

	public bool IsTweakingGeneralSelected => selectedTweakingCategory == "general";
	public bool IsQuantumSchedulerSelected => selectedTweakingCategory == "quantum";
	public bool IsTweakingDisplaySelected => selectedTweakingCategory == "display";

	private void SelectTweakingCategory(string category)
	{
		if (!SetProperty(ref selectedTweakingCategory, category)) return;
		RaisePropertyChanged(nameof(IsTweakingGeneralSelected));
		RaisePropertyChanged(nameof(IsQuantumSchedulerSelected));
		RaisePropertyChanged(nameof(IsTweakingDisplaySelected));
	}

	public double BrowserProgressValue
	{
		get => browserProgressValue;
		private set => SetProperty(ref browserProgressValue, value, nameof(BrowserProgressValue));
	}

	public string BrowserProgressStep
	{
		get => browserProgressStep;
		private set => SetProperty(ref browserProgressStep, value, nameof(BrowserProgressStep));
	}

	public string TweakingStatus
	{
		get
		{
			return tweakingStatus;
		}
		private set
		{
			SetProperty(ref tweakingStatus, value, "TweakingStatus");
		}
	}

	public string RiskyOptimizationStatus
	{
		get
		{
			return riskyOptimizationStatus;
		}
		private set
		{
			SetProperty(ref riskyOptimizationStatus, value, "RiskyOptimizationStatus");
		}
	}

	public string SelectedSoftwareLabel
	{
		get
		{
			if (SelectedSoftwareCount != 1)
			{
				return $"{SelectedSoftwareCount} applications sélectionnées";
			}
			return "1 application sélectionnée";
		}
	}

	public PerformanceMetric CpuMetric { get; }

	public PerformanceMetric GpuMetric { get; }

	public PerformanceMetric MemoryMetric { get; }

	public PerformanceMetric NetworkMetric { get; }

	public PerformanceMetric DiskMetric { get; }

	public string CpuHardwareName => cpuHardwareName;

	public string GpuHardwareName => gpuHardwareName;

	public string MemoryHardwareName => memoryHardwareName;

	public string DiskHardwareName => diskHardwareName;

	public string NetworkHardwareName => networkHardwareName;

	public string DashboardStatus
	{
		get
		{
			return dashboardStatus;
		}
		private set
		{
			SetProperty(ref dashboardStatus, value, "DashboardStatus");
		}
	}

	public string DashboardUpdatedAt
	{
		get
		{
			return dashboardUpdatedAt;
		}
		private set
		{
			SetProperty(ref dashboardUpdatedAt, value, "DashboardUpdatedAt");
		}
	}

	public PerformanceMetric SelectedPrimaryMetric
	{
		get
		{
			return selectedPrimaryMetric;
		}
		private set
		{
			if (SetProperty(ref selectedPrimaryMetric, value, "SelectedPrimaryMetric"))
			{
				RaisePropertyChanged("IsCpuMetricSelected");
				RaisePropertyChanged("IsGpuMetricSelected");
				RaisePropertyChanged("IsMemoryMetricSelected");
			}
		}
	}

	public string SelectedHardwareName
	{
		get
		{
			return selectedHardwareName;
		}
		private set
		{
			SetProperty(ref selectedHardwareName, value, "SelectedHardwareName");
		}
	}

	public bool IsCpuMetricSelected => SelectedPrimaryMetric == CpuMetric;

	public bool IsGpuMetricSelected => SelectedPrimaryMetric == GpuMetric;

	public bool IsMemoryMetricSelected => SelectedPrimaryMetric == MemoryMetric;

	public NavigationItem? SelectedNavigation
	{
		get
		{
			return selectedNavigation;
		}
		set
		{
			if (SetProperty(ref selectedNavigation, value, "SelectedNavigation") && (object)value != null)
			{
				CurrentPage = pages[value.PageKey];
                if (value.PageKey == "journal") _ = Journal.RefreshAsync();
				if (value.PageKey.Equals("reinstall", StringComparison.OrdinalIgnoreCase))
					Reinstall.RefreshDetectedKeyboard();
				if (value.PageKey is "optimizations" or "troubleshooting" or "tweaking")
				{
					_ = RefreshAllConfigurationStatesAsync();
				}
			}
		}
	}

	public PageViewModel? CurrentPage
	{
		get
		{
			return currentPage;
		}
		private set
		{
			SetProperty(ref currentPage, value, "CurrentPage");
		}
	}

	private static bool BrowserInstalled(string browser)
	{
		return (browser switch
		{
			"chrome" => new string[3]
			{
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google\\Chrome\\Application\\chrome.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google\\Chrome\\Application\\chrome.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Google\\Chrome\\Application\\chrome.exe")
			}, 
			"firefox" => new string[3]
			{
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Mozilla Firefox\\firefox.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Mozilla Firefox\\firefox.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Mozilla Firefox\\firefox.exe")
			}, 
			"librewolf" => new string[3]
			{
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LibreWolf\\librewolf.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "LibreWolf\\librewolf.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LibreWolf\\librewolf.exe")
			}, 
			"brave" => new string[3]
			{
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "BraveSoftware\\Brave-Browser\\Application\\brave.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "BraveSoftware\\Brave-Browser\\Application\\brave.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BraveSoftware\\Brave-Browser\\Application\\brave.exe")
			}, 
			"helium" => new string[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "imput\\Helium\\Application\\chrome.exe"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "imput\\Helium\\Application\\chrome.exe"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "imput\\Helium\\Application\\chrome.exe") },
			"opera" => new string[8]
			{
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Opera\\launcher.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Opera\\opera.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\Opera\\launcher.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\Opera\\opera.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\Opera GX\\launcher.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\Opera GX\\opera.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Opera\\launcher.exe"),
				Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Opera\\opera.exe")
			},
			_ => Array.Empty<string>(), 
		}).Any(File.Exists);
	}

	public RelayCommand OpenRecoveryJournalCommand { get; }
    public JournalViewModel Journal { get; }
    public InstallationVerificationViewModel Installation { get; }
    public RelayCommand OpenInstallationCommand { get; }
    private Bastos.Native.InstallationVerificationWindow? installationWindow;
    public RelayCommand OpenDiagnosticExportCommand { get; }
    private Bastos.Native.DiagnosticExportWindow? diagnosticWindow;
    public RelayCommand OpenLogMaintenanceCommand { get; }
    private Bastos.Native.LogMaintenanceWindow? maintenanceWindow;

public GamePageViewModel GameSettings { get; }
    public PowerPlanViewModel PowerPlans { get; }
    public ExtraSettingsViewModel Extras { get; }
    public CursorPackViewModel CursorPack {get;}

 public MainViewModel()
	{
		CpuMetric = new PerformanceMetric("Processeur", "#35A7FF");
		GpuMetric = new PerformanceMetric("Carte graphique", "#7C6CFF");
		MemoryMetric = new PerformanceMetric("Mémoire", "#A779FF");
		NetworkMetric = new PerformanceMetric("Internet", "#38D9A9");
		DiskMetric = new PerformanceMetric("Disques", "#FFB84D");
		selectedPrimaryMetric = CpuMetric;
		log = new OperationLogService(paths);
        Cleaner = new CleanerViewModel(paths);
        Installation = new(paths);
        OpenInstallationCommand = new(() => {
            if (installationWindow != null) { installationWindow.Activate(); return; }
            installationWindow = new(Installation) { Owner = Application.Current.MainWindow };
            var markDisplayed = Installation.PrepareMarkDisplayed();
            installationWindow.ContentRendered += (_, _) => markDisplayed();
            installationWindow.Closed += async (_, _) => { installationWindow = null; await Journal.RefreshAsync(); };
            installationWindow.Show();
            _ = Installation.CheckAsync();
        });
		workers = new PowerShellWorkerService(paths, runner, log);
		nativeActions = new NativeActionService(runner, log);
        PowerPlans = new PowerPlanViewModel(nativeActions);
		tuning = new WindowsTuningService(log);
		packages = new PackageManagerService(paths, workers, log);
		softwareFavorites = new SoftwareFavoritesService(paths);
		hardwareProfiles = new HardwareProfileService(paths);
		game = new BastosGameService(paths, log);
		if (!Environment.GetCommandLineArgs().Contains("--smoke-test")) game.Initialize();
        GameSettings = new GamePageViewModel(paths, game);
		operations = new ModuleOperationService(paths, workers, runner, log);
		interruptAffinity = new InterruptAffinityService(paths, workers, log);
		reinstallService = new ReinstallService(paths, workers, operations, log);
        Journal = new JournalViewModel(paths,resume:new OperationResumeService(paths.LogRoot,reinstallService.VerifyResumeAsync,inventory:reinstallService.ObserveResumeFiles),continueInModule:intent=>{
            SelectedNavigation=Navigation.First(item=>item.PageKey=="reinstall");
            Reinstall.ResumeFromJournal(intent);
        });
        OpenDiagnosticExportCommand = new(() => {
            if (diagnosticWindow != null) { diagnosticWindow.Activate(); return; }
            string version = typeof(MainViewModel).Assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false)
                .OfType<System.Reflection.AssemblyInformationalVersionAttribute>().FirstOrDefault()?.InformationalVersion ?? "";
            var export = new DiagnosticExportViewModel(new DiagnosticExportService(paths.LogRoot, version, Environment.OSVersion.Version.ToString()), Journal.Selected?.Reference);
            diagnosticWindow = new(export) { Owner = Application.Current.MainWindow };
            diagnosticWindow.Closed += (_, _) => diagnosticWindow = null;
            diagnosticWindow.Show();
        });
        OpenLogMaintenanceCommand = new(() => {
            if (maintenanceWindow != null) { maintenanceWindow.Activate(); return; }
            maintenanceWindow = new(new LogMaintenanceViewModel(new LogMaintenanceService(paths.LogRoot))) { Owner = Application.Current.MainWindow };
            maintenanceWindow.Closed += async (_, _) => { maintenanceWindow = null; await Journal.RefreshAsync(); };
            maintenanceWindow.Show();
        });
		troubleshooting = new TroubleshootingService(paths, workers, log);
		tweaking = new TweakingService(paths, workers, log);
		NetworkOptimization = new NetworkOptimizationViewModel(paths, workers, log);
		BuildGpuOptimizationCards();
		BuildCompetitiveCards();
        Extras = new ExtraSettingsViewModel(paths, workers);
        CursorPack=new CursorPackViewModel(paths,text=>log.Write("CursorPack",text));
		BuildKeyboardOptimizationCards();
		BuildSecurityPrivacyCards();
		NetworkDiscovery = new NetworkDiscoveryViewModel(operations);
		Reinstall = new ReinstallViewModel(reinstallService);
		Navigation = new ObservableCollection<NavigationItem>
		{
			new NavigationItem("GÉNÉRAL", "Accueil", "⌂", "home"),
			new NavigationItem("OUTILS", "Bastos Game", "\ud83c\udfae", "game"),
			new NavigationItem("MAINTENANCE", "Réinstallation facile Windows", "↻", "reinstall"),
			new NavigationItem("MAINTENANCE", "Explorateur Internet", "\ud83c\udf10", "browsers"),
			new NavigationItem("MAINTENANCE", "Mise à jour matériel", "▣", "hardware"),
			new NavigationItem("OUTILS", "Logiciels", "▣", "software"),
			new NavigationItem("OUTILS", "Optimisations", "⚡", "optimizations"),
			new NavigationItem("OUTILS", "Personnalisation", "◇", "troubleshooting"),
			new NavigationItem("OUTILS", "Réglages avancés", "⚙", "tweaking"),
			new NavigationItem("OUTILS", "Nettoyeur", "⌫", "cleaner"),
			new NavigationItem("OUTILS", "Réparation", "✓", "tests"),
			new NavigationItem("OUTILS", "Journal", "≡", "journal")
		};
		RefreshCommand = new RelayCommand(Refresh);
        OpenRecoveryJournalCommand = new RelayCommand(() => { Journal.Filter = "À vérifier"; SelectedNavigation = Navigation.First(item => item.PageKey == "journal"); _ = Journal.RefreshAsync(); });
		ShowCpuMetricCommand = new RelayCommand(delegate
		{
			SelectPrimaryMetric(CpuMetric);
		});
		ShowGpuMetricCommand = new RelayCommand(delegate
		{
			SelectPrimaryMetric(GpuMetric);
		});
		ShowMemoryMetricCommand = new RelayCommand(delegate
		{
			SelectPrimaryMetric(MemoryMetric);
		});
		InstallChromeCommand = BrowserInstallCommand("Google Chrome", "Google.Chrome", "chrome");
		InstallFirefoxCommand = BrowserInstallCommand("Mozilla Firefox", "Mozilla.Firefox", "firefox");
		InstallLibreWolfCommand = BrowserInstallCommand("LibreWolf", "LibreWolf.LibreWolf", "librewolf");
		InstallBraveCommand = BrowserInstallCommand("Brave Browser", "Brave.Brave", "brave");
		InstallUngoogledCommand = new AsyncRelayCommand(() => InstallScoopBrowser("Ungoogled Chromium", "ungoogled-chromium"));
		InstallThoriumCommand = new AsyncRelayCommand(() => InstallScoopBrowser("Thorium AVX2", "thorium-avx2"));
		InstallOperaCommand = BrowserInstallCommand("Opera", "Opera.Opera", "opera");
		InstallHeliumCommand = BrowserInstallCommand("Helium", "ImputNet.Helium", "helium");
		DebloatBraveCommand = new AsyncRelayCommand(() => DebloatBrowser("Brave"));
		DebloatEdgeCommand = new AsyncRelayCommand(() => DebloatBrowser("Edge"));
		UninstallChromeCommand = BrowserUninstallCommand("Google Chrome", "chrome");
		UninstallFirefoxCommand = BrowserUninstallCommand("Mozilla Firefox", "firefox");
		UninstallLibreWolfCommand = BrowserUninstallCommand("LibreWolf", "librewolf");
		UninstallBraveCommand = BrowserUninstallCommand("Brave Browser", "brave");
		UninstallUngoogledCommand = new AsyncRelayCommand(() => UninstallScoopBrowser("Ungoogled Chromium", "ungoogled-chromium"));
		UninstallThoriumCommand = new AsyncRelayCommand(() => UninstallScoopBrowser("Thorium AVX2", "thorium-avx2"));
		UninstallOperaCommand = BrowserUninstallCommand("Opera", "opera");
		UninstallHeliumCommand = BrowserUninstallCommand("Helium", "helium");
		InstallSelectedBrowsersCommand = new AsyncRelayCommand(InstallSelectedBrowsersAsync, () => SelectedBrowserCount > 0, () => "Coche au moins un navigateur pour continuer.");
		UninstallSelectedBrowsersCommand = new AsyncRelayCommand(UninstallSelectedBrowsersAsync, () => SelectedBrowserCount > 0, () => "Coche au moins un navigateur pour continuer.");
		ClearBrowserSelectionCommand = new RelayCommand(ClearBrowserSelection, () => SelectedBrowserCount > 0, () => "Coche au moins un navigateur pour continuer.");
		UpdateAllSoftwareCommand = new AsyncRelayCommand(() => RunSoftwareOperation("Mise à jour globale", packages.UpdateAllAsync));
		UpdateRadeonTunerCommand = new AsyncRelayCommand(UpdateRadeonTunerAsync);
		HashSet<string> favoriteIds = softwareFavorites.Load();
		SoftwareApps = new ObservableCollection<SoftwareTile>(BuildSoftwareTiles());
		foreach (SoftwareTile tile in SoftwareApps)
		{
			tile.IsFavorite = favoriteIds.Contains(tile.Package.Id);
		}
		foreach (SoftwareTile softwareApp in SoftwareApps)
		{
			softwareApp.PropertyChanged += SoftwareTilePropertyChanged;
		}
		SoftwareCategories = new ObservableCollection<string>(new string[2] { "Toutes les catégories", "Favoris" }.Concat(SoftwareApps.Select((SoftwareTile item) => item.Category).Distinct<string>(StringComparer.CurrentCultureIgnoreCase).Where(category => !category.Equals("Favoris", StringComparison.CurrentCultureIgnoreCase)).OrderBy<string, string>((string item) => item, StringComparer.CurrentCultureIgnoreCase)));
		SoftwareAppsView = CollectionViewSource.GetDefaultView(SoftwareApps);
		SoftwareAppsView.Filter = MatchesSoftwareFilter;
		InstallSelectedSoftwareCommand = new AsyncRelayCommand(InstallSelectedSoftwareAsync, HasSelectedSoftware, () => "Coche au moins un logiciel pour continuer.");
		UninstallSelectedSoftwareCommand = new AsyncRelayCommand(UninstallSelectedSoftwareAsync, HasSelectedSoftware, () => "Coche au moins un logiciel pour continuer.");
		ClearSoftwareSelectionCommand = new RelayCommand(ClearSoftwareSelection, HasSelectedSoftware, () => "Aucun logiciel n’est sélectionné.");
		TroubleshootingToggles = new ObservableCollection<TroubleshootingToggle>(BuildTroubleshootingToggles());
		TroubleshootingChoices = new ObservableCollection<TroubleshootingChoice>(BuildTroubleshootingChoices());
		SetAdministratorFullNameCommand = new AsyncRelayCommand(SetAdministratorFullNameAsync);
		RefreshTroubleshootingCommand = new AsyncRelayCommand(RefreshTroubleshootingAsync);
		TweakingToggles = new ObservableCollection<TroubleshootingToggle>(BuildTweakingToggles());
		RiskyOptimizationToggles = new ObservableCollection<TroubleshootingToggle>(BuildRiskyOptimizationToggles());
		TweakingChoices = new ObservableCollection<TroubleshootingChoice>(BuildTweakingChoices());
		NvidiaPStateToggle = new TroubleshootingToggle("NvidiaPState0", "Forcer le P-State 0 NVIDIA", "Verrouille le GPU NVIDIA sur son état de performance maximal.", initialState: false, ToggleTweakingAsync, false, "laisser le pilote adapter les fréquences évite chaleur, consommation et baisse de boost ; à réserver aux mesures comparatives.");
		GeneralTweakingTools = new ObservableCollection<TweakingTool>(BuildGeneralTweakingTools());
		AmdTweakingTools = new ObservableCollection<TweakingTool>(BuildAmdTweakingTools());
		NvidiaTweakingTools = new ObservableCollection<TweakingTool>(BuildNvidiaTweakingTools());
		QuantumScheduler = new QuantumSchedulerModel(ApplyQuantumAsync, RestoreQuantumAsync);
		ShowTweakingGeneralCommand = new RelayCommand(delegate
		{
			SelectTweakingCategory("general");
		});
		ShowQuantumSchedulerCommand = new RelayCommand(delegate
		{
			SelectTweakingCategory("quantum");
		});
		ShowTweakingDisplayCommand = new RelayCommand(() => SelectTweakingCategory("display"));
		RefreshTweakingCommand = new AsyncRelayCommand(RefreshTweakingAsync);
		BuildPages();
		OptimizationCategories.PropertyChanged += (_, eventArgs) =>
		{
			if (eventArgs.PropertyName == nameof(OptimizationCategories.Selected) && SelectedNavigation?.PageKey == "optimizations")
			{
				_ = RefreshAllConfigurationStatesAsync();
			}
		};
		HardwareProfile cachedHardware = hardwareProfiles.Load();
		if (cachedHardware != null)
		{
			ApplyHardwareProfile(cachedHardware);
		}
		else
		{
			hardwareProfileDetectionPending = true;
		}
		UpdatePerformanceDashboard();
		_ = InitializeHardwareProfileAsync();
		performanceTimer = new DispatcherTimer(DispatcherPriority.Background)
		{
			Interval = TimeSpan.FromSeconds(1.0)
		};
		performanceTimer.Tick += delegate
		{
			UpdatePerformanceDashboard();
		};
		performanceTimer.Start();
		string requestedPage = ReadArgument(Environment.GetCommandLineArgs(), "--page");
		SelectedNavigation = Navigation.FirstOrDefault((NavigationItem item) => item.PageKey.Equals(requestedPage, StringComparison.OrdinalIgnoreCase)) ?? Navigation[0];
		RefreshInstalledSoftwareAsync();
		if (!Environment.GetCommandLineArgs().Contains("--smoke-test")) EnsurePackageManagerReadyAsync();
		// Other pages load their expensive states when first visited.
		_ = Journal.RefreshAsync();
	}

	public bool IsHeliumSelected { get => heliumSelected; set { if (SetProperty(ref heliumSelected, value, nameof(IsHeliumSelected))) { if (value) DeselectBrowsersExcept("helium"); UpdateBrowserSelectionCommands(); } } }
	public bool IsOperaSelected
	{
		get => operaSelected;
		set { if (SetProperty(ref operaSelected, value, "IsOperaSelected")) { if (value) DeselectBrowsersExcept("opera"); UpdateBrowserSelectionCommands(); } }
	}

	private void BuildPages()
	{
		pages["home"] = new PageViewModel("Tableau de bord", "Les performances essentielles de ce PC, actualisées en direct", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: false, isBrowsers: false, isSoftware: false, isTroubleshooting: false, isTweaking: false, isDashboard: true);
		pages["game"] = BuildGamePage();
		pages["reinstall"] = BuildReinstallPage();
		pages["browsers"] = BuildBrowsersPage();
		pages["hardware"] = BuildHardwarePage();
		pages["optimizations"] = BuildOptimizationsPage();
		pages["software"] = BuildSoftwarePage();
		pages["troubleshooting"] = BuildTroubleshootingPage();
		pages["tweaking"] = BuildTweakingPage();
		pages["cleaner"] = new PageViewModel("Nettoyeur", "Fichiers temporaires, caches et traces inutiles · analyse avant suppression", Array.Empty<StatusCard>(), false);
		pages["tests"] = BuildTestsPage();
		pages["journal"] = BuildJournalPage();
        RebuildSettingsGroups();
	}

	private PageViewModel BuildGamePage()
	{
		BastosGameConfig bastosGameConfig = game.Load();
		List<StatusCard> list = new List<StatusCard>();
		StatusCard engine = null;
		engine = new StatusCard("Moteur Bastos Game", "Surveille les jeux autorisés sans injection et applique les optimisations de processus.", game.StatusText(), StatusTone.Success, "Démarrer", new AsyncRelayCommand(() => RunCard(engine, delegate
		{
			game.Start();
			return (Success: true, Message: game.StatusText());
		})), "Arrêter", new AsyncRelayCommand(() => RunCard(engine, delegate
		{
			game.Stop();
			return (Success: true, Message: "Arrêt demandé");
		})));
		list.Add(engine);
		StatusCard allowed = null;
		allowed = new StatusCard("Jeux autorisés", $"{bastosGameConfig.Games.Count} jeu(x) ajouté(s). La détection automatique reste disponible.", DescribeEntries(bastosGameConfig.Games), StatusTone.Neutral, "Ajouter un jeu", new AsyncRelayCommand(() => PickGame(allowed, blocked: false)), "Gérer la liste", new AsyncRelayCommand(() => ManageGameList(allowed, blocked: false)));
		list.Add(allowed);
		StatusCard blocked = null;
		blocked = new StatusCard("Applications bloquées", "Empêche un faux positif ou un jeu incompatible d’être optimisé.", DescribeEntries(bastosGameConfig.BlockedApps), StatusTone.Neutral, "Bloquer une application", new AsyncRelayCommand(() => PickGame(blocked, blocked: true)), "Gérer la liste", new AsyncRelayCommand(() => ManageGameList(blocked, blocked: true)));
		list.Add(blocked);
		StatusCard detection = null;
		detection = new StatusCard("Détection automatique", "Bibliothèques Steam, Epic, Xbox, GOG, Riot, Battle.net, Ubisoft et EA.", bastosGameConfig.AutoDetect ? "Activée" : "Désactivée", bastosGameConfig.AutoDetect ? StatusTone.Success : StatusTone.Warning, bastosGameConfig.AutoDetect ? "Désactiver" : "Activer", new AsyncRelayCommand(() => RunCard(detection, delegate
		{
			BastosGameConfig bastosGameConfig2 = game.Load();
			bastosGameConfig2.AutoDetect = !bastosGameConfig2.AutoDetect;
			game.Save(bastosGameConfig2);
			game.Restart();
			return (Success: true, Message: bastosGameConfig2.AutoDetect ? "Activée" : "Désactivée");
		})), "Ouvrir le journal", new AsyncRelayCommand(() => RunCard(detection, delegate
		{
			if (File.Exists(paths.GameLog))
			{
				operations.Open(paths.GameLog);
			}
			else
			{
				operations.Open(paths.LogRoot);
			}
			return (Success: true, Message: "Journal ouvert");
		})));
		list.Add(detection);
		return new PageViewModel("Bastos Game", "Vos jeux, vos réglages, un état clair pendant chaque partie", list, compatibilityAction: false);
	}

	private PageViewModel BuildReinstallPage()
	{
		return new PageViewModel("Réinstallation facile Windows", "Catalogue ISO par version et langue • options du compte et du clavier • USB ou partition interne", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: true);
	}

	private PageViewModel BuildBrowsersPage()
	{
		return new PageViewModel("Explorateur Internet", "Installer, configurer ou supprimer tes navigateurs Web", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: false, isBrowsers: true);
	}

	private IEnumerable<SoftwareTile> BuildSoftwareTiles()
	{
		foreach (SoftwarePackage item in packages.ReadCatalog().OrderBy((SoftwarePackage item) => item.Name, StringComparer.CurrentCultureIgnoreCase))
		{
			string path = item.Id.Replace('/', Path.DirectorySeparatorChar) + ".png";
			string iconPath = paths.Script(Path.Combine("Assets", "SoftwareIcons", path));
			yield return new SoftwareTile(item, iconPath, DescribeSoftware(item));
		}
	}

	private static string DescribeSoftware(SoftwarePackage package)
	{
		if (!string.IsNullOrWhiteSpace(package.Description))
		{
			return package.Description.Trim();
		}
		return "Description à compléter pour " + package.Name + ".";
	}

	private bool HasSelectedSoftware()
	{
		return SoftwareApps.Any((SoftwareTile item) => item.IsSelected);
	}

	private bool MatchesSoftwareFilter(object item)
	{
		if (!(item is SoftwareTile softwareTile))
		{
			return false;
		}
		bool num = SelectedSoftwareCategory == "Toutes les catégories" || (SelectedSoftwareCategory == "Favoris" ? softwareTile.IsFavorite : softwareTile.Category.Equals(SelectedSoftwareCategory, StringComparison.CurrentCultureIgnoreCase));
		string text = SoftwareSearchText.Trim();
		bool flag = text.Length == 0 || softwareTile.Name.Contains(text, StringComparison.CurrentCultureIgnoreCase) || softwareTile.Category.Contains(text, StringComparison.CurrentCultureIgnoreCase) || softwareTile.Description.Contains(text, StringComparison.CurrentCultureIgnoreCase);
		return num & flag;
	}

	private void RefreshSoftwareFilter()
	{
		SoftwareAppsView?.Refresh();
		RaisePropertyChanged("VisibleSoftwareLabel");
	}

	private void SoftwareTilePropertyChanged(object? sender, PropertyChangedEventArgs e)
	{
		if (e.PropertyName == "IsFavorite")
		{
			try
			{
				softwareFavorites.Save(SoftwareApps.Where(item => item.IsFavorite).Select(item => item.Package.Id));
				RefreshSoftwareFilter();
			}
			catch (Exception ex)
			{
				log.Write("Logiciels", "Enregistrement des favoris : " + ex.Message, error: true);
			}
			return;
		}
		if (!(e.PropertyName != "IsSelected"))
		{
			SelectedSoftwareCount = SoftwareApps.Count((SoftwareTile item) => item.IsSelected);
			RaisePropertyChanged("SelectedSoftwareLabel");
			InstallSelectedSoftwareCommand.RaiseCanExecuteChanged();
			UninstallSelectedSoftwareCommand.RaiseCanExecuteChanged();
			ClearSoftwareSelectionCommand.RaiseCanExecuteChanged();
		}
	}

	private void ClearSoftwareSelection()
	{
		foreach (SoftwareTile softwareApp in SoftwareApps)
		{
			softwareApp.IsSelected = false;
		}
	}

	private async Task InstallSelectedSoftwareAsync()
	{
        bool completed = false;
		SoftwarePackage[] selected = (from item in SoftwareApps
			where item.IsSelected
			select item.Package).ToArray();
		await RunSoftwareOperation("Installation de la sélection", async delegate
		{
			SoftwarePackage[] array = selected.Where((SoftwarePackage item) => string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
			SoftwarePackage[] special = selected.Where((SoftwarePackage item) => !string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
			(bool, string) tuple = ((array.Length == 0) ? (true, string.Empty) : (await packages.InstallManyAsync(array)));
            if (array.Length > 0) SoftwareOperationDetail = packages.LastInstallationDetail;
			(bool, string) tuple2 = tuple;
			(bool Success, string Message) normalResult = tuple2;
			(bool, string) tuple3 = await packages.ManageCustomManyAsync(special, "Install");
            completed = normalResult.Success && tuple3.Item1;
			return (Success: completed, Message: string.Join(" ", new string[2] { normalResult.Message, tuple3.Item2 }.Where((string message) => !string.IsNullOrWhiteSpace(message))));
		});
		if (completed) ClearSoftwareSelection();
		await RefreshInstalledSoftwareAsync();
	}

	private async Task UninstallSelectedSoftwareAsync()
	{
        bool uninstallSucceeded = false;
		SoftwarePackage[] selected = (from item in SoftwareApps
			where item.IsSelected
			select item.Package).ToArray();
		string text = string.Join("\n", from item in selected
			where !string.IsNullOrWhiteSpace(item.UninstallWarning)
			select "• " + item.Name + " : " + item.UninstallWarning);
		if (Bastos.Native.LocalizedMessageBox.Show($"Désinstaller complètement {selected.Length} application(s) sélectionnée(s) ?" + ((text.Length == 0) ? string.Empty : ("\n\nAttention :\n" + text)), "Suppression des logiciels", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) != MessageBoxResult.Yes)
		{
			return;
		}
		await RunSoftwareOperation("Désinstallation de la sélection", async delegate
		{
			SoftwarePackage[] array = selected.Where((SoftwarePackage item) => string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
			SoftwarePackage[] special = selected.Where((SoftwarePackage item) => !string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
			(bool, string) tuple = ((array.Length == 0) ? (true, string.Empty) : (await packages.UninstallManyAsync(array)));
			(bool, string) tuple2 = tuple;
			(bool Success, string Message) normalResult = tuple2;
			if (array.Length > 0) SoftwareOperationDetail = packages.LastUninstallationDetail;
			(bool, string) tuple3 = await packages.ManageCustomManyAsync(special, "Uninstall");
			uninstallSucceeded = normalResult.Success && tuple3.Item1;
			return (Success: normalResult.Success && tuple3.Item1, Message: string.Join(" ", new string[2] { normalResult.Message, tuple3.Item2 }.Where((string message) => !string.IsNullOrWhiteSpace(message))));
		});
		if (uninstallSucceeded) ClearSoftwareSelection();
		await RefreshInstalledSoftwareAsync();
	}

	private async Task RefreshInstalledSoftwareAsync()
	{
		try
		{
			HashSet<string> hashSet = await packages.DetectInstalledIdsAsync(SoftwareApps.Select((SoftwareTile softwareTile) => softwareTile.Package));
			foreach (SoftwareTile softwareApp in SoftwareApps)
			{
				softwareApp.IsInstalled = hashSet.Contains(softwareApp.Package.Id);
			}
			SoftwareTile[] array = SoftwareApps
				.OrderByDescending((SoftwareTile softwareTile) => softwareTile.IsInstalled)
				.ThenBy((SoftwareTile softwareTile) => softwareTile.Name, StringComparer.CurrentCultureIgnoreCase)
				.ToArray();
			SoftwareApps.Clear();
			SoftwareTile[] array2 = array;
			foreach (SoftwareTile item in array2)
			{
				SoftwareApps.Add(item);
			}
			RefreshSoftwareFilter();
		}
		catch (Exception ex)
		{
			log.Write("Logiciels", "Détection des applications installées : " + ex.Message, error: true);
		}
	}

	private async Task RunSoftwareOperation(string title, Func<Task<(bool Success, string Message)>> operation)
	{
		SoftwareOperationDetail = "";
		SoftwareOperationStatus = title + " — en cours…";
		try
		{
			(bool, string) obj = await operation();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			SoftwareOperationStatus = title + " — " + (string.IsNullOrWhiteSpace(item2) ? (item ? "Terminé." : "Résultat non confirmé. Vérifie le Journal.") : item2);
		}
		catch (Exception ex)
		{
			SoftwareOperationStatus = title + " — opération interrompue. Consulte les détails avant de réessayer.";
			SoftwareOperationDetail = ex.ToString();
		}
	}

	private AsyncRelayCommand BrowserInstallCommand(string displayName, string packageId, string browserKey)
	{
		return new AsyncRelayCommand(() => RunBrowserOperation(displayName, () => InstallBrowserExclusiveAsync(displayName, packageId, browserKey)));
	}

	private async Task UpdateRadeonTunerAsync()
	{
		SoftwarePackage? tuner = SoftwareApps.FirstOrDefault(item => item.Package.Id == "GitHub.dumbie.RadeonTuner")?.Package;
		if (tuner == null)
		{
			SoftwareOperationStatus = "Mise à jour Radeon Tuner — entrée introuvable dans le catalogue.";
			return;
		}
		await RunSoftwareOperation("Mise à jour Radeon Tuner", () => packages.ManageCustomManyAsync(new[] { tuner }, "Install"));
		await RefreshInstalledSoftwareAsync();
	}

	private void UpdateBrowserSelectionCommands()
	{
		RaisePropertyChanged("SelectedBrowserCount");
		RaisePropertyChanged("SelectedBrowserLabel");
		InstallSelectedBrowsersCommand?.RaiseCanExecuteChanged();
		UninstallSelectedBrowsersCommand?.RaiseCanExecuteChanged();
		ClearBrowserSelectionCommand?.RaiseCanExecuteChanged();
	}

	private void ClearBrowserSelection()
	{
		IsChromeSelected = false;
		IsFirefoxSelected = false;
		IsLibreWolfSelected = false;
		IsBraveSelected = false;
		IsUngoogledSelected = false;
		IsThoriumSelected = false;
		IsOperaSelected = false;
		IsHeliumSelected = false;
	}

	private async Task InstallSelectedBrowsersAsync()
	{
		if (IsChromeSelected)
		{
			await InstallChromeCommand.ExecuteAsync();
		}
		if (IsFirefoxSelected)
		{
			await InstallFirefoxCommand.ExecuteAsync();
		}
		if (IsLibreWolfSelected)
		{
			await InstallLibreWolfCommand.ExecuteAsync();
		}
		if (IsBraveSelected)
		{
			await InstallBraveCommand.ExecuteAsync();
		}
		if (IsUngoogledSelected)
		{
			await InstallScoopBrowser("Ungoogled Chromium", "ungoogled-chromium");
		}
		if (IsThoriumSelected)
		{
			await InstallScoopBrowser("Thorium AVX2", "thorium-avx2");
		}
		if (IsOperaSelected) await InstallOperaCommand.ExecuteAsync();
		if (IsHeliumSelected) await InstallHeliumCommand.ExecuteAsync();
	}

	private async Task UninstallSelectedBrowsersAsync()
	{
		if (IsChromeSelected)
		{
			await UninstallChromeCommand.ExecuteAsync();
		}
		if (IsFirefoxSelected)
		{
			await UninstallFirefoxCommand.ExecuteAsync();
		}
		if (IsLibreWolfSelected)
		{
			await UninstallLibreWolfCommand.ExecuteAsync();
		}
		if (IsBraveSelected)
		{
			await UninstallBraveCommand.ExecuteAsync();
		}
		if (IsUngoogledSelected)
		{
			await UninstallScoopBrowser("Ungoogled Chromium", "ungoogled-chromium");
		}
		if (IsThoriumSelected)
		{
			await UninstallScoopBrowser("Thorium AVX2", "thorium-avx2");
		}
		if (IsOperaSelected) await UninstallOperaCommand.ExecuteAsync();
		if (IsHeliumSelected) await UninstallHeliumCommand.ExecuteAsync();
	}

	private AsyncRelayCommand BrowserUninstallCommand(string displayName, string browserKey)
	{
		return new AsyncRelayCommand(async delegate
		{
			if (ConfirmBrowserRemoval(displayName))
			{
				await RunBrowserOperation("Suppression de " + displayName, async () =>
				{
					SetBrowserStage(20, $"Étape 1/2 — désinstallation de {displayName}");
					var result = await RemovePreviousBrowserAsync(browserKey, displayName);
					SetBrowserStage(result.Success ? 100 : 90, result.Success ? "Étape 2/2 — absence vérifiée" : "Étape 2/2 — suppression incomplète");
					return result;
				});
			}
		});
	}

	private async Task InstallScoopBrowser(string displayName, string packageId)
	{
		await RunBrowserOperation(displayName, () => InstallBrowserExclusiveAsync(displayName, packageId, packageId));
	}

	private async Task UninstallScoopBrowser(string displayName, string packageId)
	{
		if (!ConfirmBrowserRemoval(displayName))
		{
			return;
		}
		await RunBrowserOperation("Suppression de " + displayName, async () =>
		{
			SetBrowserStage(20, $"Étape 1/2 — désinstallation de {displayName}");
			var result = await RemovePreviousBrowserAsync(packageId, displayName);
			SetBrowserStage(result.Success ? 100 : 90, result.Success ? "Étape 2/2 — absence vérifiée" : "Étape 2/2 — suppression incomplète");
			return result;
		});
	}

	private static bool ConfirmBrowserRemoval(string displayName)
	{
		return Bastos.Native.LocalizedMessageBox.Show("Supprimer completement " + displayName + " de ce PC ?\n\nLe programme, les profils locaux, l'historique, les favoris, les mots de passe non synchronises, les caches, les raccourcis et les composants de mise a jour propres a ce navigateur seront effaces definitivement.", "Suppression complete du navigateur", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) == MessageBoxResult.Yes;
	}

	private async Task DebloatBrowser(string target)
	{
		await RunBrowserOperation("Debloat " + target, async delegate
		{
			string resultPath = Path.Combine(paths.LogRoot, $"Browser-Debloat-{target}-{Guid.NewGuid():N}.json");
			CommandResult result = await workers.RunAsync("Set-BASTOS-BrowserDebloat.ps1", new string[4] { "-Target", target, "-ResultPath", resultPath }, elevate: true, 10);
			string message = (result.Success ? ("Debloat " + target + " appliqué avec sauvegarde réversible.") : result.Error);
			try
			{
				if (File.Exists(resultPath))
				{
					using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
					message = jsonDocument.RootElement.GetProperty("Message").GetString() ?? message;
				}
			}
			catch
			{
			}
			return (Success: result.Success, Message: message);
		});
	}

	private async Task RunBrowserOperation(string title, Func<Task<(bool Success, string Message)>> operation)
	{
		if (browserOperationRunning)
		{
			BrowserOperationStatus = "Une opération navigateur est déjà en cours. Attends sa fin.";
			return;
		}
		browserOperationRunning = true;
		BrowserProgressVisible = true;
		SetBrowserStage(0, "Préparation de l’opération…");
		BrowserOperationDetail = "";
		BrowserOperationStatus = title + " — en cours…";
		try
		{
			(bool, string) obj = await operation();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			BrowserOperationStatus = title + " — " + (string.IsNullOrWhiteSpace(item2) ? (item ? "Terminé." : "Résultat non confirmé. Vérifie le Journal.") : item2);
			if (item && BrowserProgressValue < 100) SetBrowserStage(100, "Opération terminée et vérifiée.");
			if (!item) BrowserProgressStep = "Opération incomplète ; lis le détail ci-dessus pour la reprendre.";
		}
		catch (Exception ex)
		{
			BrowserOperationStatus = title + " — opération interrompue. Consulte les détails avant de réessayer.";
			BrowserOperationDetail = ex.ToString();
			BrowserProgressStep = "Opération interrompue ; lis le détail ci-dessus.";
		}
		finally
		{
			browserOperationRunning = false;
			RaisePropertyChanged("IsChromeInstalled");
			RaisePropertyChanged("IsFirefoxInstalled");
			RaisePropertyChanged("IsLibreWolfInstalled");
			RaisePropertyChanged("IsBraveInstalled");
			RaisePropertyChanged("IsUngoogledInstalled");
			RaisePropertyChanged("IsThoriumInstalled");
			RaisePropertyChanged("IsOperaInstalled");
			RaisePropertyChanged("IsHeliumInstalled");
		}
	}

	private PageViewModel BuildAutonomousPage()
	{
		string value = Reinstall.SelectedIso?.Display ?? "Aucune ISO sélectionnée";
		List<StatusCard> list = new List<StatusCard>();
		list.Add(new StatusCard("Profil utilisé", "Reprend les choix effectués dans Réinstallation facile Windows. Utilise de préférence l’ISO BASTOS créée à l’étape précédente; une ISO Microsoft reste acceptée et reçoit le même profil autonome.", $"{value}\n{Reinstall.SelectedLanguage.Display} — {Reinstall.SelectedKeyboard.Display} — compte {Reinstall.UserName}", ((object)Reinstall.SelectedIso != null) ? StatusTone.Success : StatusTone.Warning));
		StatusCard compatibility = null;
		compatibility = new StatusCard("1. Vérifier ce PC", "Contrôle en lecture seule le disque Windows, le mode GPT/UEFI et l’espace nécessaire à la partition persistante BASTOS_RECOVERY de 40 Go.", "Aucune modification", StatusTone.Neutral, "Vérifier la compatibilité", new AsyncRelayCommand(() => RunCard(compatibility, (Func<Task<(bool Success, string Message)>>)reinstallService.CheckAutonomousCompatibilityAsync)));
		list.Add(compatibility);
		StatusCard prepare = null;
		prepare = new StatusCard("2. Préparer l’installation autonome", "Copie l’ISO choisie et l’application courante dans BASTOS_RECOVERY sur le disque de C:, active le profil autonome et crée l’entrée de démarrage vérifiée.", "Préparation réversible tant que la réinstallation n’est pas lancée", StatusTone.Neutral, "Préparer BASTOS_RECOVERY", new AsyncRelayCommand(() => PrepareAutonomous(prepare)));
		list.Add(prepare);
		StatusCard start = null;
		start = new StatusCard("3. Réinstaller sans intervention", "Après l’unique confirmation, le PC redémarre dans WinPE, remplace Windows, crée le compte local, applique BASTOS, installe l’application native et démarre Bastos Game au premier Bureau.", "Attention — les partitions Windows remplacées ne sont pas récupérables", StatusTone.Danger, "Lancer et redémarrer", new AsyncRelayCommand(() => StartAutonomous(start)));
		list.Add(start);
		list.Add(new StatusCard("Résultat attendu", "Aucun composant KernelOS n’est installé. KOS Post-Install et KRNLGame.exe sont remplacés par le profil autonome BASTOS, l’application .NET native et le moniteur Bastos Game configuré au démarrage.", "Windows → profil BASTOS → BASTOS natif → Bastos Game prêt", StatusTone.Success));
		return new PageViewModel("Installation autonome BASTOS", "Réinstaller Windows depuis le disque, sans clé USB et sans question pendant l’installation", list, compatibilityAction: false);
	}

	private async Task PrepareAutonomous(StatusCard card)
	{
		if ((object)Reinstall.SelectedIso == null)
		{
			card.State = "Sélectionne d’abord l’ISO BASTOS créée dans Réinstallation facile Windows.";
			card.Tone = StatusTone.Warning;
		}
		else if (Bastos.Native.LocalizedMessageBox.Show("BASTOS va vérifier l’ISO choisie, puis créer ou mettre à jour BASTOS_RECOVERY sur le disque contenant C:. La création initiale peut réduire C: de 40 Go. Continuer ?", "Préparer l’installation autonome", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) == MessageBoxResult.Yes)
		{
			await RunCard(card, () => reinstallService.PrepareAutonomousAsync(Reinstall.SelectedIso, Reinstall.SelectedLanguage, Reinstall.SelectedKeyboard, Reinstall.UserName));
		}
	}

	private async Task StartAutonomous(StatusCard card)
	{
		if (Bastos.Native.LocalizedMessageBox.Show("DERNIÈRE CONFIRMATION\n\nEn continuant, BASTOS programmera le redémarrage et remplacera Windows sur son disque. Toutes les partitions de ce disque qui ne sont pas explicitement protégées comme EFI ou BASTOS_RECOVERY peuvent être supprimées.\n\nEnregistre et sauvegarde tous tes fichiers avant de répondre Oui. Après cela, l’installation se déroulera sans autre question.", "Lancer la réinstallation autonome", MessageBoxButton.YesNo, MessageBoxImage.Hand, MessageBoxResult.No) == MessageBoxResult.Yes)
		{
			await RunCard(card, (Func<Task<(bool Success, string Message)>>)reinstallService.StartAutonomousAsync);
		}
	}

	private PageViewModel BuildHardwarePage()
	{
		PageViewModel page = new PageViewModel("Mise à jour matériel", "Analyse du PC et installation des pilotes graphiques", Array.Empty<StatusCard>(), compatibilityAction: false, isHardware: true);
		StatusCard analysis = null;
		analysis = new StatusCard("Analyser ce PC", "Détecte la carte mère, le processeur, les cartes graphiques, le stockage, le réseau, l’audio et les versions de pilotes installées. Aucun numéro de série, adresse MAC ou adresse IP n’est collecté.", "Prêt — aucune installation automatique", StatusTone.Neutral, "Lancer l’analyse matérielle", new AsyncRelayCommand(() => AnalyzeHardware(page, analysis)));
		page.GraphicsStandardCard = BuildGraphicsInstallerCard();
		page.GraphicsLiteCard = BuildGraphicsDebloatInstallerCard();
		page.HardwareAnalysisCard = analysis;
		page.Cards.Add(page.GraphicsStandardCard);
		page.Cards.Add(page.GraphicsLiteCard);
		page.Cards.Add(analysis);
		return page;
	}

	private async Task AnalyzeHardware(PageViewModel page, StatusCard analysisCard)
	{
		analysisCard.State = "Initialisation de l’analyse…";
		analysisCard.Tone = StatusTone.Neutral;
		Progress<WorkerProgress> progressReporter = new Progress<WorkerProgress>(delegate(WorkerProgress item)
		{
			analysisCard.State = $"{item.Percent} % — {item.Phase}\n{item.Message}";
		});
		HardwareAnalysisResult result = await operations.AnalyzeHardwareAsync(progressReporter);
		NetworkDiscovery.ApplyAnalysis(result);
		if (!result.Success)
		{
			analysisCard.State = result.Message;
			analysisCard.Tone = StatusTone.Danger;
			return;
		}
		ShowHardwareResults(page, result);
	}

	private StatusCard BuildGraphicsInstallerCard()
	{
		StatusCard card = null;
		card = new StatusCard("Installation normale", "Pilote graphique officiel NVIDIA, AMD ou Intel, avec l’installation standard du fabricant.", "Connexion Internet et droits administrateur requis", StatusTone.Neutral, "Choisir le fabricant", new AsyncRelayCommand(() => RunCard(card, () => operations.LaunchGraphicsInstallerAsync())));
		return card;
	}
	private StatusCard BuildGraphicsDebloatInstallerCard()
	{
		StatusCard card = null!;
		card = new StatusCard("Version allégée",
			"Pilote officiel NVIDIA, AMD ou Intel ; Bastos prépare une copie allégée avant l’installation.",
			"Pilote officiel, 7-Zip et autorisation administrateur requis", StatusTone.Neutral,
			"Lancer la version allégée", new AsyncRelayCommand(() => RunCard(card, () => operations.LaunchGraphicsInstallerAsync(true))));
		return card;
	}
	private async Task OpenDriver(StatusCard card, DriverRecommendation recommendation)
	{
		if (!recommendation.Sensitive || Bastos.Native.LocalizedMessageBox.Show("Une mise à jour BIOS/UEFI incorrecte ou interrompue peut empêcher le démarrage. BASTOS va uniquement ouvrir la page officielle. Continuer ?", "Pilote sensible", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) == MessageBoxResult.Yes)
		{
			await RunCard(card, () => operations.OpenOfficialDriverAsync(recommendation));
		}
	}

	private PageViewModel BuildOptimizationsPage()
	{
		List<StatusCard> list = new List<StatusCard>();
		StatusCard statusCard = systemState.ReadDashboard().First((StatusCard card) => card.Title == "HAGS");
		bool? flag = systemState.ReadHagsSelection();
		StatusCard hags = null;
		hags = new StatusCard("HAGS", "Planification GPU accélérée par le matériel. Un redémarrage est requis.", statusCard.State, statusCard.Tone, "Activer", new AsyncRelayCommand(() => RunNativeCard(hags, "hags-on", true)), "Désactiver", new AsyncRelayCommand(() => RunNativeCard(hags, "hags-off", false)), isChoiceCard: true, flag == true, flag == false);
		list.Add(hags);
		bool gameModeEnabled = tuning.GameModeEnabled;
		StatusCard gameMode = null;
		gameMode = new StatusCard("Mode Jeu Windows", "Donne la priorité aux ressources du jeu et limite les tâches Windows en arrière-plan.", gameModeEnabled ? "Activé" : "Désactivé", gameModeEnabled ? StatusTone.Success : StatusTone.Warning, "Activer", new AsyncRelayCommand(() => RunChoiceCard(gameMode, primary: true, () => (Success: true, Message: tuning.SetGameMode(enabled: true)))), "Désactiver", new AsyncRelayCommand(() => RunChoiceCard(gameMode, primary: false, () => (Success: true, Message: tuning.SetGameMode(enabled: false)))), isChoiceCard: true, gameModeEnabled, !gameModeEnabled);
		list.Add(gameMode);
		bool foregroundPriorityEnabled = tuning.ForegroundPriorityEnabled;
		int? foregroundPriorityValue = tuning.ForegroundPriorityValue;
		StatusCard foregroundPriority = null;
		foregroundPriority = new StatusCard("Prioriser les applications actives", "Alloue davantage de temps processeur à l’application au premier plan. Utilise le réglage Windows 0x26 : quantum court, variable et priorité de premier plan élevée. Ce réglage est commun avec le Quantum avancé.", foregroundPriorityEnabled ? "Appliqué — valeur 0x26" : (foregroundPriorityValue.HasValue ? $"Non appliqué — valeur actuelle 0x{foregroundPriorityValue.Value:X2}" : "Non appliqué — valeur absente"), foregroundPriorityEnabled ? StatusTone.Success : StatusTone.Neutral, "Activer", new AsyncRelayCommand(() => RunForegroundPriorityCard(foregroundPriority, "foreground-priority-on")), "Restaurer", new AsyncRelayCommand(() => RunForegroundPriorityCard(foregroundPriority, "foreground-priority-restore")), isChoiceCard: true, foregroundPriorityEnabled, !foregroundPriorityEnabled);
		list.Add(foregroundPriority);
		AddPerformanceCard(list, "background-apps", "Limiter les applications en arrière-plan", "Désactive globalement l’exécution en arrière-plan des applications compatibles afin de réduire leur consommation de mémoire et de processeur.");
		AddPerformanceCard(list, "service-hosts", "Regrouper les hôtes de services", "Ajuste SvcHostSplitThresholdInKB à la quantité de RAM physique pour limiter la multiplication des processus de services.");
		AddPerformanceCard(list, "mmcss-gaming", "Optimiser MMCSS pour le jeu", "Applique le profil multimédia du script : MMCSS actif, réactivité à 10, limitation réseau levée et tâche Games en priorité élevée.");
		CpuOptimizationCards.Clear();
		AddInterruptAffinityCard(CpuOptimizationCards, "X3D", "Affinité des interruptions — X3D", "Ryzen X3D à 8 cœurs : GPU 2, USB 3, réseau 4, audio 5.");
		AddInterruptAffinityCard(CpuOptimizationCards, "SixCore", "Affinité des interruptions — 6 cœurs", "GPU 2, USB 3, réseau et audio 4.");
		AddInterruptAffinityCard(CpuOptimizationCards, "DualCcd", "Affinité des interruptions — double CCD", "GPU 8, USB 9, réseau 10, audio 11.");
		AddInterruptAffinityCard(CpuOptimizationCards, "Intel", "Affinité des interruptions — Intel", "GPU 2, USB 3, réseau 4, audio 5. Refus si la topologie est hybride ou ambiguë.");
		AddPerformanceCard(list, "webdav-limit", "Lever la limite de taille WebDAV", "Porte FileSizeLimitInBytes à 4 Gio pour les transferts WebDAV via le service WebClient.");
		bool fullscreenEnabled = tuning.FullscreenOptimizationsEnabled;
		StatusCard fullscreen = null;
		fullscreen = new StatusCard("Optimisations plein écran", "Autorise Windows à utiliser ses optimisations plein écran pour les jeux compatibles. Le bouton Désactiver applique les quatre valeurs du script Gaming.cs.", fullscreenEnabled ? "Activées" : "Désactivées", fullscreenEnabled ? StatusTone.Success : StatusTone.Warning, "Activer", new AsyncRelayCommand(() => RunChoiceCard(fullscreen, primary: true, () => (Success: true, Message: tuning.SetFullscreenOptimizations(enabled: true)))), "Désactiver", new AsyncRelayCommand(() => RunChoiceCard(fullscreen, primary: false, () => (Success: true, Message: tuning.SetFullscreenOptimizations(enabled: false)))), isChoiceCard: true, fullscreenEnabled, !fullscreenEnabled);
		list.Add(fullscreen);
		StatusCard cleanup = null;
		cleanup = new StatusCard("Nettoyage temporaire", "Analyse ou supprime uniquement les cibles temporaires contrôlées par BASTOS.", "Non analysé", StatusTone.Neutral, "Analyser", new AsyncRelayCommand(() => RunCard(cleanup, () => operations.RunCleanupAsync(analyzeOnly: true))), "Nettoyer", new AsyncRelayCommand(() => RunCard(cleanup, () => operations.RunCleanupAsync(analyzeOnly: false))));
		list.Add(cleanup);
        advancedPerformanceCards.Clear();
        foreach (var card in list.Where(c => c.Title is "Regrouper les hôtes de services" or "Optimiser MMCSS pour le jeu" or "Lever la limite de taille WebDAV" or "Nettoyage temporaire").ToArray())
        { advancedPerformanceCards.Add(card); list.Remove(card); }
		return new PageViewModel("Optimisations", "Performances des jeux, ressources système et réglages matériels", list, compatibilityAction: false, isReinstall: false, isBrowsers: false, isSoftware: false, isTroubleshooting: false, isTweaking: false, isDashboard: false, isOptimizations: true);
	}

	private IEnumerable<TroubleshootingToggle> BuildRiskyOptimizationToggles()
	{
		(string, string, string, string, string)[] array = new(string, string, string, string, string)[2]
		{
			("RiskUnsafeDownloads", "Autoriser les téléchargements non sûrs sans avertissement", "Abaisse la sécurité de la zone Internet afin d’ouvrir plus facilement des fichiers potentiellement dangereux.", "conserver l’avertissement évite d’exécuter par erreur un fichier venant d’un site ou d’un message malveillant.", ""),
			("RiskDisableBackgroundMaintenance", "Désactiver la maintenance et des services Windows", "Cette option peut désactiver la recherche indexée, l’impression, le Bluetooth, les notifications Windows et certaines fonctions de WSL2/Hyper-V. La désactiver dans Bastos restaurera les valeurs sauvegardées.", "les services et tâches Windows maintiennent la compatibilité, les périphériques et la santé du système.", "SERVICES WINDOWS\n• SysMain — préchargement et optimisation des applications\n• WSearch — indexation et recherche Windows\n• Spooler — impression et gestion des imprimantes\n• bthserv — prise en charge principale du Bluetooth\n• BTAGService — passerelle audio Bluetooth\n• WerSvc — rapports d’erreurs Windows\n• WdiServiceHost — diagnostics Windows\n• DiagTrack — télémétrie et expériences utilisateur connectées\n• WpnService — notifications Push Windows\n• vmcompute — Hyper-V, WSL2 et conteneurs, lorsqu’il existe\n\nTÂCHES PLANIFIÉES\n• Analyse de l’efficacité énergétique\n• Envoi des rapports d’erreurs Windows\n• Microsoft Compatibility Appraiser\n• Analyse des applications lancées au démarrage\n• Collecte des diagnostics de disque\n• Défragmentation et optimisation planifiées\n• Assistant Stockage automatique\n• Consolidation de la télémétrie\n• Télémétrie du noyau\n• Télémétrie USB")
		};
		(string Key, string Title, string Description, string Why, string Help)[] array2 = array;
		for (int i = 0; i < array2.Length; i++)
		{
			(string, string, string, string, string) tuple = array2[i];
			yield return new TroubleshootingToggle(tuple.Item1, tuple.Item2, tuple.Item3, initialState: false, ToggleRiskyOptimizationAsync, false, tuple.Item4, tuple.Item5);
		}
	}

	private IEnumerable<TroubleshootingToggle> BuildTroubleshootingToggles()
	{
		(string, string, string)[] array = new(string, string, string)[2]
		{
			("Lua", "Contrôle de compte utilisateur (LUA/UAC)", "Conserve les demandes de droits administrateur et la séparation des privilèges. Redémarrage requis."),
			("WindowsUpdateDrivers", "Pilotes via Windows Update", "Autorise Windows Update à proposer et installer les pilotes matériels.")
		};
		(string Key, string Title, string Description)[] array2 = array;
		for (int i = 0; i < array2.Length; i++)
		{
			(string, string, string) tuple = array2[i];
			yield return new TroubleshootingToggle(tuple.Item1, tuple.Item2, tuple.Item3, initialState: false, ToggleTroubleshootingAsync);
		}
	}

	private void DeselectBrowsersExcept(string selected)
	{
		if (selected != "chrome") SetProperty(ref chromeSelected, false, nameof(IsChromeSelected));
		if (selected != "firefox") SetProperty(ref firefoxSelected, false, nameof(IsFirefoxSelected));
		if (selected != "librewolf") SetProperty(ref libreWolfSelected, false, nameof(IsLibreWolfSelected));
		if (selected != "brave") SetProperty(ref braveSelected, false, nameof(IsBraveSelected));
		if (selected != "ungoogled-chromium") SetProperty(ref ungoogledSelected, false, nameof(IsUngoogledSelected));
		if (selected != "thorium-avx2") SetProperty(ref thoriumSelected, false, nameof(IsThoriumSelected));
		if (selected != "opera") SetProperty(ref operaSelected, false, nameof(IsOperaSelected));
		if (selected != "helium") SetProperty(ref heliumSelected, false, nameof(IsHeliumSelected));
	}

	private static readonly (string Key, string Name)[] BrowserReplacementCandidates =
	{
		("chrome", "Google Chrome"), ("firefox", "Mozilla Firefox"), ("librewolf", "LibreWolf"),
		("brave", "Brave Browser"), ("ungoogled-chromium", "Ungoogled Chromium"),
		("thorium-avx2", "Thorium AVX2"), ("opera", "Opera"), ("helium", "Helium"), ("edge", "Microsoft Edge")
	};

	private void SetBrowserStage(int percent, string step)
	{
		BrowserProgressValue = Math.Clamp(percent, 0, 100);
		BrowserProgressStep = step;
	}

	private static bool BrowserExecutablePresent(string key) => key switch
	{
		"ungoogled-chromium" or "thorium-avx2" => Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop", "apps", key)),
		_ => BrowserInstalled(key)
	};

	private async Task<bool> BrowserHasRemnantsAsync(string key)
	{
		if (key == "edge")
			return File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe")) ||
				File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe")) ||
				Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Edge"));
		if (key is "ungoogled-chromium" or "thorium-avx2")
		{
			string profile = key == "ungoogled-chromium" ? "Chromium" : "Thorium";
			return Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop", "apps", key)) ||
				Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop", "persist", key)) ||
				Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), profile)) ||
				Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), profile));
		}
		string resultPath = Path.Combine(paths.LogRoot, $"Browser-Detect-{key}.json");
		CommandResult probe = await workers.RunAsync("Uninstall-BASTOS-Browser.ps1", new[] { "-Browser", key, "-DetectOnly", "-ResultPath", resultPath }, elevate: false, 5);
		if (!probe.Success || !File.Exists(resultPath)) throw new InvalidOperationException($"Contrôle de {key} impossible : {probe.Error}");
		using JsonDocument result = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
		if (!result.RootElement.GetProperty("Success").GetBoolean()) throw new InvalidOperationException($"Contrôle de {key} en échec.");
		string detail = result.RootElement.GetProperty("Message").GetString() ?? string.Empty;
		return !detail.Contains("absent et sans residu", StringComparison.OrdinalIgnoreCase);
	}

	private async Task<(bool Success, string Message)> RemovePreviousBrowserAsync(string key, string name)
	{
		string resultPath = Path.Combine(paths.LogRoot, $"Browser-Replacement-{key}-{Guid.NewGuid():N}.json");
		CommandResult operation = key switch
		{
			"edge" => await workers.RunAsync("Remove-BASTOS-Edge.ps1", new[] { "-ForceWithoutBrowser", "-ResultPath", resultPath }, elevate: true, 20),
			"ungoogled-chromium" or "thorium-avx2" => await workers.RunAsync("Install-BASTOS-ScoopBrowser.ps1", new[] { "-Browser", key, "-Action", "Uninstall", "-ResultPath", resultPath }, elevate: false, 20),
			_ => await workers.RunAsync("Uninstall-BASTOS-Browser.ps1", new[] { "-Browser", key, "-ResultPath", resultPath }, elevate: true, 20)
		};
		if (!File.Exists(resultPath)) return (false, name + " : aucun rapport de suppression. " + operation.Error);
		using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
		bool reportedSuccess = report.RootElement.TryGetProperty("Success", out JsonElement success) && success.GetBoolean();
		bool reportedErrors = report.RootElement.TryGetProperty("Errors", out JsonElement reportedErrorList) &&
			reportedErrorList.ValueKind == JsonValueKind.Array && reportedErrorList.GetArrayLength() > 0;
		string detail = report.RootElement.TryGetProperty("Message", out JsonElement message) ? message.GetString() ?? string.Empty :
			(report.RootElement.TryGetProperty("Errors", out JsonElement errors) && errors.ValueKind == JsonValueKind.Array
				? string.Join(" ; ", errors.EnumerateArray().Select(error => error.GetString())) : operation.Error);
		if (!operation.Success || !reportedSuccess || reportedErrors) return (false, name + " : " + detail);
		if (await BrowserHasRemnantsAsync(key)) return (false, name + " : des fichiers, profils ou enregistrements restent détectés.");
		return (true, name + " supprimé et vérifié.");
	}

	private async Task<(bool Success, string Message)> InstallBrowserExclusiveAsync(string displayName, string packageId, string browserKey)
	{
		SetBrowserStage(5, "Étape 1/4 — recherche des navigateurs à remplacer");
		var previous = new List<(string Key, string Name)>();
		foreach (var browser in BrowserReplacementCandidates)
			if (browser.Key != browserKey && await BrowserHasRemnantsAsync(browser.Key)) previous.Add(browser);
		if (previous.Count > 0)
		{
			string names = string.Join(", ", previous.Select(item => item.Name));
			if (Bastos.Native.LocalizedMessageBox.Show($"Installer {displayName} puis supprimer complètement : {names} ?\n\nLes profils locaux, favoris et mots de passe non synchronisés de ces navigateurs seront effacés. WebView2 sera conservé.",
				"Remplacement complet des navigateurs", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) != MessageBoxResult.Yes)
				return (false, "Remplacement annulé.");
		}
		SetBrowserStage(20, $"Étape 2/4 — installation de {displayName} en cours");
		(bool Success, string Message) install;
		if (browserKey is "ungoogled-chromium" or "thorium-avx2")
		{
			string resultPath = Path.Combine(paths.LogRoot, $"Browser-Install-{browserKey}-{Guid.NewGuid():N}.json");
			CommandResult result = await workers.RunAsync("Install-BASTOS-ScoopBrowser.ps1", new[] { "-Browser", browserKey, "-ResultPath", resultPath }, elevate: false, 20);
			install = (result.Success, result.Success ? $"{displayName} installé." : result.Error);
			if (File.Exists(resultPath))
			{
				using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
				install = (result.Success && report.RootElement.GetProperty("Success").GetBoolean(), report.RootElement.GetProperty("Message").GetString() ?? install.Message);
			}
		}
		else install = BrowserExecutablePresent(browserKey)
			? (true, $"{displayName} est déjà installé ; reprise du nettoyage.")
			: await packages.InstallAsync(new SoftwarePackage("Navigateurs Web", displayName, packageId));
		if (!install.Success) return (false, install.Message);
		if (!BrowserExecutablePresent(browserKey)) return (false, $"{displayName} a été annoncé installé, mais son exécutable n’a pas été vérifié. Les anciens navigateurs sont conservés.");
		SetBrowserStage(45, $"Étape 3/4 — {displayName} vérifié ; suppression des anciens navigateurs");
		var failures = new List<string>();
		bool verificationIncomplete = false;
		var machineBrowsers = previous.Where(browser => browser.Key is not ("ungoogled-chromium" or "thorium-avx2")).ToArray();
		if (machineBrowsers.Length > 0)
		{
			SetBrowserStage(50, "Étape 3/4 — autorisation administrateur pour le nettoyage des navigateurs");
			string resultPath = Path.Combine(paths.LogRoot, $"Browser-Replacement-Batch-{Guid.NewGuid():N}.json");
			CommandResult cleanup = await workers.RunAsync("Complete-BASTOS-BrowserReplacement.ps1",
				new[] { "-SelectedBrowser", browserKey, "-Browsers", string.Join(",", machineBrowsers.Select(browser => browser.Key)), "-ResultPath", resultPath }, elevate: true, 60);
			if (cleanup.ExitCode == 1223)
				return (false, $"{displayName} est installé. La demande administrateur a été annulée : les anciens navigateurs sont conservés. Relance Installer pour reprendre le nettoyage et accepte la demande Windows.");
			if (!File.Exists(resultPath)) return (false, "Le nettoyage n’a pas fourni de rapport. " + cleanup.Error);
			using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
			verificationIncomplete = report.RootElement.TryGetProperty("VerificationIncomplete", out JsonElement incomplete) && incomplete.GetBoolean();
			if (!cleanup.Success || !report.RootElement.GetProperty("Success").GetBoolean())
				failures.Add(report.RootElement.GetProperty("Message").GetString() ?? "Nettoyage incomplet.");
		}
		foreach (var browser in previous.Where(browser => browser.Key is "ungoogled-chromium" or "thorium-avx2"))
		{
			try { var result = await RemovePreviousBrowserAsync(browser.Key, browser.Name); if (!result.Success) failures.Add(result.Message); }
			catch (Exception error) { failures.Add(browser.Name + ": " + error.Message); }
		}
		SetBrowserStage(90, "Étape 4/4 — contrôle final des navigateurs et de WebView2");
		foreach (var browser in BrowserReplacementCandidates)
		{
			if (browser.Key == browserKey) continue;
			try { if (await BrowserHasRemnantsAsync(browser.Key)) failures.Add(browser.Name + " reste détecté."); }
			catch (Exception error) { failures.Add(browser.Name + " : vérification impossible — " + error.Message); }
		}
		if (!BrowserExecutablePresent(browserKey)) failures.Add(displayName + " n’est plus présent après le nettoyage.");
		bool webViewPresent = new[] {
			Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "EdgeWebView", "Application"),
			Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "EdgeWebView", "Application")
		}.Any(root => Directory.Exists(root) && Directory.EnumerateFiles(root, "msedgewebview2.exe", SearchOption.AllDirectories).Any());
		if (!webViewPresent) failures.Add("WebView2 est absent.");
		if (failures.Count > 0) return (false, $"{displayName} est installé, mais le remplacement n’est pas complet : {string.Join(" | ", failures.Distinct())}");
		if (verificationIncomplete)
		{
			SetBrowserStage(100, "Navigateur installé ; vérification Windows partielle.");
			return (true, $"{displayName} est installé ; les anciens navigateurs détectés sont absents et WebView2 est préservé. Avertissement : Windows n’a pas permis de vérifier les paquets destinés aux futurs comptes.");
		}
		SetBrowserStage(100, "Étape 4/4 — installation et nettoyage vérifiés");
		return (true, $"{displayName} est installé ; les autres navigateurs gérés et leurs résidus détectés ont été supprimés. Vérifie le navigateur par défaut dans Windows.");
	}

	private void AddPerformanceCard(List<StatusCard> cards, string id, string title, string description)
	{
		var actual=NativeWorkerService.ReadPerformanceState(id);
        bool enabled=actual.Applied;
		StatusCard card = null;
		card = new StatusCard(title, description, actual.Message, enabled ? StatusTone.Success : StatusTone.Neutral, "Activer", new AsyncRelayCommand(() => RunPerformanceCard(card, id, true)), "Restaurer", new AsyncRelayCommand(() => RunPerformanceCard(card, id, false)), isChoiceCard: true, enabled, !enabled);
		cards.Add(card);
        performanceCards[id]=card;
	}
    private readonly Dictionary<string,StatusCard> performanceCards=new();
    public void RefreshVisibleConfigurationStates()
    {
        foreach(var entry in performanceCards){
            try{var state=NativeWorkerService.ReadPerformanceState(entry.Key);entry.Value.State=state.Message;entry.Value.SelectChoice(state.Applied);entry.Value.Tone=state.Applied?StatusTone.Success:StatusTone.Neutral;}
            catch(Exception ex){entry.Value.State="État indisponible — "+ex.Message;entry.Value.Tone=StatusTone.Warning;}
        }
    }

	private void BuildKeyboardOptimizationCards()
	{
		var cards = new List<StatusCard>();
		AddPerformanceCard(cards, "keyboard", "Accélérer la répétition des touches", "Règle le délai de répétition à 0 et la vitesse à 31. Modifie la répétition des touches maintenues ; ne change pas la latence matérielle du clavier.");
		AddPerformanceCard(cards, "accessibility-hotkeys", "Désactiver les raccourcis clavier d’accessibilité", "Neutralise les déclenchements par raccourci des Touches rémanentes, Touches filtres et Touches bascules.");
		foreach (var card in cards) KeyboardOptimizationCards.Add(card);
	}

	private void BuildGpuOptimizationCards()
	{
		AddGpuCard("amd-ulps", "AMD — Désactiver ULPS", "Empêche la mise en veille profonde ULPS des cartes Radeon.");
		AddGpuCard("amd-power-gating", "AMD — Désactiver le power gating", "Désactive la coupure dynamique de blocs et des P-States pour privilégier la disponibilité des performances.");
		AddGpuCard("amd-video-gating", "AMD — Désactiver le gating vidéo", "Maintient les blocs vidéo VCE/UVD disponibles en désactivant leur power/clock gating.");
		AddGpuCard("amd-aspm", "AMD — Désactiver ASPM", "Désactive les états PCIe ASPM L0s et L1 pour réduire la latence de réveil.");
		AddGpuCard("nvidia-dynamic-pstate", "NVIDIA — Désactiver les P-States dynamiques", "Désactive la variation dynamique des P-States du pilote NVIDIA.");
		AddGpuCard("nvidia-async-pstate", "NVIDIA — Désactiver les P-States asynchrones", "Désactive les transitions asynchrones de P-State NVIDIA.");
		AddGpuCard("intel-async-flips", "Intel — Désactiver les flips asynchrones", "Désactive les flips d’affichage asynchrones du pilote graphique Intel.");
		AddGpuCard("intel-adaptive-vsync", "Intel — Désactiver la V-Sync adaptative", "Désactive la synchronisation verticale adaptative du pilote Intel.");
		AddGpuImportCard("amd", "AMD — Importer les réglages graphiques", "Profil AMD complet : graphismes, affichage, notifications et réglages Windows associés. Aperçu détaillé et sauvegarde avant application.");
		AddGpuImportCard("nvidia", "NVIDIA — Importer les réglages graphiques", "Profil NVIDIA : P-States dynamiques, HDCP, compteurs de performance et icône NVIDIA. Sauvegarde des valeurs avant application.");
		AddGpuImportCard("intel", "Intel — Importer les réglages graphiques", "Profil Intel : synchronisation des images et faible latence du pilote Intel. Sauvegarde des valeurs avant application.");
	}

	private void AddGpuImportCard(string vendor, string title, string description)
	{
		if (!detectedGpuVendors.Contains(vendor)) return;
		StatusCard card = null!;
		card = new StatusCard(title, description, "Prêt pour l’aperçu", StatusTone.Neutral,
			"Aperçu / importer", new AsyncRelayCommand(() => RunGpuImportCard(card, vendor, true)),
			"Restaurer", new AsyncRelayCommand(() => RunGpuImportCard(card, vendor, false)),
			isChoiceCard: true, false, false);
		GpuOptimizationCards.Add(card);
	}

	private async Task RunGpuImportCard(StatusCard card, string vendor, bool apply)
	{
		string vendorName = vendor.ToUpperInvariant();
		string sid = System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value;
		string resultPath = Path.Combine(paths.LogRoot, $"GraphicsImport-{vendor}-{Guid.NewGuid():N}.json");
		string action = apply ? "PreviewImport" : "RestoreImport";
		if (apply)
		{
			card.State = "Lecture des réglages…";
			CommandResult preview = await workers.RunAsync("Invoke-BASTOS-GraphicsOptimization.ps1",
				new[] { "-Action", action, "-Vendor", vendorName, "-ExpectedUserSid", sid, "-ResultPath", resultPath }, timeoutMinutes: 2);
			if (!preview.Success || !File.Exists(resultPath)) { card.State = Summarize(preview.Error); card.Tone = StatusTone.Danger; return; }
			string detail;
			try
			{
				using JsonDocument json = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
				if (!json.RootElement.GetProperty("Success").GetBoolean()) throw new InvalidOperationException(json.RootElement.GetProperty("Message").GetString());
				detail = string.Join(Environment.NewLine, json.RootElement.GetProperty("Settings").EnumerateArray().Select(e => e.GetString()));
			}
			catch (Exception ex) { card.State = Summarize(ex.Message); card.Tone = StatusTone.Danger; return; }
			if (Bastos.Native.LocalizedMessageBox.Show("Réglages qui seront importés :" + Environment.NewLine + Environment.NewLine + detail + Environment.NewLine + Environment.NewLine +
				"Les valeurs actuelles seront sauvegardées pour une restauration. Continuer ?", card.Title, MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
			{ card.State = "Importation annulée"; card.Tone = StatusTone.Neutral; return; }
			action = "ApplyImport";
		}
		else if (Bastos.Native.LocalizedMessageBox.Show($"Restaurer les réglages {vendorName} enregistrés avant l’importation ?", card.Title,
			MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
		card.State = "Autorisation administrateur…"; card.Tone = StatusTone.Neutral;
		resultPath = Path.Combine(paths.LogRoot, $"GraphicsImport-{vendor}-{Guid.NewGuid():N}.json");
		CommandResult result = await workers.RunAsync("Invoke-BASTOS-GraphicsOptimization.ps1",
			new[] { "-Action", action, "-Vendor", vendorName, "-ExpectedUserSid", sid, "-ResultPath", resultPath }, elevate: true, timeoutMinutes: 3);
		string message = result.Success ? (apply ? "Réglages importés — redémarrage conseillé" : "Valeurs précédentes restaurées") : result.Error;
		try { if (File.Exists(resultPath)) { using JsonDocument json = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
			message = json.RootElement.GetProperty("Message").GetString() ?? message;
			if (!json.RootElement.GetProperty("Success").GetBoolean()) result = result with { Success = false }; } } catch { }
		card.State = Summarize(message); card.Tone = result.Success ? (apply ? StatusTone.Success : StatusTone.Neutral) : StatusTone.Danger;
		if (apply && result.Success)
		{
			card.State = "Réglages écrits — contrôle après démarrage du pilote…";
			card.Tone = StatusTone.Neutral;
			await Task.Delay(TimeSpan.FromSeconds(18));
			string checkPath = Path.Combine(paths.LogRoot, $"GraphicsImport-verify-{vendor}-{Guid.NewGuid():N}.json");
			CommandResult check = await workers.RunAsync("Invoke-BASTOS-GraphicsOptimization.ps1",
				new[] { "-Action", "VerifyImport", "-Vendor", vendorName, "-ExpectedUserSid", sid, "-ResultPath", checkPath }, timeoutMinutes: 2);
			string checkMessage = check.Success ? "Réglages graphiques vérifiés" : check.Error;
			try
			{
				if (File.Exists(checkPath))
				{
					using JsonDocument json = JsonDocument.Parse(await File.ReadAllTextAsync(checkPath));
					checkMessage = json.RootElement.GetProperty("Message").GetString() ?? checkMessage;
					if (!json.RootElement.GetProperty("Success").GetBoolean()) check = check with { Success = false };
				}
			}
			catch (Exception ex) { checkMessage = ex.Message; check = check with { Success = false }; }
			card.State = Summarize(checkMessage);
			card.Tone = check.Success ? StatusTone.Success : StatusTone.Danger;
		}
	}

	private void AddGpuCard(string id, string title, string description)
	{
		if (!GpuOptimizationService.IsVisibleForVendors(id, detectedGpuVendors)) return;
		var service = new GpuOptimizationService();
		bool applicable = service.IsApplicable(id);
		bool enabled = applicable && service.IsEnabled(id);
		StatusCard card = null;
		card = new StatusCard(title, description, applicable ? (enabled ? "Appliqué" : "Non appliqué") : "Pilote compatible non détecté — installer le pilote dans Mise à jour matériel", enabled ? StatusTone.Success : StatusTone.Neutral, "Activer", new AsyncRelayCommand(() => RunGpuOptimizationCard(card, id, true)), "Restaurer", new AsyncRelayCommand(() => RunGpuOptimizationCard(card, id, false)), isChoiceCard: true, enabled, !enabled);
		GpuOptimizationCards.Add(card);
	}

	private void BuildSecurityPrivacyCards()
	{
		securityCardsById.Clear();
		AddSecurityCard("telemetry", "Réduire la télémétrie", "Réduit la collecte diagnostique, les retours et l’inventaire de compatibilité. Modéré.");
		AddSecurityCard("error-reporting", "Désactiver les rapports d’erreurs", "Désactive Windows Error Reporting et les rapports manuscrits. Modéré.");
		AddSecurityCard("advertising", "Désactiver publicité et suggestions", "Désactive l’identifiant publicitaire, les expériences personnalisées et les suggestions tierces.");
		AddSecurityCard("news", Environment.OSVersion.Version.Build>=22000?"Désactiver les Widgets Windows":"Désactiver actualités et centres d’intérêt", "Utilise la stratégie disponible sur cette version de Windows : Widgets sous Windows 11, Actualités et centres d’intérêt sous Windows 10.");
		AddSecurityCard("meet-now", "Masquer Réunion maintenant", "Réglage réservé à Windows 10 ; sans effet sur Windows 11.");
		AddSecurityCard("activity-history", "Désactiver l’historique d’activité", "Bloque la publication, le flux et la synchronisation des activités.");
		AddSecurityCard("location", "Désactiver localisation et capteurs", "Bloque la localisation, les capteurs, les cartes hors ligne et Wi-Fi Sense. Modéré.");
		AddSecurityCard("autologger", "Désactiver les AutoLoggers", "Désactive dix sessions de journalisation WMI diagnostique. Modéré.");
		AddSecurityCard("cortana", "Désactiver Cortana et la recherche web", "Réglage principalement destiné à Windows 10.");
		AddSecurityCard("copilot", "Désactiver Windows Copilot", "Désactive Copilot par stratégie et masque son bouton sous Windows 11.");
		AddSecurityCard("content-delivery", "Désactiver Content Delivery Manager", "Désactive les contenus sponsorisés et suggestions diffusés par Windows.");
		AddSecurityCard("find-device", "Désactiver Localiser mon appareil", "Désactive la stratégie de localisation de l’appareil.");
		AddSecurityCard("delivery-optimization", "Désactiver le partage des mises à jour", "Désactive le partage pair-à-pair de l’Optimisation de la distribution.");
	}

	private void AddSecurityCard(string id, string title, string description)
	{
		StatusCard card = null;
		card = new StatusCard(title, description, "Lecture de l’état Windows…", StatusTone.Neutral, "Activer", new AsyncRelayCommand(() => RunSecurityCard(card, id, true)), "Restaurer", new AsyncRelayCommand(() => RunSecurityCard(card, id, false)), isChoiceCard: true, false, false);
		securityCardsById[id] = card;
		SecurityPrivacyCards.Add(card);
	}

	private async Task RefreshSecurityPrivacyStatesAsync()
	{
		string resultPath = Path.Combine(paths.LogRoot, $"SecurityPrivacy-State-{Guid.NewGuid():N}.json");
		CommandResult result = await workers.RunAsync("Manage-BASTOS-SecurityPrivacy.ps1", new[] { "-Id", "all", "-Action", "Get", "-ResultPath", resultPath }, elevate: false, 2);
		if (!result.Success || !File.Exists(resultPath))
		{
			foreach (StatusCard card in securityCardsById.Values) { card.State = "Lecture de l’état impossible"; card.Tone = StatusTone.Warning; }
			return;
		}
		try
		{
			using JsonDocument json = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
			JsonElement states = json.RootElement.GetProperty("States");
			JsonElement readableStates = json.RootElement.GetProperty("Readable");
			foreach ((string id, StatusCard card) in securityCardsById)
			{
				bool applied = states.TryGetProperty(id, out JsonElement state) && state.GetBoolean();
				bool readable = readableStates.TryGetProperty(id, out JsonElement readableState) && readableState.GetBoolean();
                if(json.RootElement.TryGetProperty("Checks",out var checks) && checks.TryGetProperty(id,out var check)){
                    card.State=check.GetProperty("Message").GetString()??"État non confirmé";
                    int matched=check.GetProperty("Matched").GetInt32();
                    if(!readable||(!applied&&matched>0))card.ClearChoice();else card.SelectChoice(applied);
                    card.Tone=!readable?StatusTone.Warning:applied?StatusTone.Success:matched>0?StatusTone.Warning:StatusTone.Neutral;
                }else{card.ClearChoice();card.State="État indisponible — vérification détaillée requise";card.Tone=StatusTone.Warning;}

			}
		}
		catch (Exception ex)
		{
			foreach (StatusCard card in securityCardsById.Values) { card.State = "Lecture incomplète : " + ex.Message; card.Tone = StatusTone.Warning; }
		}
	}

	private IEnumerable<TroubleshootingChoice> BuildTroubleshootingChoices()
	{
		return Array.Empty<TroubleshootingChoice>();
	}

	private PageViewModel BuildTroubleshootingPage()
	{
		return new PageViewModel("Personnalisation", "Interface, clavier, souris, confidentialité, avertissements et mises à jour", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: false, isBrowsers: false, isSoftware: false, isTroubleshooting: true);
	}

	private async Task RefreshTroubleshootingAsync()
	{
		TroubleshootingStatus = "Lecture de l’état réel de Windows…";
		TroubleshootingSnapshot troubleshootingSnapshot = await troubleshooting.ReadAsync();
		foreach (TroubleshootingToggle troubleshootingToggle in TroubleshootingToggles)
		{
			if (troubleshootingSnapshot.States.TryGetValue(troubleshootingToggle.Key, out var value))
			{
				troubleshootingToggle.IsOn = value;
			}
			troubleshootingToggle.State = troubleshootingSnapshot.States.ContainsKey(troubleshootingToggle.Key) ? (troubleshootingToggle.IsOn ? "Activé" : "Désactivé") : "État indisponible — lecture non confirmée";
		}
		foreach (TroubleshootingChoice troubleshootingChoice in TroubleshootingChoices)
		{
			if (troubleshootingSnapshot.Choices.TryGetValue(troubleshootingChoice.Key, out var value2) && troubleshootingChoice.Values.Contains(value2))
			{
				troubleshootingChoice.SelectedValue = value2;
			}
		}
		TroubleshootingStatus = ((troubleshootingSnapshot.States.Count == 0) ? "Lecture incomplète — consulte le journal BASTOS." : "État des réglages actualisé.");
	}

	private async Task ToggleTroubleshootingAsync(TroubleshootingToggle item)
	{
		bool requested = !item.IsOn;
		item.IsBusy = true;
		item.State = (requested ? "Activation…" : "Désactivation…");
		try
		{
			var (flag, text) = await troubleshooting.SetToggleAsync(item.Key, requested);
			if (flag)
			{
				item.IsOn = requested;
			}
			item.State = ((!flag) ? ("Échec — " + text) : (item.IsOn ? "Activé" : "Désactivé"));
			TroubleshootingStatus = item.Title + " — " + text;
		}
		finally
		{
			item.IsBusy = false;
		}
	}

	private async Task ApplyTroubleshootingChoiceAsync(TroubleshootingChoice item)
	{
		item.State = "Application…";
		(bool, string) obj = await troubleshooting.ApplyChoiceAsync(item.Key, item.SelectedValue);
		bool item2 = obj.Item1;
		string item3 = obj.Item2;
		item.State = (item2 ? "Appliqué" : ("Échec — " + item3));
		TroubleshootingStatus = item.Title + " — " + item3;
	}

	private async Task SetAdministratorFullNameAsync()
	{
		string text = AdministratorFullName.Trim();
		int length = text.Length;
		if (((length < 1 || length > 64) ? true : false) || text.Contains('\n') || text.Contains('\r'))
		{
			TroubleshootingStatus = "Le nom complet doit contenir entre 1 et 64 caractères.";
			return;
		}
		(bool, string) obj = await troubleshooting.ApplyChoiceAsync("AdministratorFullName", text);
		bool item = obj.Item1;
		string item2 = obj.Item2;
		TroubleshootingStatus = "Nom complet de l’administrateur — " + (item ? "terminé" : "échec") + " : " + item2;
	}

	private async Task EnsurePackageManagerReadyAsync()
	{
		try
		{
			var (flag, text) = await packages.EnsureReadyOnceAsync();
			log.Write("Logiciels", "Préparation silencieuse du gestionnaire — " + (flag ? "terminée" : "incomplète") + " : " + text, !flag);
		}
		catch (Exception ex)
		{
			log.Write("Logiciels", "Préparation silencieuse du gestionnaire incomplète — " + ex.Message, error: true);
		}
	}

	private IEnumerable<TroubleshootingToggle> BuildTweakingToggles()
	{
		(string, string, string, bool, string)[] array = new(string, string, string, bool, string)[12]
		{
			("NoLazyMode", "Désactiver le mode paresseux MMCSS", "Désactive le comportement « Lazy Mode » du planificateur multimédia MMCSS.", false, "conserver le comportement MMCSS de Windows ; aucun gain universel n’est documenté pour ce contournement."),
			("DisablePowerThrottling", "Désactiver la limitation énergétique", "Empêche Windows de ralentir les processus en arrière-plan pour économiser l’énergie.", false, "Bastos Game place déjà le jeu en HighQoS ; garder EcoQoS disponible pour l’arrière-plan libère des ressources."),
			("ThreadDpc", "DPC sur des threads dédiés", "Achemine les appels de procédure différée vers des threads dédiés.", false, "laisser le noyau et les pilotes choisir leur modèle DPC ; ce réglage non documenté dépend fortement des pilotes."),
			("DisableInterruptSteering", "Désactiver la répartition dynamique des interruptions", "Empêche Windows de redistribuer automatiquement les interruptions IRQ entre les cœurs.", false, "laisser Windows répartir les interruptions selon la charge et la topologie du processeur."),
			("DisableMpo", "Désactiver le MPO", "Désactive les superpositions matérielles multi-plans dans la pile graphique.", false, "garder MPO actif ; ne le désactiver que pour diagnostiquer scintillements, écrans noirs ou saccades DWM."),
			("CpuIdle", "États de veille du processeur", "Autorise les états d’inactivité du processeur définis par le plan d’alimentation actif.", true, "laisser Windows gérer les C-States préserve la marge thermique et le boost des processeurs modernes."),
			("DisableNagle", "Désactiver l’algorithme de Nagle", "Réduit la mise en mémoire tampon TCP afin de privilégier la latence réseau.", false, "ne pas imposer TCPNoDelay à toutes les cartes ; les jeux temps réel utilisent souvent UDP et le réglage global augmente l’overhead TCP."),
			("DisablePageCombining", "Désactiver la combinaison de pages mémoire", "Empêche Windows de fusionner des pages mémoire identiques. Redémarrage conseillé.", false, "laisser Windows réduire l’usage mémoire ; ne désactiver qu’après une mesure démontrant un coût CPU sur ce PC."),
			("DisablePagingExecutive", "Garder le noyau en mémoire physique", "Évite la pagination du noyau et de certains pilotes. Redémarrage requis.", false, "conserver la gestion mémoire Windows ; ce réglage est surtout historique et n’est plus requis depuis Windows 8."),
			("ForceDirectFlip", "Forcer Direct Flip", "Demande le mode de présentation Direct Flip lorsqu’il est pris en charge.", false, "laisser le jeu, DXGI et DWM activer automatiquement Direct Flip lorsque la configuration le permet."),
			("ForceIndependentFlip", "Forcer Independent Flip", "Demande le mode Independent Flip lorsque la configuration le permet.", false, "laisser Windows engager automatiquement Independent Flip uniquement quand la chaîne d’affichage est compatible."),
			("ForceFlipTrueImmediate", "Forcer Flip True Immediate", "Supprime la file d’attente supplémentaire pour les présentations compatibles.", false, "laisser la politique de présentation au jeu et au pilote afin d’éviter tearing et incompatibilités.")
		};
		(string Key, string Title, string Description, bool Recommended, string Why)[] array2 = array;
		for (int i = 0; i < array2.Length; i++)
		{
			(string, string, string, bool, string) tuple = array2[i];
			yield return new TroubleshootingToggle(tuple.Item1, tuple.Item2, tuple.Item3, initialState: false, ToggleTweakingAsync, tuple.Item4, tuple.Item5);
		}
	}

	private IEnumerable<TroubleshootingChoice> BuildTweakingChoices()
	{
		yield return Choice("LazyModeTimeout", "Délai du mode paresseux MMCSS", "Durée avant la suspension du cycle MMCSS. Redémarrage requis.", new string[8] { "Défaut (supprimer la valeur)", "100 ms", "200 ms", "300 ms", "400 ms", "500 ms", "600 ms", "700 ms" }, "Défaut (supprimer la valeur)", "évite une temporisation arbitraire non validée pour tous les jeux.");
		yield return Choice("SystemResponsiveness", "Réactivité système MMCSS", "Part de processeur réservée aux tâches de fond ; une valeur basse favorise l’application au premier plan.", new string[4] { "Défaut (20)", "Minimum (10)", "Désactiver MMCSS (100)", "Personnalisé (10 à 100)" }, "Défaut (20)", "préserve MMCSS et évite d’affamer l’audio, le réseau ou les services ; 100 désactive son avantage.");
		yield return Choice("ReceiveBuffers", "Tampons de réception réseau", "Mémoire allouée aux données reçues par les cartes réseau compatibles.", new string[5] { "Défaut (supprimer la valeur)", "256", "512", "1024", "2048" }, "Défaut (supprimer la valeur)", "le maximum utile dépend du pilote ; augmenter sert surtout le débit et peut augmenter la mise en file.");
		yield return Choice("TransmitBuffers", "Tampons d’émission réseau", "Mémoire conservant les données avant leur envoi sur le réseau.", new string[5] { "Défaut (supprimer la valeur)", "128", "256", "512", "1024" }, "Défaut (supprimer la valeur)", "laisse le pilote choisir une valeur adaptée à la carte et au firmware.");
		yield return Choice("CsrssPriority", "Priorité de CSRSS", "Modifie la classe de priorité du sous-système client/serveur Windows.", new string[5] { "Temps réel", "Haute", "Supérieure à la normale", "Normale", "Inférieure à la normale" }, "Normale", "CSRSS est critique ; Temps réel peut bloquer la souris, les caches disque et d’autres composants système.");
		yield return Choice("IoLatencyCap", "Plafond de latence E/S", "Plafonne la latence de fin d’E/S avec les valeurs proposées par KOS.", new string[7] { "Défaut (0x50 = 80)", "Désactivé (0)", "20", "25", "50", "500", "Personnalisé (entier)" }, "Défaut (0x50 = 80)", "aucune valeur plus agressive ne garantit un gain sur tous les contrôleurs NVMe ou pilotes.");
		yield return Choice("IoPageLockLimit", "Limite de verrouillage des pages E/S", "Quantité de mémoire que les opérations d’E/S peuvent réserver. Redémarrage requis.", new string[14]
		{
			"Défaut (supprimer la valeur)", "10 Mo (0x00A00000)", "25 Mo (0x01900000)", "50 Mo (0x03200000)", "75 Mo (0x04B00000)", "80 Mo (0x05000000)", "100 Mo (0x06400000)", "120 Mo (0x07800000)", "150 Mo (0x09600000)", "200 Mo (0x0C800000)",
			"250 Mo (0x0FA00000)", "300 Mo (0x12C00000)", "500 Mo (0x1F400000)", "Maximum selon la RAM"
		}, "Défaut (supprimer la valeur)", "la gestion mémoire moderne s’adapte à la RAM ; une limite fixe peut gaspiller ou contraindre la mémoire.");
		yield return Choice("TscSyncPolicy", "Politique de synchronisation TSC", "Méthode utilisée par Windows pour synchroniser le compteur temporel entre les cœurs.", new string[3] { "Défaut Windows (supprimer le réglage)", "Améliorée", "Héritée" }, "Défaut Windows (supprimer le réglage)", "Microsoft réserve ce paramètre BCD au diagnostic ; Windows choisit selon le processeur et le firmware.");
		yield return Choice("UsePlatformTick", "Utiliser l’horloge matérielle de la plateforme", "Choisit TSC, RTC ou restaure le réglage BCD par défaut.", new string[3] { "Défaut (supprimer le réglage)", "Désactivée (TSC)", "Activée (RTC)" }, "Défaut (supprimer le réglage)", "Microsoft réserve aussi ce paramètre au diagnostic ; le forcer peut augmenter la latence des minuteries.");
		yield return Choice("DisableDynamicTick", "Tick dynamique", "Contrôle disabledynamictick au démarrage. Le choix Désactivé correspond à Yes dans le fichier Timer Fix. Partagé avec « Timers pour les jeux ». Redémarrage requis.", new[] { "Défaut (supprimer le réglage)", "Désactivé (Yes)", "Activé (No)" }, "Défaut (supprimer le réglage)", "Microsoft réserve ce paramètre au diagnostic ; aucun gain en jeu n’est garanti.");
		yield return Choice("UsePlatformClock", "Horloge de plateforme pour le compteur", "Contrôle useplatformclock au démarrage. Le choix Ne pas forcer correspond à No dans le fichier Timer Fix. Redémarrage requis.", new[] { "Défaut (supprimer le réglage)", "Ne pas forcer (No)", "Forcer (Yes)" }, "Défaut (supprimer le réglage)", "Microsoft réserve ce paramètre au diagnostic ; Windows peut choisir l’horloge adaptée.");
		yield return Choice("QueuedPresentLimit", "Limite des images en attente", "Nombre maximal d’images pouvant être placées en file avant leur présentation.", new string[3] { "Défaut (3)", "2", "1" }, "Défaut (3)", "meilleur compromis de fluidité ; 1 peut réduire la file mais accentuer les saccades si le jeu ne cadence pas correctement.");
		TroubleshootingChoice Choice(string key, string title, string description, string[] values, string recommended, string why)
		{
			return new TroubleshootingChoice(key, title, description, values, recommended, ApplyTweakingChoiceAsync, recommended, why);
		}
	}

	private IEnumerable<TweakingTool> BuildGeneralTweakingTools()
	{
		yield return Tool("Autoruns", "Affiche et gère tous les programmes, services et tâches lancés automatiquement.", null, "https://learn.microsoft.com/sysinternals/downloads/autoruns", null, new string[2] { "Autoruns64.exe", "Autoruns.exe" }, null, "Ouvrir la source", "Source officielle — redistribution Microsoft interdite");
		yield return Tool("Device Cleanup", "Supprime du Gestionnaire de périphériques les anciennes entrées qui ne sont plus connectées.", null, "https://www.uwe-sieber.de/misc_tools_e.html", null, null, "Tools\\Tweaking\\General\\DeviceCleanup\\DeviceCleanup.exe", "Ouvrir", "Intégré à BASTOS — prêt");
		yield return Tool("GoInterruptPolicy", "Configure l’affinité et la stratégie d’interruptions des périphériques.", null, "https://github.com/spddl/GoInterruptPolicy/releases", null, null, "Tools\\Tweaking\\General\\GoInterruptPolicy\\GoInterruptPolicy.exe", "Ouvrir", "Intégré à BASTOS — prêt");
		yield return Tool("ServiWin", "Affiche et contrôle les services et pilotes Windows.", null, "https://www.nirsoft.net/utils/serviwin.html", null, null, "Tools\\Tweaking\\General\\ServiWin\\serviwin.exe", "Ouvrir", "Intégré à BASTOS — prêt");
		yield return Tool("USB Tree View", "Montre l’arborescence USB, les contrôleurs, ports et descripteurs détaillés.", null, "https://www.uwe-sieber.de/usbtreeview_e.html", null, null, "Tools\\Tweaking\\General\\UsbTreeView\\UsbTreeView.exe", "Ouvrir", "Intégré à BASTOS — prêt");
	}

	private IEnumerable<TweakingTool> BuildAmdTweakingTools()
	{
		yield return Tool("Radeon Software Slimmer", "Allège le paquet de pilotes AMD avant ou après son installation.", null, "https://github.com/GSDragoon/RadeonSoftwareSlimmer/releases", null, null, "Tools\\Tweaking\\AMD\\RadeonSoftwareSlimmer\\RadeonSoftwareSlimmer.exe", "Ouvrir", "Intégré à BASTOS — prêt");
		yield return Tool("MoreClockTool", "Règle fréquences, tensions et limites des GPU AMD compatibles.", null, "https://www.igorslab.de/en/the-moreclocktool-mct-for-free-download-the-practical-oc-attachment-to-the-morepowertool-replaces-the-wattman/3/", null, null, null, "Ouvrir la source", "Source officielle — redistribution interdite");
		yield return Tool("MorePowerTool", "Édite les limites de puissance SoftPowerPlayTable des Radeon compatibles.", null, "https://www.igorslab.de/neue-version-des-morepowertools-mpt-und-finale-des-redbioseditors-rbe-zum-download/", null, null, null, "Ouvrir la source", "Source officielle — redistribution interdite");
		yield return Tool("RadeonMod", "Éditeur historique de paramètres du pilote AMD ; réservé aux anciennes cartes et pilotes.", null, "https://www.guru3d.com/download/amd-registry-editor-download/", null, null, null, "Ouvrir la source", "Source officielle uniquement");
	}

	private IEnumerable<TweakingTool> BuildNvidiaTweakingTools()
	{
		yield return Tool("NVIDIA Inspector", "Surveille et ajuste les paramètres bas niveau des GPU NVIDIA compatibles.", null, "https://www.guru3d.com/download/nvidia-inspector-download/", null, null, null, "Ouvrir la source", "Source officielle uniquement");
		yield return Tool("Profile Inspector", "Édite les profils d’applications et réglages cachés du pilote NVIDIA.", null, "https://github.com/Orbmu2k/nvidiaProfileInspector/releases", null, null, "Tools\\Tweaking\\NVIDIA\\ProfileInspector\\nvidiaProfileInspector.exe", "Ouvrir", "Intégré à BASTOS — prêt");
		yield return Tool("NVCleanstall", "Télécharge et construit un pilote NVIDIA allégé avec les composants choisis.", null, "https://www.techpowerup.com/download/techpowerup-nvcleanstall/", null, new string[1] { "NVCleanstall.exe" }, null, "Ouvrir la source", "Source officielle uniquement");
		TweakingTool Tool(string name, string description, string? packageId, string? url, string? customAction, string[]? executables, string? localRelativePath = null, string actionLabel = "Installer / ouvrir", string initialState = "Prêt")
		{
			return new TweakingTool(name, description, packageId, url, customAction, executables, RunTweakingToolAsync, localRelativePath, actionLabel, initialState);
		}
	}

	private TweakingTool Tool(string name, string description, string? packageId, string? url, string? customAction, string[]? executables, string? localRelativePath = null, string actionLabel = "Installer / ouvrir", string initialState = "Prêt")
	{
		return new TweakingTool(name, description, packageId, url, customAction, executables, RunTweakingToolAsync, localRelativePath, actionLabel, initialState);
	}

	private async Task RunTweakingToolAsync(TweakingTool tool)
	{
		if (!string.IsNullOrWhiteSpace(tool.LocalRelativePath))
		{
			string value = Path.GetFullPath(paths.Root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
			string fullPath = Path.GetFullPath(paths.Script(tool.LocalRelativePath));
			if (!fullPath.StartsWith(value, StringComparison.OrdinalIgnoreCase))
			{
				tool.State = "Chemin intégré refusé";
				return;
			}
			if (!File.Exists(fullPath))
			{
				tool.State = "Fichier intégré manquant";
				return;
			}
			operations.Open(fullPath);
			tool.State = "Ouvert depuis BASTOS";
			return;
		}
		string text = tool.Executables.Select((string name) => ProcessExecutionService.FindExecutable(name)).FirstOrDefault((string path) => path != null);
		if (text != null)
		{
			operations.Open(text);
			tool.State = "Ouvert";
			return;
		}
		tool.State = "Préparation…";
		(bool, string) tuple;
		if (!string.IsNullOrWhiteSpace(tool.CustomAction))
		{
			tuple = await packages.ManageCustomManyAsync(new _003C_003Ez__ReadOnlySingleElementList<SoftwarePackage>(new SoftwarePackage("Outils avancés", tool.Name, tool.Name, null, null, tool.CustomAction)), "Install");
		}
		else
		{
			if (string.IsNullOrWhiteSpace(tool.PackageId))
			{
				operations.Open(tool.SourceUrl);
				tool.State = "Page officielle ouverte";
				TweakingStatus = tool.Name + " — téléchargement officiel ouvert.";
				return;
			}
			tuple = await packages.InstallAsync(new SoftwarePackage("Outils avancés", tool.Name, tool.PackageId));
		}
		tool.State = (tuple.Item1 ? "Installé" : "Échec");
		TweakingStatus = tool.Name + " — " + tuple.Item2;
		if (!tuple.Item1 && !string.IsNullOrWhiteSpace(tool.SourceUrl))
		{
			operations.Open(tool.SourceUrl);
		}
	}

	private async Task RunPower9800X3DAsync(StatusCard card)
	{
		card.State = "Autorisation administrateur ou opération en cours…";
		card.Tone = StatusTone.Neutral;
		string resultPath = Path.Combine(paths.LogRoot, $"Power-9800X3D-{Guid.NewGuid():N}.json");
		CommandResult result = await workers.RunAsync("Set-PUBG-Experiment.ps1", new _003C_003Ez__ReadOnlyArray<string>(new string[5] { "-Mode", "Power9800X3D", "-Quiet", "-ResultPath", resultPath }), elevate: true, 5);
		string message = (result.Success ? "Profil BASTOS 9800X3D Gaming activé." : result.Error);
		try
		{
			if (File.Exists(resultPath))
			{
				using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
				message = jsonDocument.RootElement.GetProperty("Message").GetString() ?? message;
			}
		}
		catch
		{
		}
		card.State = Summarize(message);
		card.Tone = (result.Success ? StatusTone.Success : StatusTone.Danger);
		if (result.Success)
		{
			card.SelectChoice(primary: false);
		}
	}

	private PageViewModel BuildTweakingPage()
	{
		return new PageViewModel("Réglages avancés", "Optimisations système, réseau et planificateur Quantum avec lecture de l’état Windows", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: false, isBrowsers: false, isSoftware: false, isTroubleshooting: false, isTweaking: true);
	}

	private async Task RefreshTweakingAsync()
	{
		TweakingStatus = "Lecture des réglages avancés…";
		TweakingSnapshot tweakingSnapshot = await tweaking.ReadAsync();
		foreach (TroubleshootingToggle tweakingToggle in TweakingToggles)
		{
			if (tweakingSnapshot.States.TryGetValue(tweakingToggle.Key, out var value))
			{
				tweakingToggle.IsOn = value;
			}
			tweakingToggle.State = tweakingSnapshot.States.ContainsKey(tweakingToggle.Key) ? (tweakingToggle.IsOn ? "Activé" : "Désactivé") : "État indisponible — lecture non confirmée";
		}
		foreach (TroubleshootingToggle riskyOptimizationToggle in RiskyOptimizationToggles)
		{
			if (tweakingSnapshot.States.TryGetValue(riskyOptimizationToggle.Key, out var value2))
			{
				riskyOptimizationToggle.IsOn = value2;
			}
			riskyOptimizationToggle.State = tweakingSnapshot.States.ContainsKey(riskyOptimizationToggle.Key) ? (riskyOptimizationToggle.IsOn ? "Activé — protection réduite" : "Désactivé — réglage Windows conservé") : "État indisponible — lecture non confirmée";
		}
		if (tweakingSnapshot.States.TryGetValue(NvidiaPStateToggle.Key, out var value3))
		{
			NvidiaPStateToggle.IsOn = value3;
		}
		NvidiaPStateToggle.State = tweakingSnapshot.States.ContainsKey(NvidiaPStateToggle.Key) ? (NvidiaPStateToggle.IsOn ? "Activé" : "Désactivé") : "État indisponible — lecture non confirmée";
		foreach (TroubleshootingChoice tweakingChoice in TweakingChoices)
		{
            tweakingChoice.State=tweakingSnapshot.Choices.TryGetValue(tweakingChoice.Key,out var actualChoice)?"Configuration enregistrée : "+actualChoice:"État indisponible — lecture non confirmée";
			if (tweakingSnapshot.Choices.TryGetValue(tweakingChoice.Key, out var value4) && tweakingChoice.Values.Contains(value4))
			{
				tweakingChoice.SelectedValue = value4;
			}
		}
		QuantumScheduler.LoadFromValue(tweakingSnapshot.Quantum);
		TweakingStatus = ((tweakingSnapshot.States.Count == 0) ? "Lecture incomplète — consulte le journal BASTOS." : "État des réglages avancés actualisé.");
		RiskyOptimizationStatus = ((tweakingSnapshot.States.Count == 0) ? "Lecture incomplète — consulte le journal BASTOS." : "Options expérimentales actualisées.");
	}

	private async Task ToggleRiskyOptimizationAsync(TroubleshootingToggle item)
	{
		bool requested = !item.IsOn;
		if (requested && Bastos.Native.LocalizedMessageBox.Show(item.Title + "\n\n" + item.Description + "\n\nCette option réduit la sécurité ou la fiabilité de Windows. BASTOS enregistrera l’état actuel pour pouvoir le restaurer. Continuer ?", "Option expérimentale BASTOS", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) != MessageBoxResult.Yes)
		{
			return;
		}
		item.IsBusy = true;
		item.State = (requested ? "Activation expérimentale…" : "Restauration de Windows…");
		try
		{
			var (flag, text) = await tweaking.SetToggleAsync(item.Key, requested);
			if (flag)
			{
				item.IsOn = requested;
			}
			item.State = ((!flag) ? ("Échec — " + text) : (item.IsOn ? "Activé — protection réduite" : "Désactivé — réglage Windows restauré"));
			RiskyOptimizationStatus = item.Title + " — " + text;
		}
		finally
		{
			item.IsBusy = false;
		}
	}

	private async Task ToggleTweakingAsync(TroubleshootingToggle item)
	{
		bool requested = !item.IsOn;
		item.IsBusy = true;
		item.State = (requested ? "Activation…" : "Restauration…");
		try
		{
			var (flag, text) = await tweaking.SetToggleAsync(item.Key, requested);
			if (flag)
			{
				item.IsOn = requested;
			}
			item.State = ((!flag) ? ("Échec — " + text) : (item.IsOn ? "Activé" : "Désactivé"));
			TweakingStatus = item.Title + " — " + text;
		}
		finally
		{
			item.IsBusy = false;
		}
	}

	private async Task ApplyTweakingChoiceAsync(TroubleshootingChoice item)
	{
		item.State = "Application…";
		string text = item.SelectedValue;
		if (text.StartsWith("Personnalisé", StringComparison.OrdinalIgnoreCase))
		{
			if (!int.TryParse(Interaction.InputBox((item.Key == "SystemResponsiveness") ? "Entre une valeur entière comprise entre 10 et 100." : "Entre un plafond de latence E/S entier positif.", item.Title, (item.Key == "SystemResponsiveness") ? "20" : "80").Trim(), out var result) || result < ((item.Key == "SystemResponsiveness") ? 10 : 0) || result > ((item.Key == "SystemResponsiveness") ? 100 : int.MaxValue))
			{
				item.State = "Valeur personnalisée annulée ou invalide";
				return;
			}
			text = result.ToString(CultureInfo.InvariantCulture);
		}
		(bool, string) obj = await tweaking.ApplyChoiceAsync(item.Key, text);
		bool item2 = obj.Item1;
		string item3 = obj.Item2;
		item.State = (item2 ? "Appliqué" : ("Échec — " + item3));
		TweakingStatus = item.Title + " — " + item3;
	}

	private async Task ApplyQuantumAsync()
	{
		QuantumScheduler.State = "Application du planificateur…";
		var (flag, text) = await tweaking.ApplyQuantumAsync(QuantumScheduler.PreviewValue);
		if (flag)
		{
			QuantumScheduler.LoadFromValue(QuantumScheduler.PreviewValue);
		}
		QuantumScheduler.State = (flag ? "Planificateur appliqué — redémarrage conseillé." : ("Échec — " + text));
		TweakingStatus = "Planificateur Quantum — " + text;
	}

	private async Task RestoreQuantumAsync()
	{
		QuantumScheduler.State = "Restauration…";
		var (flag, text) = await tweaking.RestoreQuantumAsync();
		if (flag)
		{
			QuantumScheduler.LoadFromValue(38);
		}
		QuantumScheduler.State = (flag ? "Défaut Windows restauré (0x26)." : ("Échec — " + text));
		TweakingStatus = "Planificateur Quantum — " + text;
	}

	private PageViewModel BuildSoftwarePage()
	{
		return new PageViewModel("Logiciels", "Installer, mettre à jour ou désinstaller les applications", Array.Empty<StatusCard>(), compatibilityAction: false, isReinstall: false, isBrowsers: false, isSoftware: true);
	}

	private PageViewModel BuildTestsPage()
	{
		List<StatusCard> list = new List<StatusCard>();
		StatusCard repairSfc = null;
		repairSfc = new StatusCard("sfc /scannow", "Première vérification : recherche et tente de réparer les fichiers système Windows endommagés. Si les erreurs persistent, utilise DISM puis relance SFC.", "Prêt", StatusTone.Neutral, "Réparer les fichiers système", new AsyncRelayCommand(() => RunNativeCard(repairSfc, "repair-sfc")));
		StatusCard checkDisk = null;
		checkDisk = new StatusCard("chkdsk C: /f", "En cas de problèmes de disque ou de fichiers : recherche et corrige les erreurs du système de fichiers. Une console peut proposer une vérification au prochain redémarrage.", "Prêt — aucun redémarrage automatique", StatusTone.Neutral, "Vérifier le disque", new AsyncRelayCommand(() => OpenRepairDisk(checkDisk)));
		StatusCard bootrec = null;
		bootrec = new StatusCard("bootrec /fixmbr", "Répare le code de démarrage principal d’un disque MBR. Cette commande s’utilise dans l’environnement de récupération Windows et ne répare pas une partition EFI GPT.", "À effectuer dans Windows Recovery", StatusTone.Neutral, "Voir les instructions", new AsyncRelayCommand(() => ShowBootrecInstructions(bootrec)));
		StatusCard dns = null;
		dns = new StatusCard("ipconfig /flushdns", "Si certains sites restent inaccessibles : vide le cache local DNS afin de redemander leurs adresses.", "Prêt", StatusTone.Neutral, "Vider le cache DNS", new AsyncRelayCommand(() => RunNativeCard(dns, "repair-dns")));
		StatusCard repairDism = null;
		repairDism = new StatusCard("DISM /Online /Cleanup-Image /RestoreHealth", "Si SFC ne corrige pas tout : répare les composants Windows, puis relance SFC. Une connexion Internet ou une source de réparation peut être nécessaire.", "Prêt", StatusTone.Neutral, "Réparer les composants", new AsyncRelayCommand(() => RunNativeCard(repairDism, "repair-dism")));
		StatusCard sfc = null;
		sfc = new StatusCard("SFC VerifyOnly", "Contrôle facultatif : vérifie les fichiers système sans les réparer. Pour tenter une réparation, utilise SFC /scannow en haut de la page.", "Prêt", StatusTone.Neutral, "Vérifier", new AsyncRelayCommand(() => RunNativeCard(sfc, "sfc-verify")));
		StatusCard dism = null;
		dism = new StatusCard("DISM ScanHealth", "Contrôle facultatif : analyse les composants Windows sans les réparer. Pour tenter une réparation, utilise DISM RestoreHealth en haut de la page.", "Prêt", StatusTone.Neutral, "Analyser", new AsyncRelayCommand(() => RunNativeCard(dism, "dism-scan")));
		StatusCard network = null;
		network = new StatusCard("Réseau", "En cas de problème de connexion : effectue huit mesures vers 1.1.1.1 et affiche la latence et les pertes ; les détails restent dans le journal.", "Prêt", StatusTone.Neutral, "Tester", new AsyncRelayCommand(() => RunNetworkRepairCard(network)));
		list.AddRange(new[] { repairSfc, repairDism, checkDisk, network, dns, sfc, dism, bootrec });
		return new PageViewModel("Réparation", "Commence par SFC. Utilise ensuite les autres outils selon le problème rencontré.", list, compatibilityAction: false);
	}

	private async Task OpenRepairDisk(StatusCard card)
	{
		if (Bastos.Native.LocalizedMessageBox.Show("Une console administrateur va ouvrir CHKDSK /f sur le lecteur Windows. S’il est utilisé, Windows proposera une vérification au prochain redémarrage ; lis la question dans la console et réponds selon ton choix. Continuer ?", "Vérifier le disque", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
		await RunNativeCard(card, "repair-chkdsk");
		if (card.Tone == StatusTone.Success) card.Tone = StatusTone.Warning;
	}

	private async Task RunNetworkRepairCard(StatusCard card)
	{
		bool running = true;
		card.ProgressPercent = null;
		card.ProgressVisible = true;
		var progress = new Progress<WorkerProgress>(item => { if (running) { card.State = item.Message; card.ProgressPercent = item.Percent; } });
		try { await RunCard(card, () => operations.NetworkTestAsync(progress)); }
		finally { running = false; card.ProgressVisible = false; }
	}

	private static Task ShowBootrecInstructions(StatusCard card)
	{
		Bastos.Native.LocalizedMessageBox.Show("Cette commande concerne les disques MBR et s’exécute dans Windows Recovery.\n\nDans Windows, ouvre Paramètres > Système > Récupération > Démarrage avancé, puis choisis Dépannage > Options avancées > Invite de commandes.\n\nSaisis : bootrec /fixmbr\n\nSur un PC UEFI avec disque GPT, cette commande ne répare pas le démarrage EFI. Utilise d’abord l’outil de redémarrage système de Windows Recovery.", "Réparer le démarrage MBR", MessageBoxButton.OK, MessageBoxImage.Information);
		card.State = "Instructions affichées — aucune réparation lancée.";
		return Task.CompletedTask;
	}

	private PageViewModel BuildJournalPage() => new("Journal", "Historique des opérations et résultats vérifiés • conservés sur ce PC", Array.Empty<StatusCard>(), false);

	private static StatusCard ActionCard(string title, string description, string state, string action, Func<(bool Success, string Message)> execute)
	{
		StatusCard card = null;
		card = new StatusCard(title, description, state, StatusTone.Neutral, action, new AsyncRelayCommand(() => RunCard(card, execute)));
		return card;
	}

	private static async Task RunCard(StatusCard card, Func<Task<OperationResult>> operation)
	{
		card.State = "Opération en cours…";
		card.Tone = StatusTone.Neutral;
		try
		{
			var result = await operation();
			card.State = result.UserMessage;
			card.StateDetail = new OperationHistoryEntry(result, "").TechnicalDetail + "\n" + string.Join("\n", new OperationHistoryEntry(result, "").Checks);
			card.Tone = result.State switch {
				OperationState.Succeeded => StatusTone.Success,
				OperationState.Partial or OperationState.Unconfirmed or OperationState.Cancelled or OperationState.TimedOut => StatusTone.Warning,
				_ => StatusTone.Danger
			};
		}
		catch (Exception)
		{
			card.State = "L’opération n’a pas pu être terminée. Consulte le journal avant de réessayer.";
			card.Tone = StatusTone.Danger;
		}
	}

	private static async Task RunCard(StatusCard card, Func<(bool Success, string Message)> operation)
	{
		card.State = "Opération en cours…";
		card.Tone = StatusTone.Neutral;
		try
		{
			(bool, string) tuple = operation();
			bool item = tuple.Item1;
			string item2 = tuple.Item2;
			card.State = item2;
			card.Tone = (item ? StatusTone.Success : StatusTone.Danger);
		}
		catch (Exception ex)
		{
			card.State = "Opération interrompue. Consulte les détails avant de réessayer.";
			card.StateDetail = ex.ToString();
			card.Tone = StatusTone.Danger;
		}
		await Task.CompletedTask;
	}

	private static async Task RunCard(StatusCard card, Func<Task<(bool Success, string Message)>> operation)
	{
		card.State = "Opération en cours…";
		card.Tone = StatusTone.Neutral;
		try
		{
			(bool, string) obj = await operation();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			card.State = item2;
			card.Tone = (item ? StatusTone.Success : StatusTone.Danger);
		}
		catch (Exception ex)
		{
			card.State = "Opération interrompue. Consulte les détails avant de réessayer.";
			card.StateDetail = ex.ToString();
			card.Tone = StatusTone.Danger;
		}
	}

	private static async Task RunChoiceCard(StatusCard card, bool primary, Func<(bool Success, string Message)> operation)
	{
		card.State = "Opération en cours…";
		card.Tone = StatusTone.Neutral;
		try
		{
			(bool, string) tuple = operation();
			bool item = tuple.Item1;
			string item2 = tuple.Item2;
			card.State = item2;
			card.Tone = (item ? StatusTone.Success : StatusTone.Danger);
			if (item)
			{
				card.SelectChoice(primary);
			}
		}
		catch (Exception ex)
		{
			card.State = "Opération interrompue. Consulte les détails avant de réessayer.";
			card.StateDetail = ex.ToString();
			card.Tone = StatusTone.Danger;
		}
		await Task.CompletedTask;
	}

	private async Task RunNativeCard(StatusCard card, string action, bool? selectedPrimary = null)
	{
		bool tracksProgress = action is "repair-sfc" or "repair-dism" or "repair-dns" or "repair-chkdsk" or "sfc-verify" or "dism-scan";
		bool running = true;
		card.State = "En attente de l’autorisation administrateur…";
		card.Tone = StatusTone.Neutral;
		card.ProgressPercent = null;
		card.ProgressVisible = tracksProgress;
		var progress = tracksProgress ? new Progress<RepairProgress>(item => { if (running) { card.State = item.Message; card.ProgressPercent = item.Percent; } }) : null;
		try
		{
			NativeActionResult result = await nativeActions.RunElevatedAsync(action, progress);
			running = false;
			card.State = Summarize(result.Message);
			card.StateDetail = result.Message;
			card.Tone = result.Success ? StatusTone.Success : StatusTone.Danger;
			if (result.Success && selectedPrimary.HasValue) card.SelectChoice(selectedPrimary.Value);
		}
		catch (Exception error) { running = false; card.State = "Opération interrompue : " + error.Message; card.Tone = StatusTone.Danger; }
		finally { running = false; card.ProgressVisible = false; }
	}

	private async Task PickGame(StatusCard card, bool blocked)
	{
		OpenFileDialog dialog = new OpenFileDialog
		{
			Title = Bastos.Native.InterfaceLanguage.Instance.Translate(blocked ? "Application à bloquer" : "Jeu à autoriser"),
			Filter = "Applications (*.exe)|*.exe",
			CheckFileExists = true,
			Multiselect = false
		};
		if (dialog.ShowDialog() == true)
		{
			await RunCard(card, delegate
			{
				game.AddGame(dialog.FileName, blocked);
				BastosGameConfig bastosGameConfig = game.Load();
				return (Success: true, Message: DescribeEntries(blocked ? bastosGameConfig.BlockedApps : bastosGameConfig.Games));
			});
		}
	}

	private async Task ManageGameList(StatusCard card, bool blocked)
	{
		GameListWindow gameListWindow = new GameListWindow(game, blocked);
		gameListWindow.Owner = Application.Current.MainWindow;
		gameListWindow.ShowDialog();
		BastosGameConfig bastosGameConfig = game.Load();
		card.State = DescribeEntries(blocked ? bastosGameConfig.BlockedApps : bastosGameConfig.Games);
		await Task.CompletedTask;
	}

	private static string DescribeEntries(IEnumerable<GameEntry> entries)
	{
		string[] array = (from entry in entries
			select entry.Name into name
			where !string.IsNullOrWhiteSpace(name)
			select name).Take(5).ToArray();
		if (array.Length != 0)
		{
			return string.Join(", ", array) + ((entries.Count() > array.Length) ? "…" : string.Empty);
		}
		return "Liste vide";
	}

	private static string Summarize(string value)
	{
		string text = value.Replace('\r', ' ').Replace('\n', ' ').Trim();
		if (text.Length > 260)
		{
			return text.Substring(0, 260) + "…";
		}
		return text;
	}

	private async void UpdatePerformanceDashboard()
	{
		if(disposed || performanceReadRunning)return;
		performanceReadRunning=true;
		long started=System.Diagnostics.Stopwatch.GetTimestamp();
		try
		{
			PerformanceSnapshot performanceSnapshot = await performance.ReadAsync();
			if(disposed)return;
			CpuMetric.Update(performanceSnapshot.CpuPercent, $"{performanceSnapshot.CpuPercent:0}%", "Utilisation globale en temps réel", $"{performanceSnapshot.LogicalProcessors} processeur(s) logique(s)");
			GpuMetric.Update(performanceSnapshot.Gpu.Percent, performanceSnapshot.Gpu.IsAvailable ? $"{performanceSnapshot.Gpu.Percent:0}%" : "N/D", performanceSnapshot.Gpu.IsAvailable ? "Moteur graphique le plus sollicité" : "Compteur GPU en attente d’activité", performanceSnapshot.Gpu.Name);
			MemoryMetric.Update(performanceSnapshot.MemoryPercent, $"{performanceSnapshot.MemoryPercent:0}%", FormatCapacity(performanceSnapshot.MemoryUsed) + " utilisés sur " + FormatCapacity(performanceSnapshot.MemoryTotal), FormatCapacity(performanceSnapshot.MemoryTotal - performanceSnapshot.MemoryUsed) + " disponibles");
			double bytesPerSecond = performanceSnapshot.Network.DownloadBytesPerSecond + performanceSnapshot.Network.UploadBytesPerSecond;
			NetworkMetric.Update(performanceSnapshot.Network.Percent, FormatNetworkRate(bytesPerSecond), "↓ " + FormatNetworkRate(performanceSnapshot.Network.DownloadBytesPerSecond) + "   ↑ " + FormatNetworkRate(performanceSnapshot.Network.UploadBytesPerSecond), performanceSnapshot.Network.AdapterName);
			string newDetail = (performanceSnapshot.Disk.IsActivity ? ("Lecture " + FormatStorageRate(performanceSnapshot.Disk.ReadBytesPerSecond) + "   •   Écriture " + FormatStorageRate(performanceSnapshot.Disk.WriteBytesPerSecond)) : "Occupation du volume système (activité E/S indisponible)");
			string newSecondary = ((performanceSnapshot.Disk.TotalBytes > 0) ? (FormatCapacity((ulong)performanceSnapshot.Disk.FreeBytes) + " libres sur " + FormatCapacity((ulong)performanceSnapshot.Disk.TotalBytes)) : "Capacité du volume système indisponible");
			DiskMetric.Update(performanceSnapshot.Disk.Percent, $"{performanceSnapshot.Disk.Percent:0}%", newDetail, newSecondary);
			if (!hardwareProfileReady)
			{
				SetHardwareNames(performanceSnapshot.CpuName, "Mémoire vive — " + FormatCapacity(performanceSnapshot.MemoryTotal), performanceSnapshot.Gpu.Name, "Disque système", performanceSnapshot.Network.AdapterName);
			}
			RefreshSelectedHardwareName();
			DashboardStatus = hardwareProfileDetectionPending ? "Première détection du matériel… ce résultat sera mémorisé" : "Surveillance en direct • matériel mémorisé sur ce PC";
			DashboardUpdatedAt = $"Mis à jour à {performanceSnapshot.CapturedAt:HH:mm:ss}";
		}
		catch (Exception ex)
		{
			DashboardStatus = "Mesures momentanément indisponibles : " + ex.Message;
			DashboardUpdatedAt = "Nouvelle tentative automatique dans une seconde";
		}
		finally { performanceReadRunning=false; RuntimeTimingService.Record("dashboard-sample",System.Diagnostics.Stopwatch.GetElapsedTime(started)); }
	}

	private async Task RunForegroundPriorityCard(StatusCard card, string action)
	{
		card.State = "Autorisation administrateur…";
		card.Tone = StatusTone.Neutral;
		NativeActionResult result = await nativeActions.RunElevatedAsync(action);
		if (!result.Success)
		{
			card.State = Summarize(result.Message);
			card.Tone = StatusTone.Danger;
			return;
		}

		bool enabled = tuning.ForegroundPriorityEnabled;
		int? value = tuning.ForegroundPriorityValue;
		card.State = enabled ? "Appliqué — valeur 0x26" : (value.HasValue ? $"Restauré — valeur 0x{value.Value:X2}" : "Restauré — valeur absente");
		card.Tone = enabled ? StatusTone.Success : StatusTone.Neutral;
		card.SelectChoice(enabled);
	}

	private async Task RunPerformanceCard(StatusCard card, string id, bool enable)
	{
		card.State = "Autorisation administrateur…";
		card.Tone = StatusTone.Neutral;
		NativeActionResult result = await nativeActions.RunElevatedAsync($"performance-{(enable ? "on" : "restore")}:{id}");
		if (!result.Success)
		{
			card.State = Summarize(result.Message);
			card.Tone = StatusTone.Danger;
			return;
		}
		bool applied = tuning.IsPerformanceOptimizationEnabled(id);
		card.State = NativeWorkerService.ReadPerformanceState(id).Message;
		card.Tone = applied ? StatusTone.Success : StatusTone.Neutral;
		card.SelectChoice(applied);
	}

	private async Task RunGpuOptimizationCard(StatusCard card, string id, bool enable)
	{
		card.State = "Autorisation administrateur…";
		card.Tone = StatusTone.Neutral;
		NativeActionResult result = await nativeActions.RunElevatedAsync($"gpu-{(enable ? "on" : "restore")}:{id}");
		if (!result.Success) { card.State = Summarize(result.Message); card.Tone = StatusTone.Danger; return; }
		var service = new GpuOptimizationService();
		bool applied = service.IsEnabled(id);
		card.State = applied ? "Appliqué — redémarrage recommandé" : "Restauré aux valeurs précédentes";
		card.Tone = applied ? StatusTone.Success : StatusTone.Neutral;
		card.SelectChoice(applied);
	}

	private async Task RunSecurityCard(StatusCard card, string id, bool enable)
	{
		card.State = "Autorisation administrateur…"; card.Tone = StatusTone.Neutral;
		string resultPath = Path.Combine(paths.LogRoot, $"SecurityPrivacy-{id}-{Guid.NewGuid():N}.json");
		CommandResult result = await workers.RunAsync("Manage-BASTOS-SecurityPrivacy.ps1", new[] { "-Id", id, "-Action", enable ? "Enable" : "Restore", "-ResultPath", resultPath, "-ExpectedUserSid", System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value }, elevate: true, 20);
		string message = result.Success ? (enable ? "Appliqué — redémarrage recommandé" : "Valeurs précédentes restaurées") : result.Error;
		try { if (File.Exists(resultPath)) { using JsonDocument json = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath)); message = json.RootElement.GetProperty("Message").GetString() ?? message; if(!json.RootElement.GetProperty("Success").GetBoolean())result=result with {Success=false}; } } catch { }
        await RefreshSecurityPrivacyStatesAsync();
        if(!result.Success){card.State=message;card.Tone=StatusTone.Danger;}
	}

	private async Task InitializeHardwareProfileAsync()
	{
		long started=System.Diagnostics.Stopwatch.GetTimestamp();
		try
		{
			var result = await hardwareProfiles.GetOrDetectAsync();
			ApplyHardwareProfile(result.Profile);
			hardwareProfileDetectionPending = false;
			DashboardStatus = result.FromCache ? "Surveillance en direct • matériel chargé depuis la mémoire locale" : "Matériel détecté et mémorisé • surveillance en direct";
		}
		catch (Exception ex)
		{
			hardwareProfileDetectionPending = false;
			DashboardStatus = "Noms matériels partiellement disponibles : " + ex.Message;
		}
		finally { RuntimeTimingService.Record("hardware-profile",System.Diagnostics.Stopwatch.GetElapsedTime(started)); log.Write("Réactivité",RuntimeTimingService.Summary()); }
	}

	private void ApplyHardwareProfile(HardwareProfile profile)
	{
		UpdateGpuInventory(profile.GpuDeviceIds);
		SetHardwareNames(profile.CpuName, profile.MemoryName, profile.GpuName, profile.DiskName, profile.NetworkName);
		hardwareProfileReady = true;
		RefreshSelectedHardwareName();
	}

	internal void UpdateGpuInventory(string[]? deviceIds)
	{
		GpuDeviceIds = deviceIds;
		gpuInventoryAvailable = deviceIds != null;
		detectedGpuVendors = GpuOptimizationService.DetectVendors(deviceIds);
		GpuOptimizationCards.Clear();
		BuildGpuOptimizationCards();
		RaisePropertyChanged(nameof(GpuOptimizationSummary));
	}

	private void SetHardwareNames(string cpu, string memory, string gpu, string disk, string network)
	{
		SetHardwareName(ref cpuHardwareName, cpu, "CpuHardwareName");
		SetHardwareName(ref memoryHardwareName, memory, "MemoryHardwareName");
		SetHardwareName(ref gpuHardwareName, gpu, "GpuHardwareName");
		SetHardwareName(ref diskHardwareName, disk, "DiskHardwareName");
		SetHardwareName(ref networkHardwareName, network, "NetworkHardwareName");
	}

	private void SetHardwareName(ref string field, string value, string propertyName)
	{
		string normalized = string.IsNullOrWhiteSpace(value) ? "Matériel non identifié" : value.Trim();
		if (!string.Equals(field, normalized, StringComparison.Ordinal))
		{
			field = normalized;
			RaisePropertyChanged(propertyName);
		}
	}

	private void SelectPrimaryMetric(PerformanceMetric metric)
	{
		SelectedPrimaryMetric = metric;
		RefreshSelectedHardwareName();
	}

	private void RefreshSelectedHardwareName()
	{
		SelectedHardwareName = (IsCpuMetricSelected ? cpuHardwareName : (IsGpuMetricSelected ? gpuHardwareName : memoryHardwareName));
	}

	private static string FormatCapacity(ulong bytes)
	{
		double num = bytes;
		string[] array = new string[5] { "o", "Ko", "Mo", "Go", "To" };
		int num2 = 0;
		while (num >= 1024.0 && num2 < array.Length - 1)
		{
			num /= 1024.0;
			num2++;
		}
		return $"{num:0.#} {array[num2]}";
	}

	private static string FormatNetworkRate(double bytesPerSecond)
	{
		double num = Math.Max(0.0, bytesPerSecond) * 8.0;
		if (!(num >= 1000000000.0))
		{
			if (num >= 1000000.0)
			{
				return $"{num / 1000000.0:0.##} Mb/s";
			}
			return $"{num / 1000.0:0.#} Kb/s";
		}
		return $"{num / 1000000000.0:0.##} Gb/s";
	}

	private static string FormatStorageRate(double bytesPerSecond)
	{
		double num = Math.Max(0.0, bytesPerSecond);
		if (!(num >= 1073741824.0))
		{
			if (num >= 1048576.0)
			{
				return $"{num / 1048576.0:0.##} Mo/s";
			}
			return $"{num / 1024.0:0.#} Ko/s";
		}
		return $"{num / 1073741824.0:0.##} Go/s";
	}

    internal async Task RefreshAllConfigurationStatesAsync(bool force = false)
    {
        string page = SelectedNavigation?.PageKey ?? "home";
        string category = OptimizationCategories.Selected.Key;
        string key = page == "optimizations" ? page + ":" + category : page;
        if(page is not ("optimizations" or "troubleshooting" or "tweaking")) return;
        await Task.Yield();
        if(disposed || SelectedNavigation?.PageKey != page || (page == "optimizations" && OptimizationCategories.Selected.Key != category)) return;
        await readRefreshes.RunAsync(key, async () => {
            if(disposed)return;
            if(page == "optimizations")
            {
                if(category == "cpu") await RefreshInterruptAffinityCardsAsync();
                if(category == "graphics") { GpuOptimizationCards.Clear(); BuildGpuOptimizationCards(); }
                if(category == "windows") PowerPlans.Refresh(preserveSelection:true);
                if(category is "windows" or "sound" or "network")
                    await readRefreshes.RunAsync("competitive",RefreshCompetitiveAsync,force);
                if(category == "network") await NetworkOptimization.RefreshAsync();
                if(category is "devices" or "network" or "windows")
                    await readRefreshes.RunAsync("extras",Extras.RefreshAsync,force);
            }
            else
            {
                await readRefreshes.RunAsync("preferences",RefreshTroubleshootingAsync,force);
                await readRefreshes.RunAsync("advanced",RefreshTweakingAsync,force);
                if(page == "troubleshooting") await RefreshSecurityPrivacyStatesAsync();
                await readRefreshes.RunAsync("extras",Extras.RefreshAsync,force);
            }
            if(!disposed)log.Write("Réactivité",RuntimeTimingService.Summary());
        }, force);
    }

    private void Refresh()
    {
        string key = SelectedNavigation?.PageKey ?? "home";
        BuildPages();
        CurrentPage=pages[key];
        if(key == "journal") _ = Journal.RefreshAsync();
        RefreshVisibleConfigurationStates();
        _ = RefreshAllConfigurationStatesAsync(force:true);
        if(key == "home") UpdatePerformanceDashboard();
    }
	private static string? ReadArgument(string[] arguments, string name)
	{
		for (int i = 0; i < arguments.Length - 1; i++)
		{
			if (arguments[i].Equals(name, StringComparison.OrdinalIgnoreCase))
			{
				return arguments[i + 1];
			}
		}
		return null;
	}

	public void Dispose()
	{
		disposed=true;
        Cleaner.Dispose();
		performanceTimer.Stop();
		performance.Dispose();
		GC.SuppressFinalize(this);
	}
}
