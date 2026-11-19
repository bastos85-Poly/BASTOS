using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Markup;
using Bastos.Native.Models;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class MainWindow : Window, IComponentConnector
{
	private readonly Stopwatch startup = Stopwatch.StartNew();

	public MainWindow()
	{
		InitializeComponent();
        if (Environment.GetCommandLineArgs().Contains("--language-preview")) Title = "BASTOS — aperçu Français / English";
		SourceInitialized += (_, _) => TryEnableDarkTitleBar();
		OptimizationCategorySelector.SelectionChanged += (_, _) => OptimizationCategoryContent.ScrollToTop();
		base.DataContext = new MainViewModel();
        Closing += (_, e) => { if (DataContext is MainViewModel vm && vm.Cleaner.IsBusy) { e.Cancel = true; vm.Cleaner.CancelCommand.Execute(null); } };
		base.Loaded += OnLoaded;
		base.Activated += (_, _) => {if(DataContext is MainViewModel model){model.Reinstall.RefreshDownloadedIsos();model.RefreshVisibleConfigurationStates();}};
		base.Closed += delegate
		{
			AdvancedDisplayCalibrationPage?.ReleaseControl();
			(base.DataContext as IDisposable)?.Dispose();
		};
	}

	private async void OnLoaded(object sender, RoutedEventArgs e)
	{
		startup.Stop();
        if(Environment.GetCommandLineArgs().Contains("--official-iso-smoke-test")){await RunOfficialIsoSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--language-smoke-test")){await RunLanguageSmokeAsync();return;}
        Bastos.Native.Services.RuntimeTimingService.Record("window-loaded",startup.Elapsed);
        if(Environment.GetCommandLineArgs().Contains("--donation-smoke-test")){await RunDonationSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--appearance-detection-smoke-test")){await RunAppearanceDetectionSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--responsiveness-only-test")) { await RunResponsivenessSmokeAsync(); Application.Current.Shutdown(0); return; }
        if(Environment.GetCommandLineArgs().Contains("--persistence-smoke-test")){await RunPersistenceSmokeAsync(false);return;}
        if(Environment.GetCommandLineArgs().Contains("--persistence-verify-test")){await RunPersistenceSmokeAsync(true);return;}
        if(Environment.GetCommandLineArgs().Contains("--cursor-smoke-test")){await RunCursorSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--curves-smoke-test")){await RunCurvesSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--extras-smoke-test")){await RunExtrasSmokeAsync();return;}
        if(Environment.GetCommandLineArgs().Contains("--competitive-smoke-test")){await RunCompetitiveSmokeAsync();return;}
		TryEnableDarkTitleBar();
        if(Environment.GetCommandLineArgs().Contains("--language-preview")) return;
        if(Environment.GetCommandLineArgs().Contains("--installation-display-smoke-test")) { await RunInstallationDisplaySmokeAsync(); Application.Current.Shutdown(0); return; }
		if (!Environment.GetCommandLineArgs().Any((string arg) => arg.Equals("--smoke-test", StringComparison.OrdinalIgnoreCase)))
		{
			if (DataContext is MainViewModel installationVm && installationVm.Installation.ShouldShowAutomatically)
				installationVm.OpenInstallationCommand.Execute(null);
			return;
		}
		string path = Path.Combine(Path.GetTempPath(), "BASTOS-Native-SmokeTest.txt");
		MainViewModel mainViewModel = (MainViewModel)base.DataContext;
		var timers = mainViewModel.AdvancedSettingsGroups.Single(group => group.Key == "timers");
		if (!new[] { "TscSyncPolicy", "UsePlatformTick", "DisableDynamicTick", "UsePlatformClock" }.All(key => timers.Choices.Count(choice => choice.Key == key) == 1))
			throw new InvalidOperationException("Les quatre choix d’horloge doivent être disponibles une fois chacun.");
		if (!Bastos.Native.Services.MouseCurveProfiles.Names.Contains("Courbes nulles"))
			throw new InvalidOperationException("Le mode de pointeur Courbes nulles est absent.");
		if (mainViewModel.Extras.AppearanceOptions.Count(option => option.Key == "ClassicContextMenu") != 1)
			throw new InvalidOperationException("L’option de menu contextuel classique doit apparaître une seule fois dans les profils.");
		mainViewModel.Extras.Preset = "Classique";
		if (!mainViewModel.Extras.AppearanceOptions.Single(option => option.Key == "ClassicContextMenu").Selected)
			throw new InvalidOperationException("Le profil Classique ne sélectionne pas le menu contextuel.");
		mainViewModel.Extras.Preset = "Sobre";
		if (!mainViewModel.PowerPlans.Plans.Any(p => p.Id == Bastos.Native.Services.PowerPlanService.BalancedId) ||
			!mainViewModel.PowerPlans.Plans.Any(p => p.Id == Bastos.Native.Services.PowerPlanService.PerformanceId) ||
			!mainViewModel.PowerPlans.Plans.Any(Bastos.Native.Services.PowerPlanService.IsZoicAmd) ||
			!mainViewModel.PowerPlans.Plans.Any(p => p.Id == Bastos.Native.Services.PowerPlanService.BastosAmdId && p.Name == "Bastos Power Plan (AMD)"))
			throw new InvalidOperationException("Les choix d’alimentation sont absents.");
		using (var powerResource = typeof(App).Assembly.GetManifestResourceStream("Bastos.PowerPlans.ZoicAMD.pow"))
			if (powerResource == null || powerResource.Length < 4096)
				throw new InvalidOperationException("Profil AMD embarqué absent ou invalide.");
		if (HardwareHome == null || mainViewModel.TroubleshootingToggles.Count != 2 ||
			mainViewModel.TroubleshootingChoices.Count != 0)
			throw new InvalidOperationException("Régression accueil matériel / Personnalisation.");
		if (!mainViewModel.SoftwareApps.Any(item => item.Package.Id == "BASTOS.EqualizerAPO") ||
			!mainViewModel.SoftwareApps.Any(item => item.Package.Id == "BASTOS.PeaceEqualizer"))
			throw new InvalidOperationException("Catalogue audio Equalizer APO / Peace absent.");
		if (mainViewModel.Reinstall.AppxRemovalOptions.Count != 26 ||
			mainViewModel.Reinstall.AppxRemovalOptions.Any(item => !item.IsSelected) ||
			!mainViewModel.Reinstall.RemoveOneDrive || !mainViewModel.Reinstall.DisableConsumerContent ||
			mainViewModel.Reinstall.GetSelectedAppxRemovalNames().Length != 27)
			throw new InvalidOperationException("Les suppressions ISO ne sont pas toutes sélectionnées par défaut.");
		var preservedApp = mainViewModel.Reinstall.AppxRemovalOptions[0];
		preservedApp.IsSelected = false;
		mainViewModel.Reinstall.RemoveOneDrive = false;
		if (mainViewModel.Reinstall.GetSelectedAppxRemovalNames().Contains(preservedApp.PackageId) ||
			mainViewModel.Reinstall.GetSelectedAppxRemovalNames().Contains("Microsoft.OneDriveSync"))
			throw new InvalidOperationException("Une application conservée reste dans la liste de suppression ISO.");
		var customizationWindow = new IsoCustomizationWindow(mainViewModel.Reinstall);
		if (customizationWindow.DataContext != mainViewModel.Reinstall)
			throw new InvalidOperationException("La fenêtre de choix ISO ne charge pas la liste.");
		customizationWindow.Close();
		string? detectedKeyboard = Bastos.Native.Services.WindowsKeyboardLayoutDetector.DetectInputLocale();
		if (!mainViewModel.Reinstall.KeyboardSelectionHint.StartsWith("Disposition enregistrée") && mainViewModel.Reinstall.SelectedKeyboard.InputLocale != "040C:0000040C")
			throw new InvalidOperationException("Le clavier par défaut doit rester AZERTY français, indépendamment de la session actuelle.");
		var manualKeyboard = mainViewModel.Reinstall.Keyboards.First(item => item != mainViewModel.Reinstall.SelectedKeyboard);
		mainViewModel.Reinstall.SelectedKeyboard = manualKeyboard;
		mainViewModel.Reinstall.RefreshDetectedKeyboard();
		if (mainViewModel.Reinstall.SelectedKeyboard != manualKeyboard)
			throw new InvalidOperationException("Le choix manuel du clavier a été remplacé.");
		for (int patternIndex = 0; patternIndex < 5; patternIndex++)
		{
			var calibration = new DisplayCalibrationWindow(patternIndex);
			if (calibration.WindowStyle != WindowStyle.None || calibration.WindowState != WindowState.Maximized || !calibration.Topmost)
				throw new InvalidOperationException("Mire non configurée en plein écran.");
			calibration.Close();
		}
		if (!Environment.GetCommandLineArgs().Contains("--page") && mainViewModel.SelectedNavigation?.PageKey != "home")
			throw new InvalidOperationException("Le démarrage par défaut doit afficher l’accueil matériel.");
		if(Environment.GetCommandLineArgs().Contains("--responsiveness-smoke-test")) await RunResponsivenessSmokeAsync();
		RunSettingsClassificationSmoke(mainViewModel);
        RunHeliumSmoke(mainViewModel);
		mainViewModel.SelectedNavigation = mainViewModel.Navigation.First(item => item.PageKey == "tweaking");
		mainViewModel.ShowTweakingDisplayCommand.Execute(null);
		if (!mainViewModel.IsTweakingDisplaySelected || TweakingDisplayTab == null ||
			AdvancedDisplaySection.Visibility != Visibility.Visible)
			throw new InvalidOperationException("Catégorie Écran absente de Réglages avancés.");
		if (HardwareHome.IsVisible && HardwareHome.ActualWidth > 0 && HardwareHome.ActualHeight > 0)
		{
			var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)HardwareHome.ActualWidth, (int)HardwareHome.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
			bitmap.Render(HardwareHome);
			var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
			encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
			using var output = File.Create(Path.Combine(Path.GetTempPath(), "BASTOS-HardwareHome-Smoke.png"));
			encoder.Save(output);
		}
		string text = mainViewModel.CurrentPage?.Cards.FirstOrDefault((StatusCard card) => card.Title == "HAGS")?.State ?? "absent";
		int num = 0;
		mainViewModel.SelectedNavigation = mainViewModel.Navigation.First(item => item.PageKey == "hardware");
		if (mainViewModel.CurrentPage.GraphicsStandardCard?.HasPrimaryAction != true ||
			mainViewModel.CurrentPage.GraphicsLiteCard?.HasPrimaryAction != true ||
			mainViewModel.CurrentPage.HardwareAnalysisCard?.HasPrimaryAction != true)
			throw new InvalidOperationException("Les deux installations graphiques ou l’analyse matérielle sont absentes.");
		UpdateLayout();
		SaveSmokeVisual(this, "BASTOS-Hardware-Layout-Smoke.png");
		mainViewModel.SelectedNavigation = mainViewModel.Navigation.First(item => item.PageKey == "tests");
		var repairTitles = new[] { "sfc /scannow", "chkdsk C: /f", "bootrec /fixmbr", "ipconfig /flushdns", "DISM /Online /Cleanup-Image /RestoreHealth" };
		if (mainViewModel.CurrentPage.Title != "Réparation" || repairTitles.Any(title => !mainViewModel.CurrentPage.Cards.Any(card => card.Title == title && card.HasPrimaryAction)))
			throw new InvalidOperationException("Les cinq outils de réparation ne sont pas tous disponibles.");
		var expectedRepairOrder = new[] { "sfc /scannow", "DISM /Online /Cleanup-Image /RestoreHealth", "chkdsk C: /f", "Réseau", "ipconfig /flushdns", "SFC VerifyOnly", "DISM ScanHealth", "bootrec /fixmbr" };
		if (!mainViewModel.CurrentPage.Cards.Select(card => card.Title).SequenceEqual(expectedRepairOrder))
			throw new InvalidOperationException("L’ordre des outils de réparation est inattendu.");
		var repairSmokeCard = mainViewModel.CurrentPage.Cards.First(card => card.Title == "sfc /scannow");
		repairSmokeCard.State = "En cours : 31 % (étape indiquée par Windows).";
		repairSmokeCard.ProgressVisible = true;
		repairSmokeCard.ProgressPercent = 31;
		if (repairSmokeCard.ProgressIndeterminate) throw new InvalidOperationException("Progression déterminée non représentée.");
		UpdateLayout();
		System.Collections.Generic.IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
		{
			if (root is T item) yield return item;
			for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(root); i++)
				foreach (var child in Descendants<T>(System.Windows.Media.VisualTreeHelper.GetChild(root, i))) yield return child;
		}
		if (!Descendants<System.Windows.Controls.TextBlock>(this).Any(text => text.IsVisible && text.Text == repairSmokeCard.Description) ||
			Descendants<System.Windows.Controls.Expander>(this).Any(expander => expander.IsVisible && Equals(expander.Header, "En savoir plus")))
			throw new InvalidOperationException("La description de Réparation doit être visible directement.");
		SaveSmokeVisual(this, "BASTOS-Repair-Layout-Smoke.png");
		repairSmokeCard.ProgressVisible = false;
		repairSmokeCard.ProgressPercent = null;
		repairSmokeCard.State = "Prêt";
		foreach (NavigationItem item in mainViewModel.Navigation)
		{
			mainViewModel.SelectedNavigation = item;
			num += mainViewModel.CurrentPage?.Cards.Count((StatusCard card) => card.HasPrimaryAction || card.HasSecondaryAction) ?? 0;
		}
		string value = $"{mainViewModel.Reinstall.Languages.Count}/{mainViewModel.Reinstall.Keyboards.Count}/{mainViewModel.Reinstall.Releases.Count}/{mainViewModel.Reinstall.Methods.Count}";
		await mainViewModel.Journal.RefreshAsync();
		if (mainViewModel.CurrentPage?.IsJournal != true || mainViewModel.CurrentPage.IsStandardPage)
			throw new InvalidOperationException("La page Journal dédiée est absente.");
		UpdateLayout();
		var journalBitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
		journalBitmap.Render(this);
		var journalEncoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
		journalEncoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(journalBitmap));
		using (var journalOutput = File.Create(Path.Combine(Path.GetTempPath(), "BASTOS-Journal-Smoke.png"))) journalEncoder.Save(journalOutput);
		RunIsoCatalogSmoke(mainViewModel);
		RunGuidedLayoutSmoke(mainViewModel);
		if (Environment.GetCommandLineArgs().Contains("--storage-smoke-test")) await RunStorageSmokeAsync();
		if (Environment.GetCommandLineArgs().Contains("--preflight-smoke-test")) RunPreflightSmoke();
		if (Environment.GetCommandLineArgs().Contains("--guidance-smoke-test")) await RunGuidanceSmokeAsync();
		if (Environment.GetCommandLineArgs().Contains("--cancellation-smoke-test")) await RunCancellationSmokeAsync(mainViewModel);
		if (Environment.GetCommandLineArgs().Contains("--resume-smoke-test")) await RunResumeSmokeAsync();
		if (Environment.GetCommandLineArgs().Contains("--integrity-smoke-test")) await RunIntegritySmokeAsync();
		if (Environment.GetCommandLineArgs().Contains("--log-maintenance-smoke-test")) await RunLogMaintenanceSmokeAsync(mainViewModel);
		if (Environment.GetCommandLineArgs().Contains("--postinstall-smoke-test")) RunInstallationSmoke();
		if (Environment.GetCommandLineArgs().Contains("--diagnostic-export-smoke-test")) await RunDiagnosticExportSmokeAsync(mainViewModel);
		if (Environment.GetCommandLineArgs().Contains("--operation-smoke-test")) await RunVerifiedOperationSmokeAsync();
		using var displayProbe = new Bastos.Native.Services.DisplayColorService();
		var vibranceProbe = displayProbe.Vibrance;
		File.WriteAllText(path, $"OK\tStartupMs={startup.ElapsedMilliseconds}\tPages={mainViewModel.Navigation.Count}\tActionCards={num}\tWizard={value}\tLogo={File.Exists(mainViewModel.LogoPath)}\tDashboard={mainViewModel.CpuMetric.Value}/{mainViewModel.MemoryMetric.Value}\tWebView2={mainViewModel.Reinstall.WebView2Version}\tHAGS={text.Replace('\t', ' ')}\tAMD-Vibrance={(vibranceProbe.HasValue ? $"{vibranceProbe.Value.Current}/{vibranceProbe.Value.Minimum}-{vibranceProbe.Value.Maximum}" : "unavailable")}");
		Close();
	}

	private void TryEnableDarkTitleBar()
	{
		try
		{
			if (SystemParameters.HighContrast) return;
			nint handle = new WindowInteropHelper(this).Handle;
			int value = 1;
			DwmSetWindowAttribute(handle, 20, ref value, 4);
			if (TryFindResource("WindowBrush") is System.Windows.Media.SolidColorBrush background)
			{
				var color = background.Color;
				int captionColor = color.R | (color.G << 8) | (color.B << 16);
				// Windows 11 COLORREF attributes; older Windows retain their native title bar.
				DwmSetWindowAttribute(handle, 35, ref captionColor, 4);
				DwmSetWindowAttribute(handle, 34, ref captionColor, 4);
				int textColor = 0x00FFFFFF;
				DwmSetWindowAttribute(handle, 36, ref textColor, 4);
			}
		}
		catch
		{
		}
	}

	[DllImport("dwmapi.dll")]
	private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int valueSize);
}

