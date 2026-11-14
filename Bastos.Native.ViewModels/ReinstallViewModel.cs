using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed partial class ReinstallViewModel : ObservableObject
{
	private readonly ReinstallService service;

	private LanguageChoice selectedLanguage;

	private KeyboardChoice selectedKeyboard;
	private bool keyboardChoiceChangedManually;
	private string keyboardSelectionHint = string.Empty;

	private NamedChoice selectedRelease;

	private NamedChoice selectedMethod;

	private IsoChoice? selectedIso;

	private string userName = "Administrator";

	private string status = "1. Choisis une famille Windows, sa version, sa langue et son architecture.";

	private bool isBusy;
	private bool removeOneDrive = true;
	private bool disableConsumerContent = true;

	private bool isDownloadProgressVisible;

	private bool isDownloadProgressIndeterminate = true;

	private double downloadProgressPercent;

	private string downloadProgressText = "Préparation du téléchargement Microsoft…";

	private bool isBuildProgressVisible;

	private bool isBuildProgressIndeterminate = true;

	private double buildProgressPercent;

	private string buildProgressPhase = "Prérequis";

	private string buildProgressText = "Vérification du moteur de création ISO…";

	private bool isRecoveryProgressVisible;

	private bool isRecoveryProgressIndeterminate = true;

	private double recoveryProgressPercent;

	private string recoveryProgressPhase = "Préparation";

	private string recoveryProgressText = "Vérification des paramètres de récupération…";

	public ObservableCollection<LanguageChoice> Languages { get; }

	public ObservableCollection<KeyboardChoice> Keyboards { get; }
	public ObservableCollection<IsoRemovalChoice> AppxRemovalOptions { get; }

	public bool RemoveOneDrive
	{
		get => removeOneDrive;
		set => SetProperty(ref removeOneDrive, value);
	}

	public bool DisableConsumerContent
	{
		get => disableConsumerContent;
		set => SetProperty(ref disableConsumerContent, value);
	}

	public string[] GetSelectedAppxRemovalNames()
	{
		var names = AppxRemovalOptions.Where(item => item.IsSelected).Select(item => item.PackageId).ToList();
		if (RemoveOneDrive) names.Add("Microsoft.OneDriveSync");
		return names.ToArray();
	}

	public ObservableCollection<NamedChoice> Releases { get; }

	public ObservableCollection<NamedChoice> Methods { get; }

	public ObservableCollection<IsoChoice> Isos { get; }

	public AsyncRelayCommand DownloadCommand { get; }

	public AsyncRelayCommand RefreshIsoCommand { get; }

	public AsyncRelayCommand BuildCommand { get; }

	public AsyncRelayCommand PrepareUsbCommand { get; }

	public AsyncRelayCommand PrepareRecoveryCommand { get; }
	public AsyncRelayCommand CheckRecoveryCompatibilityCommand { get; }
	public AsyncRelayCommand InitializeRecoveryCommand { get; }
	public AsyncRelayCommand FinalizeRecoveryCommand { get; }

    public AsyncRelayCommand RufusOptionsCommand { get; }
    public string RufusOptionsSummary
    {
        get
        {
            if (!service.HasRufusOptions) return "Choisis l’édition Windows, le compte, le nom du PC et les partitions dans le menu intégré.";
            var options = service.ReadRufusOptions();
            if (options.WindowsImageIndex < 1 || SelectedIso == null ||
                !string.Equals(options.EditionIsoPath, SelectedIso.Path, StringComparison.OrdinalIgnoreCase))
                return "Édition Windows à choisir dans le menu intégré. Compte local et partition D: protégée.";
            return "Édition sélectionnée : " + options.WindowsImageName + " — index " + options.WindowsImageIndex + ". Langue Windows : " + options.WindowsUILanguage + ".";
        }
    }

	public AsyncRelayCommand BootRecoveryCommand { get; }

	public AsyncRelayCommand OpenLibraryCommand { get; }

	public AsyncRelayCommand DeleteIsoCommand { get; }

	public LanguageChoice SelectedLanguage
	{
		get
		{
			return selectedLanguage;
		}
		set
		{
			SetProperty(ref selectedLanguage, value, "SelectedLanguage");
		}
	}

	public KeyboardChoice SelectedKeyboard
	{
		get
		{
			return selectedKeyboard;
		}
		set
		{
			if (value == null) return;
			if (SetProperty(ref selectedKeyboard, value, "SelectedKeyboard"))
			{
				keyboardChoiceChangedManually = true;
				KeyboardSelectionHint = "Choix manuel : " + value.Display + ".";
			}
		}
	}

	public string KeyboardSelectionHint
	{
		get => keyboardSelectionHint;
		private set => SetProperty(ref keyboardSelectionHint, value, nameof(KeyboardSelectionHint));
	}

	public void RefreshDetectedKeyboard()
	{
		if (keyboardChoiceChangedManually) return;
		KeyboardSelectionHint = "Par défaut : AZERTY français. Vérifie ce choix ; le clavier de la session actuelle ne remplace pas celui de la prochaine installation.";
	}

	public NamedChoice SelectedRelease
	{
		get
		{
			return selectedRelease;
		}
		set
		{
			SetProperty(ref selectedRelease, value, "SelectedRelease");
		}
	}

	public IsoChoice? SelectedIso
	{
		get
		{
			return selectedIso;
		}
		set
		{
			if (SetProperty(ref selectedIso, value, "SelectedIso"))
			{
				RaisePropertyChanged("SelectedRecoveryIsoTitle");
				RaisePropertyChanged("SelectedRecoveryIsoPath");
				RaisePropertyChanged("SelectedRecoveryIsoKind");
				RaisePropertyChanged("SelectedRecoveryIsoMetadata");
                RaisePropertyChanged(nameof(RufusOptionsSummary));
				RefreshActionAvailability();
			}
		}
	}

	public string SelectedRecoveryIsoTitle
	{
		get
		{
			if ((object)SelectedIso != null)
			{
				return "ISO qui sera copiée : " + Path.GetFileName(SelectedIso.Path);
			}
			return "Aucune ISO sélectionnée";
		}
	}

	public string SelectedRecoveryIsoPath => SelectedIso?.Path ?? "Sélectionnez d’abord une ISO dans l’étape 2.";

	public string SelectedRecoveryIsoMetadata => SelectedIso?.Metadata ?? "Date, heure et taille indisponibles.";

	public string SelectedRecoveryIsoKind
	{
		get
		{
			if ((object)SelectedIso == null)
			{
				return "BASTOS_RECOVERY ne sera pas modifiée.";
			}
			if (!SelectedIso.IsBastosCustom)
			{
				return "ISO Windows Microsoft d’origine — sans la personnalisation ISO facultative de BASTOS.";
			}
			return "ISO BASTOS personnalisée — le profil autonome, les scripts ordonnés et l’installation de l’application seront activés au premier Bureau.";
		}
	}

	public string UserName
	{
		get
		{
			return userName;
		}
		set
		{
			SetProperty(ref userName, value, "UserName");
		}
	}

	public string Status
	{
		get
		{
			return status;
		}
		private set
		{
			SetProperty(ref status, value, "Status");
		}
	}

	public bool IsBusy
	{
		get
		{
			return isBusy;
		}
		private set
		{
			if (SetProperty(ref isBusy, value, "IsBusy")) RefreshActionAvailability();
		}
	}

	public bool IsDownloadProgressVisible
	{
		get
		{
			return isDownloadProgressVisible;
		}
		private set
		{
			SetProperty(ref isDownloadProgressVisible, value, "IsDownloadProgressVisible");
		}
	}

	public bool IsDownloadProgressIndeterminate
	{
		get
		{
			return isDownloadProgressIndeterminate;
		}
		private set
		{
			SetProperty(ref isDownloadProgressIndeterminate, value, "IsDownloadProgressIndeterminate");
		}
	}

	public double DownloadProgressPercent
	{
		get
		{
			return downloadProgressPercent;
		}
		private set
		{
			SetProperty(ref downloadProgressPercent, value, "DownloadProgressPercent");
		}
	}

	public string DownloadProgressText
	{
		get
		{
			return downloadProgressText;
		}
		private set
		{
			SetProperty(ref downloadProgressText, value, "DownloadProgressText");
		}
	}

	public bool IsBuildProgressVisible
	{
		get
		{
			return isBuildProgressVisible;
		}
		private set
		{
			SetProperty(ref isBuildProgressVisible, value, "IsBuildProgressVisible");
		}
	}

	public bool IsBuildProgressIndeterminate
	{
		get
		{
			return isBuildProgressIndeterminate;
		}
		private set
		{
			SetProperty(ref isBuildProgressIndeterminate, value, "IsBuildProgressIndeterminate");
		}
	}

	public double BuildProgressPercent
	{
		get
		{
			return buildProgressPercent;
		}
		private set
		{
			SetProperty(ref buildProgressPercent, value, "BuildProgressPercent");
		}
	}

	public string BuildProgressPhase
	{
		get
		{
			return buildProgressPhase;
		}
		private set
		{
			SetProperty(ref buildProgressPhase, value, "BuildProgressPhase");
		}
	}

	public string BuildProgressText
	{
		get
		{
			return buildProgressText;
		}
		private set
		{
			SetProperty(ref buildProgressText, value, "BuildProgressText");
		}
	}

	public bool IsRecoveryProgressVisible
	{
		get
		{
			return isRecoveryProgressVisible;
		}
		private set
		{
			SetProperty(ref isRecoveryProgressVisible, value, "IsRecoveryProgressVisible");
		}
	}

	public bool IsRecoveryProgressIndeterminate
	{
		get
		{
			return isRecoveryProgressIndeterminate;
		}
		private set
		{
			SetProperty(ref isRecoveryProgressIndeterminate, value, "IsRecoveryProgressIndeterminate");
		}
	}

	public double RecoveryProgressPercent
	{
		get
		{
			return recoveryProgressPercent;
		}
		private set
		{
			SetProperty(ref recoveryProgressPercent, value, "RecoveryProgressPercent");
		}
	}

	public string RecoveryProgressPhase
	{
		get
		{
			return recoveryProgressPhase;
		}
		private set
		{
			SetProperty(ref recoveryProgressPhase, value, "RecoveryProgressPhase");
		}
	}

	public string RecoveryProgressText
	{
		get
		{
			return recoveryProgressText;
		}
		private set
		{
			SetProperty(ref recoveryProgressText, value, "RecoveryProgressText");
		}
	}

	public NamedChoice SelectedMethod
	{
		get
		{
			return selectedMethod;
		}
		set
		{
			if (SetProperty(ref selectedMethod, value, "SelectedMethod"))
			{
				RaisePropertyChanged("IsUsbMethod");
				RaisePropertyChanged("IsRecoveryMethod");
			}
		}
	}

	public bool IsUsbMethod => SelectedMethod.Value == "Usb";

	public bool IsRecoveryMethod => SelectedMethod.Value == "Recovery";

	public string WebView2Version => service.ReadWebView2Version() ?? "absent";

	public ReinstallViewModel(ReinstallService service)
	{
		this.service = service;
		Languages = new ObservableCollection<LanguageChoice>(CreateLanguages());
		Keyboards = new ObservableCollection<KeyboardChoice>(CreateKeyboards());
		AppxRemovalOptions = new ObservableCollection<IsoRemovalChoice>(
			service.ReadDefaultAppxRemovals()
				.Where(name => !name.Equals("Microsoft.OneDriveSync", StringComparison.OrdinalIgnoreCase))
				.Select(name => new IsoRemovalChoice(name, AppxRemovalDisplay(name))));
		Releases = new ObservableCollection<NamedChoice>
		{
			new NamedChoice("Windows 11 — version publique actuelle", "Retail25H2"),
			new NamedChoice("Windows 11 — Windows Insider (préversion)", "Insider26H2")
		};
		Methods = new ObservableCollection<NamedChoice>
		{
			new NamedChoice("Clé USB bootable avec Rufus", "Usb"),
			new NamedChoice("Réinstallation interne sans clé USB", "Recovery")
		};
		Isos = new ObservableCollection<IsoChoice>();
		selectedLanguage = Languages.First((LanguageChoice item) => item.Locale == "fr-FR");
		selectedKeyboard = Keyboards.First((KeyboardChoice item) => item.InputLocale == "040C:0000040C");
		RefreshDetectedKeyboard();
		if (service.HasRufusOptions)
		{
			var saved = service.ReadRufusOptions();
			selectedLanguage = Languages.FirstOrDefault(item => item.Locale == saved.WindowsLocale) ?? selectedLanguage;
			var savedKeyboard = Keyboards.FirstOrDefault(item => item.InputLocale == saved.KeyboardLayout);
			if (savedKeyboard != null)
			{
				selectedKeyboard = savedKeyboard;
				keyboardChoiceChangedManually = true;
				KeyboardSelectionHint = "Disposition enregistrée : " + savedKeyboard.Display + ".";
			}
		}
		selectedRelease = Releases[0];
		selectedMethod = Methods[1];
		DownloadCommand = new AsyncRelayCommand(DownloadCatalogIso, () => DownloadReason.Length == 0, () => DownloadReason);
		RefreshIsoCommand = new AsyncRelayCommand(delegate
		{
			RefreshIsos();
			return Task.CompletedTask;
		}, () => CanChooseLocalIso, () => WaitingReason);
		BuildCommand = new AsyncRelayCommand(BuildIso, () => IsoActionReason.Length == 0, () => IsoActionReason);
		PrepareUsbCommand = new AsyncRelayCommand(PrepareUsb, () => IsoActionReason.Length == 0, () => IsoActionReason);
		PrepareRecoveryCommand = new AsyncRelayCommand(PrepareRecovery, () => IsoActionReason.Length == 0, () => IsoActionReason);
		CheckRecoveryCompatibilityCommand = new AsyncRelayCommand(CheckRecoveryCompatibility,
			() => !IsBusy && !IsCatalogRefreshing, () => WaitingReason);
		InitializeRecoveryCommand = new AsyncRelayCommand(InitializeRecovery, () => WaitingReason.Length == 0, () => WaitingReason);
		FinalizeRecoveryCommand = new AsyncRelayCommand(FinalizeRecovery, () => WaitingReason.Length == 0, () => WaitingReason);
        RufusOptionsCommand = new AsyncRelayCommand(async () =>
        {
            await Execute(async () =>
            {
                bool saved = await ConfigureRufusOptions();
                return (saved, Status);
            });
        }, () => IsoActionReason.Length == 0, () => IsoActionReason);
		BootRecoveryCommand = new AsyncRelayCommand(BootRecovery, () => IsoActionReason.Length == 0, () => IsoActionReason);
		OpenLibraryCommand = new AsyncRelayCommand(delegate
		{
			service.OpenIsoLibrary(SelectedIso?.Path);
			return Task.CompletedTask;
		});
		DeleteIsoCommand = new AsyncRelayCommand(DeleteSelectedIso, () => IsoActionReason.Length == 0, () => IsoActionReason);
		InitializeDownloadCatalog();
		RefreshIsos();
	}

	private async Task DownloadWindows()
	{
		await Execute(async delegate
		{
			IsDownloadProgressVisible = true;
			IsDownloadProgressIndeterminate = true;
			DownloadProgressPercent = 0.0;
			DownloadProgressText = "Préparation du lien de téléchargement officiel Microsoft…";
			if (service.ReadWebView2Version() == null)
			{
				Status = "WebView2 Runtime est absent — téléchargement et installation depuis Microsoft…";
				var (flag, text) = await service.EnsureWebView2RuntimeAsync();
				if (!flag)
				{
					return (Success: false, Message: text);
				}
				Status = text + " Ouverture du téléchargement Windows…";
			}
			Status = ((SelectedRelease.Value == "Insider26H2") ? "Connexion Microsoft Insider : connecte-toi, puis choisis manuellement l’édition Windows 11 souhaitée." : "Microsoft prépare puis télécharge l’ISO Windows 11 actuellement proposée sur son site…");
			Progress<IsoDownloadProgress> progress = new Progress<IsoDownloadProgress>(UpdateDownloadProgress);
			(bool, string, string) tuple2 = await service.DownloadWindowsAsync(SelectedLanguage, SelectedRelease, progress);
			RefreshIsos(tuple2.Item3);
            if (tuple2.Item1 && tuple2.Item3 != null && File.Exists(tuple2.Item3) && SelectedIso != null)
            {
                return (true, "ISO téléchargée. Configure le compte, le PC, l’édition et les partitions, puis valide les options et prépare D:.");
            }
			return (Success: tuple2.Item1, Message: tuple2.Item2);
		});
	}

	private void UpdateDownloadProgress(IsoDownloadProgress progress)
	{
		IsDownloadProgressVisible = true;
		IsDownloadProgressIndeterminate = progress.TotalBytes <= 0 && progress.Status != "Completed";
		DownloadProgressPercent = ((progress.Status == "Completed") ? 100.0 : progress.Percent);
		if (progress.Status == "Downloading" || progress.Status == "Completed")
		{
			string value = FormatBytes(progress.Bytes);
			string value2 = ((progress.TotalBytes > 0) ? FormatBytes(progress.TotalBytes) : "taille inconnue");
			string value3 = ((progress.BytesPerSecond > 0.0) ? (" — " + FormatBytes((long)progress.BytesPerSecond) + "/s") : string.Empty);
			DownloadProgressText = $"{DownloadProgressPercent:N1} % — {value} sur {value2}{value3}";
			Status = ((progress.Status == "Completed") ? ("Téléchargement terminé — " + progress.FilePath) : $"Téléchargement de l’ISO en cours — {DownloadProgressPercent:N1} %");
		}
		else
		{
			string text;
			switch (progress.Status)
			{
			case "LinkReady":
				text = "Lien Microsoft prêt. Démarrage du transfert…";
				break;
			case "DownloadStarted":
				text = "Transfert démarré. Lecture de la taille de l’ISO…";
				break;
			case "SigningIn":
			case "AwaitingSignIn":
				text = "Connecte-toi dans la fenêtre Microsoft Insider ouverte.";
				break;
			case "AwaitingEditionSelection":
				text = "Choisis l’édition Windows 11 dans la fenêtre Microsoft, puis clique sur Confirmer.";
				break;
			case "Error":
			case "Interrupted":
			case "Timeout":
				text = "Le téléchargement a été interrompu.";
				break;
			default:
				text = "Microsoft prépare le lien temporaire de l’ISO…";
				break;
			}
			DownloadProgressText = text;
		}
	}

	private static string FormatBytes(long bytes)
	{
		if (bytes < 1073741824)
		{
			if (bytes < 1048576)
			{
				if (bytes >= 1024)
				{
					return $"{(double)bytes / 1024.0:N0} Ko";
				}
				return $"{bytes:N0} octets";
			}
			return $"{(double)bytes / 1024.0 / 1024.0:N1} Mo";
		}
		return $"{(double)bytes / 1024.0 / 1024.0 / 1024.0:N2} Go";
	}

	private async Task BuildIso()
	{
		if (IsBusy) return;
		if ((object)SelectedIso == null)
		{
			Status = "Sélectionne d’abord une ISO Windows téléchargée.";
			return;
		}
		if (AppxRemovalOptions.Count == 0)
		{
			Status = "Liste des applications BASTOS introuvable : création de l’ISO interrompue.";
			return;
		}
		var dialog = new Bastos.Native.IsoCustomizationWindow(this) { Owner = Application.Current.MainWindow };
		if (dialog.ShowDialog() != true) return;
		string[] selectedAppx = GetSelectedAppxRemovalNames();
		bool selectedOneDrive = RemoveOneDrive;
		bool selectedConsumerContent = DisableConsumerContent;
		await Execute(async delegate
		{
			IsBuildProgressVisible = true;
			IsBuildProgressIndeterminate = true;
			BuildProgressPercent = 0.0;
			BuildProgressPhase = "Prérequis — Windows ADK";
			BuildProgressText = "Vérification d’Oscdimg. S’il manque, BASTOS téléchargera et installera automatiquement les seuls Outils de déploiement Microsoft.";
			Status = "Préparation de la construction ISO. Une demande administrateur peut apparaître.";
			Progress<IsoBuildProgress> buildProgress = new Progress<IsoBuildProgress>(UpdateBuildProgress);
			(bool, string, string) tuple = await service.BuildBastosIsoAsync(SelectedIso, SelectedLanguage, SelectedKeyboard, UserName, selectedAppx, selectedOneDrive, selectedConsumerContent, buildProgress, activeCancellation);
			RefreshIsos(tuple.Item3);
			return (Success: tuple.Item1, Message: tuple.Item2);
		});
	}

	private void UpdateBuildProgress(IsoBuildProgress progress)
	{
		IsBuildProgressVisible = true;
		IsBuildProgressIndeterminate = progress.IsIndeterminate;
		BuildProgressPercent = progress.Percent;
		string text = ((progress.Step > 0) ? $" — étape {progress.Step}/{Math.Max(1, progress.TotalSteps)}" : string.Empty);
		BuildProgressPhase = progress.Phase + text;
		BuildProgressText = progress.Message;
		Status = ((progress.Percent >= 100.0) ? ("ISO BASTOS terminée — " + progress.Message) : $"Construction ISO — {progress.Percent:N0} % — {progress.Phase}{text}");
	}

	private async Task PrepareUsb()
	{
		if ((object)SelectedIso == null)
		{
			Status = "Sélectionne l’ISO à écrire sur la clé USB.";
			return;
		}
		await Execute(async delegate
		{
			Status = "Vérification de Rufus et présélection de l’ISO…";
			return ((bool Success, string Message))(await service.PrepareUsbAsync(SelectedIso));
		});
	}

	private Task DeleteSelectedIso()
	{
		IsoChoice isoChoice = SelectedIso;
		if ((object)isoChoice == null)
		{
			return Task.CompletedTask;
		}
		if (MessageBox.Show($"Supprimer définitivement cette ISO ?\n\n{isoChoice.FileName}\n{isoChoice.Metadata}\n{isoChoice.Path}\n\n" + "Le contenu déjà copié dans BASTOS_RECOVERY ne sera pas effacé, mais cette ISO ne pourra plus être utilisée pour une nouvelle synchronisation ou une clé USB.", "Supprimer l’ISO sélectionnée", MessageBoxButton.YesNo, MessageBoxImage.Exclamation, MessageBoxResult.No) != MessageBoxResult.Yes)
		{
			return Task.CompletedTask;
		}
		var (flag, text) = service.DeleteIso(isoChoice);
		if (flag)
		{
			SelectedIso = null;
			RefreshIsos();
			Status = "Terminé — " + text;
		}
		else
		{
			Status = "Échec — " + text;
		}
		return Task.CompletedTask;
	}

    private async Task<bool> ConfigureRufusOptions()
    {
        var options = service.ReadRufusOptions();
        options.WindowsLocale = SelectedLanguage.Locale;
        options.KeyboardLayout = SelectedKeyboard.InputLocale;
        options.RecoveryPartitionGuid = "";
        options.WindowsDiskIdentity = "";
        options.DiskSafetySnapshot = "";
        var preview = await service.PreviewRecoveryAsync(options);
        if (!preview.Success) { Status = "Options refusées — " + preview.Message; return false; }
        options.RecoveryPartitionGuid = preview.PartitionGuid;
        options.WindowsDiskIdentity = preview.DiskIdentity;
        options.DiskSafetySnapshot = preview.DiskSnapshot;
        var iso = SelectedIso;
        if (iso == null) { Status = "Sélectionne d’abord l’ISO pour choisir son édition Windows."; return false; }
        var window = new Bastos.Native.RufusInstallWindow(options, iso.Path, preview.Target, preview.Message,
            () => service.ReadIsoEditionsAsync(iso), Languages, Keyboards)
        { Owner = Application.Current.MainWindow };
        if (window.ShowDialog() != true) { Status = "Options annulées."; return false; }
        SelectedKeyboard = Keyboards.First(item => item.InputLocale == options.KeyboardLayout);
        SelectedLanguage = Languages.First(item => item.Locale == options.WindowsLocale);
        preview = await service.PreviewRecoveryAsync(options);
        if (!preview.Success) { Status = "Options refusées — " + preview.Message; return false; }
        service.SaveRufusOptions(options);
        RaisePropertyChanged(nameof(RufusOptionsSummary));
        Status = "Options enregistrées : " + options.WindowsImageName + ". D: est identifié et le plan a été vérifié.";
        return true;
    }

    private async Task PrepareRecovery()
    {
        if (SelectedIso == null) { Status = "Sélectionne l’ISO à copier dans BASTOS_RECOVERY."; return; }
        IsoChoice iso = SelectedIso;
        await Execute(async () =>
        {
            var validation = ValidateSavedOptions();
            if (!validation.Success) return validation;
            var options = service.ReadRufusOptions();
            var decision = await ReviewRecovery(iso, options, false);
            if (!decision.Success || !decision.Confirmed) return (decision.Success, decision.Message);
            IsRecoveryProgressVisible = true;
            IsRecoveryProgressIndeterminate = true;
            RecoveryProgressPercent = 0;
            RecoveryProgressPhase = "Préparation de D:";
            RecoveryProgressText = "ISO sélectionnée : " + Path.GetFileName(iso.Path);
            return await service.ProvisionRecoveryAsync(iso, SelectedLanguage, SelectedKeyboard, UserName,
                new Progress<RecoveryBuildProgress>(UpdateRecoveryProgress), approvedOptions: options, cancellation: activeCancellation);
        });
    }

	private async Task InitializeRecovery()
	{
		if (IsBusy || IsCatalogRefreshing) return;
		IsBusy = true;
		try
		{
			Status = "Vérification du disque avant la création de D:…";
			var compatibility = await service.CheckAutonomousCompatibilityAsync();
			if (!compatibility.Success) { Status = "Création de D: refusée — " + compatibility.Message; return; }
			if (MessageBox.Show(
				compatibility.Message + "\n\nBastos va uniquement créer la partition D: BASTOS_RECOVERY. Si 40 Go ne sont pas déjà non alloués, C: sera réduit de 40 Go si Windows le permet. L’édition Windows et les options seront choisies ensuite. Aucun redémarrage ne sera lancé. Sauvegarde tes fichiers avant de continuer.",
				"Créer D: BASTOS_RECOVERY", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
			{
				Status = "Création annulée. Aucune modification du disque demandée.";
				return;
			}
			IsRecoveryProgressVisible = true;
			IsRecoveryProgressIndeterminate = true;
			RecoveryProgressPercent = 0;
			RecoveryProgressPhase = "Création de D: BASTOS_RECOVERY";
			RecoveryProgressText = "Vérification puis création de la partition, sans copie de l’ISO.";
			var result = await service.PrepareRecoveryPartitionAsync();
			IsRecoveryProgressIndeterminate = false;
			RecoveryProgressPercent = result.Success ? 100 : 0;
			if (result.Success) { RaisePropertyChanged(nameof(RufusOptionsSummary)); RefreshActionAvailability(); }
			Status = (result.Success ? "Terminé — " : "Échec — ") + result.Message;
		}
		catch (Exception ex) { Status = "Échec — " + ex.Message; }
		finally { IsBusy = false; }
	}

	private Task CheckRecoveryCompatibility()
	{
		Status = "Vérification de compatibilité en cours — lecture du disque Windows, des partitions et de l’espace disponible…";
		return Execute(service.CheckAutonomousCompatibilityAsync);
	}

	private async Task FinalizeRecovery()
	{
		if (IsBusy || IsCatalogRefreshing) return;
		IsBusy = true;
		try
		{
			Status = "Vérification de Bastos sur C:, de WinRE et de D:…";
			var preview = await service.FinalizeTemporaryRecoveryAsync(false);
			if (!preview.Success) { Status = "Finalisation refusée — " + preview.Message; return; }
			if (MessageBox.Show("La réinstallation est vérifiée et Bastos fonctionne depuis C:. Bastos va supprimer D: BASTOS_RECOVERY, agrandir C: et recréer une petite partition WinRE. Toutes les données encore présentes sur D: seront effacées. Une interruption pendant le partitionnement peut demander une réparation manuelle. Sauvegarde tes fichiers avant de continuer.\n\nContinuer ?", "Récupérer l’espace de D:", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
			{
				Status = "Finalisation annulée. D: est conservé.";
				return;
			}
			Status = "Réintégration de D: dans C: et vérification de WinRE…";
			var result = await service.FinalizeTemporaryRecoveryAsync(true);
			Status = (result.Success ? "Terminé — " : "À vérifier — ") + result.Message;
		}
		catch (Exception ex) { Status = "Finalisation interrompue — " + ex.Message; }
		finally { IsBusy = false; }
	}

    private async Task<(bool Success, bool Confirmed, string Message)> ReviewRecovery(IsoChoice iso, RufusInstallOptions options, bool reinstall)
    {
        Status = "Bilan en cours — relecture de l’ISO, de son édition et du plan des disques…";
        var review = await service.ReviewRecoveryAsync(iso, options, reinstall, activeCancellation);
        string keyboardLabel = Keyboards.FirstOrDefault(k => k.InputLocale == options.KeyboardLayout)?.Display ?? options.KeyboardLayout;
        string regionLabel = Languages.FirstOrDefault(l => l.Locale == options.WindowsLocale)?.Display ?? options.WindowsLocale;
        review = review with { Profile = $"Compte : {options.UserName} (sans mot de passe)\nPC : {options.ComputerName}\nClavier : {keyboardLabel}\nFormats régionaux : {regionLabel}\n\n{RecoveryPreflightBuilder.FinalizationNotice}" };
        var window = new Bastos.Native.RecoveryPreflightWindow(review) { Owner = Application.Current.MainWindow };
        bool confirmed = window.ShowDialog() == true && review.CanContinue;
        return (review.CanContinue, confirmed, !review.CanContinue
            ? "Lancement bloqué — " + string.Join(" ", review.Blockers)
            : confirmed ? "Bilan confirmé." : "Lancement annulé. Aucune préparation ni aucun redémarrage demandé.");
    }

    private (bool Success, string Message) ValidateSavedOptions()
    {
        if (!service.HasRufusOptions)
            return (false, "Configure d’abord le module Compte, nom du PC, nettoyage et partitions, puis enregistre les options.");
        var options = service.ReadRufusOptions();
        if (string.IsNullOrWhiteSpace(options.DiskSafetySnapshot))
            return (false, "Le plan des disques doit être validé avec cette version de Bastos. Ouvre Compte, nom du PC, nettoyage et partitions, vérifie le plan puis enregistre les options.");
        if (SelectedIso == null || options.WindowsImageIndex < 1 || string.IsNullOrWhiteSpace(options.WindowsEditionId) ||
            string.IsNullOrWhiteSpace(options.WindowsUILanguage) ||
            string.IsNullOrWhiteSpace(options.EditionIsoSha256) ||
            !string.Equals(options.EditionIsoPath, SelectedIso.Path, StringComparison.OrdinalIgnoreCase))
            return (false, "L’ISO, son édition ou sa langue n’est pas configuré. Ouvre le module Compte, nom du PC, nettoyage et partitions, puis enregistre les options.");
        SelectedLanguage = Languages.FirstOrDefault(item => item.Locale == options.WindowsLocale) ?? SelectedLanguage;
        SelectedKeyboard = Keyboards.FirstOrDefault(item => item.InputLocale == options.KeyboardLayout) ?? SelectedKeyboard;
        return (true, "Options enregistrées : " + options.WindowsImageName);
    }

	private void UpdateRecoveryProgress(RecoveryBuildProgress progress)
	{
		IsRecoveryProgressVisible = true;
		IsRecoveryProgressIndeterminate = progress.IsIndeterminate;
		RecoveryProgressPercent = progress.Percent;
		string text = ((progress.Step > 0) ? $" — étape {progress.Step}/{Math.Max(1, progress.TotalSteps)}" : string.Empty);
		RecoveryProgressPhase = progress.Phase + text;
		RecoveryProgressText = progress.Message;
		Status = ((progress.Phase == "Échec") ? ("Échec — " + progress.Message) : ((progress.Percent >= 100.0) ? ("Terminé — " + progress.Message) : $"BASTOS_RECOVERY — {progress.Percent:N0} % — {progress.Phase}{text}"));
	}

    private async Task BootRecovery()
    {
        if (SelectedIso == null) { Status = "Sélectionne l'ISO exacte à synchroniser avant le redémarrage."; return; }
        IsoChoice iso = SelectedIso;
        await Execute(async () =>
        {
            var validation = ValidateSavedOptions();
            if (!validation.Success) return validation;
            var options = service.ReadRufusOptions();
            var decision = await ReviewRecovery(iso, options, true);
            if (!decision.Success || !decision.Confirmed) return (decision.Success, decision.Message);
            IsRecoveryProgressVisible = true;
            IsRecoveryProgressIndeterminate = true;
            RecoveryProgressPercent = 0;
            RecoveryProgressPhase = "Validation finale";
            RecoveryProgressText = "Préparation de " + Path.GetFileName(iso.Path) + " sur D:…";
            var prepared = await service.ProvisionRecoveryAsync(iso, SelectedLanguage, SelectedKeyboard, UserName,
                new Progress<RecoveryBuildProgress>(UpdateRecoveryProgress), approvedOptions: options, cancellation: activeCancellation);
            if (!prepared.Success) return prepared;
            if (activeCancellation?.Requested == true)
                return (true, prepared.Message + " La préparation s’est terminée après le dernier point d’arrêt. Le redémarrage n’a pas été demandé car tu as demandé l’annulation.");
            activeCancellation?.Lock("Programmation du démarrage Recovery : laisse la vérification et la demande de redémarrage se terminer.");
            return await service.BootRecoveryAsync(iso, options, recoveryProgress: new Progress<RecoveryBuildProgress>(UpdateRecoveryProgress));
        });
    }

	private async Task Execute(Func<Task<(bool Success, string Message)>> operation)
	{
		if (IsBusy || IsCatalogRefreshing)
		{
			return;
		}
		IsBusy = true;
        var cancellation = BeginCancellation();
		try
		{
			(bool, string) obj = await operation();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			Status = (item ? "Terminé — " : cancellation.Requested ? "Résultat — " : "Échec — ") + item2;
		}
		catch (OperationCanceledException) { Status = "Annulation confirmée avant le lancement de l’étape suivante. Le contrôle en cours a terminé ; aucun arrêt forcé demandé."; }
		catch (Exception ex)
		{
			Status = "Échec — " + ex.Message;
		}
		finally
		{
            EndCancellation(cancellation);
			IsBusy = false;
		}
	}

	private void RefreshIsos(string? preferred = null)
	{
		string previous = preferred ?? SelectedIso?.Path;
		Isos.Clear();
		foreach (IsoChoice item in service.FindIsos())
		{
			Isos.Add(item);
		}
		SelectedIso = Isos.FirstOrDefault((IsoChoice item) => string.Equals(item.Path, previous, StringComparison.OrdinalIgnoreCase)) ?? Isos.FirstOrDefault();
		if (Isos.Count == 0)
		{
			Status = "Aucune ISO locale détectée. Choisis une ISO dans le catalogue ci-dessus pour la télécharger.";
		}
	}

	private static IEnumerable<LanguageChoice> CreateLanguages()
	{
		return new LanguageChoice[38]
		{
			new LanguageChoice("Allemand", "German", "de-DE"),
			new LanguageChoice("Anglais (États-Unis)", "English", "en-US"),
			new LanguageChoice("Anglais international", "English International", "en-GB"),
			new LanguageChoice("Arabe", "Arabic", "ar-SA"),
			new LanguageChoice("Bulgare", "Bulgarian", "bg-BG"),
			new LanguageChoice("Chinois simplifié", "Chinese (Simplified)", "zh-CN"),
			new LanguageChoice("Chinois traditionnel", "Chinese (Traditional)", "zh-TW"),
			new LanguageChoice("Coréen", "Korean", "ko-KR"),
			new LanguageChoice("Croate", "Croatian", "hr-HR"),
			new LanguageChoice("Danois", "Danish", "da-DK"),
			new LanguageChoice("Espagnol", "Spanish", "es-ES"),
			new LanguageChoice("Espagnol (Mexique)", "Spanish (Mexico)", "es-MX"),
			new LanguageChoice("Estonien", "Estonian", "et-EE"),
			new LanguageChoice("Finnois", "Finnish", "fi-FI"),
			new LanguageChoice("Français", "French", "fr-FR"),
			new LanguageChoice("Français canadien", "French Canadian", "fr-CA"),
			new LanguageChoice("Grec", "Greek", "el-GR"),
			new LanguageChoice("Hébreu", "Hebrew", "he-IL"),
			new LanguageChoice("Hongrois", "Hungarian", "hu-HU"),
			new LanguageChoice("Italien", "Italian", "it-IT"),
			new LanguageChoice("Japonais", "Japanese", "ja-JP"),
			new LanguageChoice("Letton", "Latvian", "lv-LV"),
			new LanguageChoice("Lituanien", "Lithuanian", "lt-LT"),
			new LanguageChoice("Néerlandais", "Dutch", "nl-NL"),
			new LanguageChoice("Norvégien", "Norwegian", "nb-NO"),
			new LanguageChoice("Polonais", "Polish", "pl-PL"),
			new LanguageChoice("Portugais", "Portuguese", "pt-PT"),
			new LanguageChoice("Portugais (Brésil)", "Brazilian Portuguese", "pt-BR"),
			new LanguageChoice("Roumain", "Romanian", "ro-RO"),
			new LanguageChoice("Russe", "Russian", "ru-RU"),
			new LanguageChoice("Serbe (latin)", "Serbian Latin", "sr-Latn-RS"),
			new LanguageChoice("Slovaque", "Slovak", "sk-SK"),
			new LanguageChoice("Slovène", "Slovenian", "sl-SI"),
			new LanguageChoice("Suédois", "Swedish", "sv-SE"),
			new LanguageChoice("Tchèque", "Czech", "cs-CZ"),
			new LanguageChoice("Thaï", "Thai", "th-TH"),
			new LanguageChoice("Turc", "Turkish", "tr-TR"),
			new LanguageChoice("Ukrainien", "Ukrainian", "uk-UA")
		};
	}

	private static string AppxRemovalDisplay(string packageId) => packageId switch
	{
		"Clipchamp.Clipchamp" => "Clipchamp",
		"7EE7776C.LinkedInforWindows" => "LinkedIn",
		"Microsoft.549981C3F5F10" => "Cortana",
		"Microsoft.BingNews" => "Actualités Bing",
		"Microsoft.BingWeather" => "Météo Bing",
		"Microsoft.BingSearch" => "Recherche Bing",
		"Microsoft.Copilot" => "Microsoft Copilot",
		"Microsoft.GetHelp" => "Obtenir de l’aide",
		"Microsoft.Getstarted" => "Prise en main de Windows",
		"Microsoft.MicrosoftOfficeHub" => "Microsoft 365 Hub",
		"Microsoft.MicrosoftSolitaireCollection" => "Microsoft Solitaire",
		"Microsoft.OutlookForWindows" => "Outlook pour Windows",
		"Microsoft.People" => "Contacts",
		"Microsoft.PowerAutomateDesktop" => "Power Automate Desktop",
		"Microsoft.Todos" => "Microsoft To Do",
		"Microsoft.WindowsAlarms" => "Horloge et alarmes",
		"Microsoft.WindowsFeedbackHub" => "Hub de commentaires",
		"Microsoft.WindowsMaps" => "Cartes Windows",
		"Microsoft.WindowsSoundRecorder" => "Enregistreur audio",
		"Microsoft.Windows.DevHome" => "Dev Home",
		"MicrosoftWindows.Client.WebExperience" => "Widgets Windows",
		"5319275A.WhatsAppDesktop" => "WhatsApp",
		"MicrosoftCorporationII.MicrosoftFamily" => "Microsoft Family",
		"MicrosoftCorporationII.QuickAssist" => "Assistance rapide",
		"MicrosoftTeams" or "MSTeams" => "Microsoft Teams",
		_ => packageId
	};

	private static IEnumerable<KeyboardChoice> CreateKeyboards()
	{
		return new KeyboardChoice[9]
		{
			new KeyboardChoice("QWERTY — Anglais (États-Unis)", "0409:00000409"),
			new KeyboardChoice("QWERTY international — Anglais (États-Unis)", "0409:00020409"),
			new KeyboardChoice("QWERTY — Anglais (Royaume-Uni)", "0809:00000809"),
			new KeyboardChoice("AZERTY — Français (France)", "040C:0000040C"),
			new KeyboardChoice("AZERTY — Français (Belgique)", "080C:0000080C"),
			new KeyboardChoice("QWERTY canadien — Français (Canada)", "0C0C:00001009"),
			new KeyboardChoice("QWERTZ — Français (Suisse)", "100C:0000100C"),
			new KeyboardChoice("QWERTZ — Allemand (Allemagne)", "0407:00000407"),
			new KeyboardChoice("QWERTY — Espagnol (Espagne)", "040A:0000040A")
		};
	}
}
