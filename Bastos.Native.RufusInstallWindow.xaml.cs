using System;
using System.IO;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using Bastos.Native.Models;

namespace Bastos.Native;

public partial class RufusInstallWindow : Window
{
    public RufusInstallOptions Options { get; }
    private readonly bool initialKeepOnly;
    private readonly string initialPlan;
    private WindowsIsoEditionCatalog? editionCatalog;
    private WindowsIsoEdition[] selectableEditions = Array.Empty<WindowsIsoEdition>();
    private bool editionLoading = true;
    public RufusInstallWindow(RufusInstallOptions options, string isoPath, string target, string plan,
        Func<Task<WindowsIsoEditionCatalog>> loadEditions, IReadOnlyList<LanguageChoice> regions, IReadOnlyList<KeyboardChoice> keyboards)
    {
        InitializeComponent();
        Options = options;
        initialKeepOnly = options.KeepOnlyRecoveryPartition;
        initialPlan = plan;
        DataContext = options;
        RegionCombo.ItemsSource = regions;
        RegionCombo.SelectedItem = regions.FirstOrDefault(item => item.Locale == options.WindowsLocale) ?? regions.FirstOrDefault();
        KeyboardCombo.ItemsSource = keyboards;
        KeyboardCombo.SelectedItem = keyboards.FirstOrDefault(item => item.InputLocale == options.KeyboardLayout) ?? keyboards.FirstOrDefault(item => item.InputLocale == "040C:0000040C") ?? keyboards.FirstOrDefault();
        KeyboardCombo.SelectionChanged += (_, _) => UpdateKeyboardHint();
        UpdateKeyboardHint();
        IsoText.Text = string.IsNullOrWhiteSpace(isoPath) ? "Sélectionner une ISO dans Bastos" : Path.GetFileName(isoPath);
        TargetText.Text = target;
        PlanText.Text = plan;
        UpdateSaveState();
        Loaded += async (_, _) =>
        {
            try
            {
                var catalog = await loadEditions();
                if (!IsVisible) return;
                editionLoading = false;
                editionCatalog = catalog;
                selectableEditions = catalog.Images.Where(IsSupportedEdition)
                    .OrderBy(item => item.EditionId switch { "Professional" => 0, "Core" => 1, _ => 2 })
                    .ThenBy(item => item.ImageIndex).ToArray();
                EditionCombo.ItemsSource = selectableEditions;
                EditionCombo.IsEnabled = selectableEditions.Length > 0;
                if (string.Equals(options.EditionIsoSha256, catalog.IsoSha256, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(options.EditionIsoPath, catalog.IsoPath, StringComparison.OrdinalIgnoreCase))
                    EditionCombo.SelectedItem = selectableEditions.FirstOrDefault(item => item.ImageIndex == options.WindowsImageIndex &&
                        item.EditionId == options.WindowsEditionId && item.ImageName == options.WindowsImageName);
                EditionCombo.SelectedItem ??= selectableEditions.FirstOrDefault(item => item.EditionId == "Professional")
                    ?? selectableEditions.FirstOrDefault();
                EditionStatusText.Text = selectableEditions.Length == 0
                    ? "Cette ISO ne contient aucune édition Home, Education ou Pro prise en charge."
                    : EditionCombo.SelectedItem == null
                    ? "Choisis l’édition à réinstaller dans la liste ci-dessus."
                    : "Cette édition sera utilisée lors de la préparation et du redémarrage.";
                UpdateSaveState();
            }
            catch (Exception error)
            {
                if (!IsVisible) return;
                EditionStatusText.Text = "Impossible de lire les éditions de cet ISO.";
                ErrorText.Text = error.Message;
                editionLoading = false;
                UpdateSaveState();
            }
        };
    }
    public static bool IsSupportedEdition(WindowsIsoEdition edition) => edition.EditionId is "Core" or "Education" or "Professional";
    private void Edition_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ImageLanguageCombo == null || SaveButton == null) return;
        ImageLanguageCombo.ItemsSource = null;
        ImageLanguageCombo.IsEnabled = false;
        SaveButton.IsEnabled = false;
        if (EditionCombo.SelectedItem is not WindowsIsoEdition edition) { UpdateSaveState(); return; }
        var languages = edition.Languages.Distinct(StringComparer.OrdinalIgnoreCase).Select(code => new ImageLanguageChoice(code)).ToArray();
        ImageLanguageCombo.ItemsSource = languages;
        ImageLanguageCombo.IsEnabled = languages.Length > 0;
        var preferred = string.IsNullOrEmpty(Options.WindowsUILanguage) ? Options.WindowsLocale : Options.WindowsUILanguage;
        ImageLanguageCombo.SelectedItem = languages.FirstOrDefault(language => string.Equals(language.Code, preferred, StringComparison.OrdinalIgnoreCase))
            ?? languages.FirstOrDefault(language => string.Equals(language.Code, edition.DefaultUILanguage, StringComparison.OrdinalIgnoreCase))
            ?? languages.FirstOrDefault();
        ImageLanguageStatusText.Text = languages.Length == 0
            ? "Les langues de cette édition sont illisibles. L’enregistrement est bloqué."
            : "Seules les langues présentes dans l’ISO sont proposées. Formats régionaux : " + Options.WindowsLocale + ". Le clavier sélectionné est conservé.";
        EditionStatusText.Text = "Cette édition sera utilisée lors de la préparation et du redémarrage.";
        UpdateSaveState();
    }
    private void ImageLanguage_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e) { UpdateSaveState(); UpdateKeyboardHint(); }
    private void UpdateKeyboardHint()
    {
        if (KeyboardHint == null || KeyboardCombo == null) return;
        string language = (ImageLanguageCombo?.SelectedItem as ImageLanguageChoice)?.Code ?? Options.WindowsLocale;
        bool englishKeyboard = KeyboardCombo.SelectedItem is KeyboardChoice choice && choice.InputLocale.StartsWith("0409", StringComparison.OrdinalIgnoreCase);
        bool warning = language.StartsWith("fr", StringComparison.OrdinalIgnoreCase) && englishKeyboard;
        KeyboardHint.Text = warning ? "Attention : clavier QWERTY anglais sélectionné. Pour un clavier français, choisis AZERTY — Français (France). La langue des applications restera le français."
            : "Le clavier est indépendant de la langue des applications. La langue Windows choisie sera prioritaire pour les applications ; aucune langue anglaise n’est ajoutée pour un clavier QWERTY.";
        KeyboardHint.Foreground = new System.Windows.Media.SolidColorBrush(warning ? System.Windows.Media.Color.FromRgb(255,184,77) : System.Windows.Media.Color.FromRgb(182,194,210));
    }
    private void UpdateSaveState()
    {
        if (SaveButton == null || SaveHint == null) return;
        SaveButton.IsEnabled = editionCatalog != null && EditionCombo.SelectedItem is WindowsIsoEdition && ImageLanguageCombo?.SelectedItem is ImageLanguageChoice;
        string reason = SaveButton.IsEnabled ? "" : editionLoading ? "Lecture des éditions de l’ISO en cours. Attends la fin du chargement."
            : editionCatalog == null ? "Les éditions de l’ISO ne sont pas lisibles. Ferme cette fenêtre et choisis une autre ISO."
            : selectableEditions.Length == 0 ? "Cette ISO ne contient aucune édition Home, Education ou Pro. Choisis une autre ISO."
            : EditionCombo.SelectedItem is not WindowsIsoEdition ? "Choisis l’édition Windows à réinstaller pour enregistrer les options."
            : "Choisis une langue disponible dans cette édition de l’ISO.";
        SaveHint.Text = reason;
        SaveButton.ToolTip = reason.Length == 0 ? null : reason;
        System.Windows.Automation.AutomationProperties.SetHelpText(SaveButton, reason);
    }
    public sealed record ImageLanguageChoice(string Code)
    {
        public string Display { get { try { return CultureInfo.GetCultureInfo(Code).NativeName + " — " + Code; } catch (CultureNotFoundException) { return Code; } } }
        public override string ToString() => Display;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
    private void PartitionPlan_Click(object sender, RoutedEventArgs e)
    {
        bool keepOnly = ((System.Windows.Controls.CheckBox)sender).IsChecked == true;
        PlanText.Text = keepOnly == initialKeepOnly ? initialPlan : keepOnly
            ? "D: sera conservé. Toutes les autres partitions du disque Windows seront effacées ; EFI, MSR et Windows seront recréés. Le détail sera revérifié après l’enregistrement et affiché avant le redémarrage."
            : "D: et la partition EFI seront conservés. Les autres partitions du disque Windows seront effacées ; MSR et Windows seront recréés. Le détail sera revérifié après l’enregistrement et affiché avant le redémarrage.";
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (editionCatalog == null || EditionCombo.SelectedItem is not WindowsIsoEdition edition || !IsSupportedEdition(edition))
        { ErrorText.Text = "Choisis l’édition Windows à installer."; return; }
        if (ImageLanguageCombo.SelectedItem is not ImageLanguageChoice language || !edition.Languages.Contains(language.Code, StringComparer.OrdinalIgnoreCase))
        { ErrorText.Text = "Choisis une langue présente dans cette édition de l’ISO."; return; }
        Options.UserName = Options.UserName.Trim();
        Options.ComputerName = Options.ComputerName.Trim().ToUpperInvariant();
        if (Options.UserName.Length < 1 || Options.UserName.Length > 20 ||
            !Regex.IsMatch(Options.UserName, @"^[A-Za-z0-9][A-Za-z0-9 _.-]*$") || Options.UserName.EndsWith('.') ||
            Regex.IsMatch(Options.UserName, @"^(Administrator|Administrateur|Guest|Invite|Invité|DefaultAccount|defaultuser0|WDAGUtilityAccount|HelpAssistant|KRBTGT|Local|NONE|SYSTEM)$", RegexOptions.IgnoreCase))
        { ErrorText.Text = "Choisis un nom de compte de 1 à 20 lettres A–Z, chiffres, espaces, tirets ou points, sans nom réservé."; return; }
        if (Options.ComputerName.Length > 15 || !Regex.IsMatch(Options.ComputerName, @"^[A-Z0-9][A-Z0-9-]*$") ||
            !Regex.IsMatch(Options.ComputerName, "[A-Z]") || Options.ComputerName.EndsWith('-'))
        { ErrorText.Text = "Le nom du PC doit contenir 1 à 15 lettres, chiffres ou tirets, avec au moins une lettre."; return; }
        Options.WindowsImageIndex = edition.ImageIndex;
        if (RegionCombo.SelectedItem is not LanguageChoice region || KeyboardCombo.SelectedItem is not KeyboardChoice keyboard)
        { ErrorText.Text = "Choisis les formats régionaux et la disposition du clavier."; return; }
        Options.WindowsLocale = region.Locale;
        Options.KeyboardLayout = keyboard.InputLocale;
        Options.WindowsEditionId = edition.EditionId;
        Options.WindowsImageName = edition.ImageName;
        Options.WindowsUILanguage = language.Code;
        Options.EditionIsoPath = editionCatalog.IsoPath;
        Options.EditionIsoSha256 = editionCatalog.IsoSha256;
        DialogResult = true;
    }
}
