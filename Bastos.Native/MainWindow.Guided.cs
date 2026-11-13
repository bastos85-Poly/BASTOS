using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class MainWindow
{
    // Presentation only. Navigation never invokes a preparation or launch command.
    private void ReinstallNext_Click(object sender, RoutedEventArgs e) =>
        ReinstallSteps.SelectedIndex = Math.Min(2, ReinstallSteps.SelectedIndex + 1);

    private void ReinstallBack_Click(object sender, RoutedEventArgs e) =>
        ReinstallSteps.SelectedIndex = Math.Max(0, ReinstallSteps.SelectedIndex - 1);

    private void RunGuidedLayoutSmoke(MainViewModel model)
    {
        var original = model.SelectedNavigation;
        model.SelectedNavigation = model.Navigation.First(n => n.PageKey == "reinstall");
        for (int i = 0; i < 3; i++)
        {
            ReinstallSteps.SelectedIndex = i;
            UpdateLayout();
            if (ReinstallSteps.SelectedIndex != i || ReinstallSteps.Items.Count != 3)
                throw new InvalidOperationException("Navigation de réinstallation incomplète.");
            SaveSmokeVisual(this, "BASTOS-Guided-Reinstall-" + i + ".png");
        }
        ReinstallSteps.SelectedIndex = 0;
        ReinstallNext_Click(this, new RoutedEventArgs());
        ReinstallNext_Click(this, new RoutedEventArgs());
        ReinstallNext_Click(this, new RoutedEventArgs());
        if (ReinstallSteps.SelectedIndex != 2) throw new InvalidOperationException("Étape finale dépassée.");
        ReinstallBack_Click(this, new RoutedEventArgs());
        ReinstallBack_Click(this, new RoutedEventArgs());
        ReinstallBack_Click(this, new RoutedEventArgs());
        if (ReinstallSteps.SelectedIndex != 0) throw new InvalidOperationException("Retour hors du parcours.");
        if (IsoFamilyCombo.Items.Count == 0 || IsoLanguageCombo.Items.Count == 0)
            throw new InvalidOperationException("Catalogue absent du parcours guidé.");
        ReinstallSteps.SelectedIndex = 0;
        // Render the affected pages at the normal and minimum supported widths.
        // This only changes the test window's presentation, never a setting.
        double originalWidth = Width;
        foreach (int width in new[] { 1320, 1080 })
        {
            Width = width;
            foreach (string page in new[] { "software", "troubleshooting", "tweaking", "game", "browsers", "hardware" })
            {
                model.SelectedNavigation = model.Navigation.First(n => n.PageKey == page);
                if (page == "tweaking") model.ShowTweakingGeneralCommand.Execute(null);
                UpdateLayout();
                (FindName(page == "tweaking" ? "AdvancedPageScroll" : "PersonalizationPageScroll") as ScrollViewer)?.ScrollToTop();
                UpdateLayout();
                SaveSmokeVisual(this, $"BASTOS-Harmonized-{page}-{width}.png");
            }
        }
        Width = originalWidth;
        model.SelectedNavigation = original;
        RunAvailabilitySmoke(model);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "BASTOS-Guided-SmokeTest.txt"),
            "PASS : trois étapes, navigation avant/arrière bornée, catalogue conservé ; aucune commande de préparation exécutée.");
    }
}
