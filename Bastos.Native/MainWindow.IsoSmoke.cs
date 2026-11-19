using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class MainWindow
{
    private void RunIsoCatalogSmoke(MainViewModel main)
    {
        var vm = main.Reinstall;
        var originalFamily = vm.SelectedCatalogFamily;
        var originalVersion = vm.SelectedCatalogVersion;
        var originalLanguage = vm.SelectedCatalogLanguage;
        var originalArch = vm.SelectedCatalogArchitecture;
        var actualImages = WindowsDownloadCatalog.ReadBundled();
        main.SelectedNavigation = main.Navigation.First(item => item.PageKey == "reinstall");
        var regularFamily = vm.CatalogFamilies.First(item => item.Value == "Windows 11");
        vm.SelectedCatalogFamily = regularFamily;
        if (vm.CatalogFamilies.Any(item => item.Value == "Windows Server") ||
            vm.CatalogVersions.Any(item => item.Value.Contains("26H1", StringComparison.OrdinalIgnoreCase) ||
                item.Value.Contains("Business", StringComparison.OrdinalIgnoreCase) ||
                item.Value.Contains("LTSC", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Une famille ou version retirée reste visible dans le catalogue.");
        var regularVersion = vm.CatalogVersions.First(item => item.Value == "Windows 11 Consumer version publique actuelle");
        vm.SelectedCatalogVersion = regularVersion;
        foreach (var language in vm.CatalogLanguages.ToArray())
        {
            vm.SelectedCatalogLanguage = language;
            if (vm.SelectedCatalogIso?.Language != language.Value)
                throw new InvalidOperationException("La langue sélectionnée ne correspond pas à l’ISO proposée.");
        }
        int combinations = 0;
        foreach (var family in vm.CatalogFamilies.ToArray())
        {
            vm.SelectedCatalogFamily = family;
            foreach (var version in vm.CatalogVersions.ToArray())
            {
                vm.SelectedCatalogVersion = version;
                foreach (var language in vm.CatalogLanguages.ToArray())
                {
                    if (!actualImages.Any(item => item.Family.StartsWith(family.Value, StringComparison.Ordinal) && item.Version == version.Value && item.Language == language.Value)) continue;
                    vm.SelectedCatalogLanguage = language;
                    foreach (var arch in vm.CatalogArchitectures.ToArray())
                    {
                        vm.SelectedCatalogArchitecture = arch;
                        foreach (var iso in vm.CatalogImages.ToArray())
                        {
                            vm.SelectedCatalogIso = iso;
                            if (!iso.Family.StartsWith(family.Value, StringComparison.Ordinal) || iso.Version != version.Value || iso.Language != language.Value || iso.Architecture != arch.Value || !vm.DownloadCommand.CanExecute(null) || !vm.CatalogSelectionSummary.Contains(version.Display))
                                throw new InvalidOperationException("Catalogue ISO incohérent : " + family.Value + "/" + version.Value + "/" + language.Value + "/" + arch.Value);
                            combinations++;
                        }
                    }
                }
            }
        }
        if (combinations != actualImages.Count || vm.CatalogFamilies.Count != 2 || actualImages.Any(item=>!WindowsDownloadCatalog.IsSupportedChoice(item))) throw new InvalidOperationException("Catalogue ISO Microsoft incohérent");
        int fallbacks = 0;
        foreach (var family in vm.CatalogFamilies.ToArray())
        {
            vm.SelectedCatalogFamily = family;
            foreach (var version in vm.CatalogVersions.ToArray())
            {
                vm.SelectedCatalogFamily = family;
                vm.SelectedCatalogVersion = vm.CatalogVersions.First(item => item.Value == version.Value);
                var languages = vm.CatalogLanguages.ToArray();
                foreach (var language in languages.Where(language => !actualImages.Any(item => item.Family.StartsWith(family.Value, StringComparison.Ordinal) && item.Version == version.Value && item.Language == language.Value)))
                {
                    vm.SelectedCatalogFamily = family;
                    vm.SelectedCatalogVersion = vm.CatalogVersions.First(item => item.Value == version.Value);
                    vm.SelectedCatalogLanguage = vm.CatalogLanguages.First(item => item.Value == language.Value);
                    if (!vm.CanChooseCatalogLanguage || vm.SelectedCatalogIso?.Language != language.Value || vm.SelectedCatalogVersion?.Value.Contains(" Consumer ", StringComparison.Ordinal) != true)
                        throw new InvalidOperationException("Bascule automatique incorrecte depuis " + version.Value + " vers " + language.Value);
                    fallbacks++;
                }
            }
        }
        vm.SelectedCatalogFamily = originalFamily;
        vm.SelectedCatalogVersion = originalVersion;
        vm.SelectedCatalogLanguage = originalLanguage;
        vm.SelectedCatalogArchitecture = originalArch;
        main.SelectedNavigation = main.Navigation.First(item => item.PageKey == "reinstall");
        UpdateLayout();
        if (IsoFamilyCombo.SelectedItem == null || IsoVersionCombo.SelectedItem == null || IsoLanguageCombo.SelectedItem == null || IsoArchitectureCombo.SelectedItem == null)
            throw new InvalidOperationException("Une liste du catalogue n’affiche plus son choix après changement de famille.");
        SaveSmokeVisual(this, "BASTOS-ISO-Catalogue.png");

        var options = new RufusInstallOptions { UserName = "BastOS", ComputerName = "BASTOS-TEST", WindowsLocale = "fr-FR", KeyboardLayout = "040C:0000040C" };
        var image = new WindowsIsoEdition(1, "Windows 11 Pro", "Professional") { Languages = new[] { "fr-FR" }, DefaultUILanguage = "fr-FR" };
        var catalog = new WindowsIsoEditionCatalog("C:\\BASTOS-Test.iso", "test-sha256", new[] { image });
        var dialog = new RufusInstallWindow(options, catalog.IsoPath, "D: — BASTOS_RECOVERY", "Aperçu de test : aucune partition modifiée.", () => Task.FromResult(catalog), vm.Languages, vm.Keyboards)
        { Owner = this, ShowActivated = false, ShowInTaskbar = false, Opacity = 0 };
        Exception? failure = null;
        dialog.Loaded += (_, _) =>
        {
            try
            {
                if (dialog.KeyboardCombo.SelectedItem is not KeyboardChoice initial || initial.InputLocale != "040C:0000040C")
                    throw new InvalidOperationException("Le clavier enregistré n’est pas présélectionné.");
                dialog.KeyboardCombo.SelectedItem = vm.Keyboards.First(item => item.InputLocale == "0409:00000409");
                dialog.RegionCombo.SelectedItem = vm.Languages.First(item => item.Locale == "en-US");
                dialog.UpdateLayout();
                if (dialog.Content is DockPanel panel && panel.Children.OfType<ScrollViewer>().FirstOrDefault()?.Content is FrameworkElement content)
                    SaveSmokeVisual(content, "BASTOS-ISO-Options.png");
                dialog.SaveButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }
            catch (Exception error) { failure = error; dialog.Close(); }
        };
        bool? saved = dialog.ShowDialog();
        if (failure != null) throw failure;
        if (saved != true || options.KeyboardLayout != "0409:00000409" || options.WindowsLocale != "en-US" || options.WindowsUILanguage != "fr-FR")
            throw new InvalidOperationException("Le clavier, les formats et la langue de l’image ne sont pas enregistrés indépendamment.");
        var recoveryEditions = new[] {
            new WindowsIsoEdition(1, "Windows 11 Famille", "Core"),
            new WindowsIsoEdition(6, "Windows 11 Pro", "Professional")
        };
        var recoveryChooser = new RecoveryEditionWindow(recoveryEditions)
            { Owner = this, ShowActivated = false, ShowInTaskbar = false, Opacity = 0 };
        Exception? recoveryFailure = null;
        recoveryChooser.Loaded += (_, _) =>
        {
            try
            {
                if (recoveryChooser.SelectedEdition != null || recoveryChooser.ContinueButton.IsEnabled)
                    throw new InvalidOperationException("L’édition Recovery doit être choisie explicitement.");
                recoveryChooser.EditionCombo.SelectedItem = recoveryEditions[1];
                recoveryChooser.UpdateLayout();
                SaveSmokeVisual((FrameworkElement)recoveryChooser.Content, "BASTOS-Recovery-Edition.png");
                recoveryChooser.ContinueButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }
            catch (Exception error) { recoveryFailure = error; recoveryChooser.Close(); }
        };
        bool? recoverySelected = recoveryChooser.ShowDialog();
        if (recoveryFailure != null) throw recoveryFailure;
        if (recoverySelected != true || recoveryChooser.SelectedEdition?.ImageIndex != 6)
            throw new InvalidOperationException("Le choix d’édition Recovery n’a pas été confirmé.");
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "BASTOS-ISO-Catalogue-Test.txt"), $"OK : {combinations} ISO autorisées, 2 familles, {fallbacks} bascules de langue, clavier et formats indépendants. Aucun téléchargement ni préparation de disque lancé.");
    }

    private static void SaveSmokeVisual(FrameworkElement visual, string name)
    {
        int width = Math.Max(1, (int)Math.Ceiling(visual.ActualWidth));
        int height = Math.Max(1, (int)Math.Ceiling(visual.ActualHeight));
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(Path.Combine(Path.GetTempPath(), name));
        encoder.Save(output);
    }
}
