using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private void RunSettingsClassificationSmoke(MainViewModel model)
    {
        RunGpuVendorSmoke(model);
        var groups=model.PersonalizationGroups.Concat(model.AdvancedSettingsGroups).ToArray();
        var toggles=groups.SelectMany(g=>g.Toggles).ToArray();
        var expectedToggles=model.TroubleshootingToggles.Concat(model.RiskyOptimizationToggles).Concat(model.TweakingToggles).Append(model.NvidiaPStateToggle).ToArray();
        if(toggles.Length!=expectedToggles.Length||toggles.Distinct().Count()!=toggles.Length||expectedToggles.Any(t=>!toggles.Contains(t)))
            throw new InvalidOperationException("Reglage bascule perdu ou duplique lors du classement.");
        var choices=groups.SelectMany(g=>g.Choices).ToArray();
        var expectedChoices=model.TroubleshootingChoices.Concat(model.TweakingChoices).ToArray();
        if(choices.Length!=expectedChoices.Length||choices.Distinct().Count()!=choices.Length||expectedChoices.Any(c=>!choices.Contains(c)))
            throw new InvalidOperationException("Choix perdu ou duplique lors du classement.");
        var cards=groups.SelectMany(g=>g.Cards).ToArray();
        if(cards.Distinct().Count()!=cards.Length||model.SecurityPrivacyCards.Concat(model.KeyboardOptimizationCards).Any(c=>!cards.Contains(c)))
            throw new InvalidOperationException("Carte de preference perdue ou dupliquee.");
        if(!model.PersonalizationGroups.Single(g=>g.Key=="security").Toggles.Any(t=>t.Key=="RiskUnsafeDownloads")||
            !model.AdvancedSettingsGroups.Single(g=>g.Key=="maintenance").Toggles.Any(t=>t.Key=="RiskDisableBackgroundMaintenance")||
            model.OptimizationCategories.Items.Any(c=>c.Key is "security" or "keyboard" or "mouse"))
            throw new InvalidOperationException("Preference encore presente dans Optimisations.");
        if(!model.PersonalizationGroups.Single(g=>g.Key=="input").HasMouse||model.KeyboardOptimizationCards.Count!=2)
            throw new InvalidOperationException("Clavier ou souris absent de Personnalisation.");
        model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="optimizations");
        if(model.CurrentPage.Cards.Count!=5||model.CurrentPage.Cards.Any(c=>cards.Contains(c))||
            !model.AdvancedSettingsGroups.Single(g=>g.Key=="network").Cards.Any(c=>c.Title.Contains("WebDAV"))||
            !model.AdvancedSettingsGroups.Single(g=>g.Key=="maintenance").Cards.Any(c=>c.Title=="Nettoyage temporaire"))
            throw new InvalidOperationException("Actions techniques perdues ou dupliquees dans Optimisations.");
        IEnumerable<T> Find<T>(DependencyObject parent) where T:DependencyObject
        { for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++){var child=VisualTreeHelper.GetChild(parent,i);if(child is T match)yield return match;foreach(var nested in Find<T>(child))yield return nested;} }
        void Capture(string name){UpdateLayout();var image=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);image.Render(this);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Settings-"+name+".png"));png.Save(output);}
        model.OptimizationCategories.Selected=model.OptimizationCategories.Items.First(c=>c.Key=="windows");UpdateLayout();
        foreach(var card in model.CurrentPage.Cards)
            if(Find<System.Windows.Controls.Primitives.ButtonBase>(WindowsOptimizationCategory).Count(b=>b.IsVisible&&ReferenceEquals(b.Command,card.IsToggleCard ? card.ToggleCommand : card.PrimaryCommand))!=1)
                throw new InvalidOperationException("Carte de performances dupliquee ou absente dans la vue.");
        model.OptimizationCategories.Selected=model.OptimizationCategories.Items.Single(c=>c.Key=="cpu");UpdateLayout();
        if(model.CpuOptimizationCards.Count!=4 || !CpuOptimizationCategory.IsVisible ||
            model.CpuOptimizationCards.Any(c=>!Find<System.Windows.Controls.Primitives.ButtonBase>(CpuOptimizationCategory).Any(b=>ReferenceEquals(b.Command,c.ToggleCommand))))
            throw new InvalidOperationException("Profils d’affinité absents d’Optimisations > Processeur.");
        Capture("Optimizations-CPU-Affinity");
        model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="troubleshooting");UpdateLayout();
        Expander Expand(string key, bool personal){var item=Find<Expander>(this).Single(e=>e.DataContext is SettingsGroup g&&g.Key==key&&(personal?model.PersonalizationGroups:model.AdvancedSettingsGroups).Contains(g));item.IsExpanded=true;UpdateLayout();item.BringIntoView();UpdateLayout();return item;}
        var appearance=Expand("appearance",true);
        if(model.PersonalizationGroups.Single(g=>g.Key=="appearance").Toggles.Count!=0 || model.PersonalizationGroups.Single(g=>g.Key=="appearance").Choices.Count!=0) throw new InvalidOperationException("Options retirees encore presentes dans Interface.");
        if(!model.SoftwareApps.Any(t=>t.Package.Id=="Microsoft.Sysinternals.ProcessExplorer") || !model.SoftwareApps.Any(t=>t.Package.Id=="OpenWhispr.OpenWhispr")) throw new InvalidOperationException("Logiciels a conserver absents du catalogue.");
        Capture("Personalization-Appearance");appearance.IsExpanded=false;
        var security=Expand("security",true);
        var unsafeToggle=model.RiskyOptimizationToggles.Single(t=>t.Key=="RiskUnsafeDownloads");
        if(!Find<Button>(security).Any(b=>ReferenceEquals(b.Command,unsafeToggle.ToggleCommand)))throw new InvalidOperationException("Commande du telechargement perdue en Personnalisation.");
        Capture("Personalization-Security");security.IsExpanded=false;
        var input=Expand("input",true);
        if(!Find<MouseSettingsPage>(input).Any(p=>p.IsVisible))throw new InvalidOperationException("Souris deplacee mais non affichee.");
        Capture("Personalization-Input");input.IsExpanded=false;
        model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="tweaking");UpdateLayout();
        var maintenance=Expand("maintenance",false);
        if(!Find<Button>(maintenance).Any(b=>ReferenceEquals(b.Command,model.RiskyOptimizationToggles.Single(t=>t.Key=="RiskDisableBackgroundMaintenance").ToggleCommand)))throw new InvalidOperationException("Commande maintenance perdue.");
        Capture("Advanced-Maintenance");maintenance.IsExpanded=false;
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-SettingsClassification-SmokeTest.txt"),
            $"OK : {groups.Length} groupes, {toggles.Length} bascules et {choices.Length} choix classes exactement une fois avec les objets/commandes d origine ; {cards.Length} cartes classees ; quatre profils d’affinité dans Optimisations > Processeur ; aucune action appliquee.");
    }

    private void RunGpuVendorSmoke(MainViewModel model)
    {
        string cachePath=Path.Combine(Path.GetTempPath(),"GpuVendorCacheTest",Guid.NewGuid().ToString("N"),"profile.json");
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        var legacy=new HardwareProfile {GpuName="AMD Radeon"};
        File.WriteAllText(cachePath,System.Text.Json.JsonSerializer.Serialize(legacy));
        HardwareProfile live=new HardwareProfile {GpuName="AMD Radeon",GpuDeviceIds=new[]{@"PCI\VEN_1002&DEV_7550"}};
        var cache=new Bastos.Native.Services.HardwareProfileService(cachePath,()=>System.Threading.Tasks.Task.FromResult(live));
        var migrated=cache.GetOrDetectAsync().GetAwaiter().GetResult();
        if(migrated.FromCache || cache.Load()?.GpuDeviceIds?.Length!=1)throw new InvalidOperationException("Migration inventaire GPU echouee.");
        live.GpuDeviceIds=new[]{@"PCI\VEN_1002&DEV_7550",@"PCI\VEN_8086&DEV_1234"};
        if(cache.GetOrDetectAsync().GetAwaiter().GetResult().Profile.GpuDeviceIds?.Length!=2)throw new InvalidOperationException("GPU secondaire ignore dans le cache.");
        var failingCache=new Bastos.Native.Services.HardwareProfileService(cachePath,()=>System.Threading.Tasks.Task.FromException<HardwareProfile>(new IOException("Detection indisponible")));
        if(failingCache.GetOrDetectAsync().GetAwaiter().GetResult().Profile.GpuDeviceIds?.Length!=2)throw new InvalidOperationException("Cache perdu apres echec temporaire.");
        live.GpuDeviceIds=Array.Empty<string>();
        if(cache.GetOrDetectAsync().GetAwaiter().GetResult().Profile.GpuDeviceIds?.Length!=0)throw new InvalidOperationException("Ancien GPU conserve apres retrait.");
        string[]? original = model.GpuDeviceIds;
        var cases = new (string[]? Ids, int Count, string[] Brands)[] {
            (new[]{@"PCI\VEN_1002&DEV_7550"}, 5, new[]{"AMD"}),
            (new[]{@"PCI\VEN_10DE&DEV_1234"}, 3, new[]{"NVIDIA"}),
            (new[]{@"PCI\VEN_8086&DEV_1234"}, 3, new[]{"Intel"}),
            (new[]{@"PCI\VEN_1002&DEV_7550", @"PCI\VEN_8086&DEV_1234"}, 8, new[]{"AMD","Intel"}),
            (new[]{@"PCI\VEN_1002&DEV_7550", @"PCI\VEN_10DE&DEV_1234"}, 8, new[]{"AMD","NVIDIA"}),
            (new[]{@"pci\ven_1002&dev_7550", @"PCI\VEN_1002&DEV_1234"}, 5, new[]{"AMD"}),
            (new[]{@"ROOT\Microsoft Basic Display", @"PCI\VEN_9999&DEV_1002"}, 0, Array.Empty<string>()),
            (Array.Empty<string>(), 0, Array.Empty<string>()),
            (null, 0, Array.Empty<string>())
        };
        try
        {
            model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="optimizations");
            model.OptimizationCategories.Selected=model.OptimizationCategories.Items.First(c=>c.Key=="graphics");
            foreach (var test in cases)
            {
                model.UpdateGpuInventory(test.Ids);
                UpdateLayout();
                if(model.GpuOptimizationCards.Count!=test.Count || model.GpuOptimizationCards.Any(c=>!test.Brands.Any(b=>c.Title.StartsWith(b+" —",StringComparison.Ordinal))))
                    throw new InvalidOperationException("Filtrage GPU incorrect : " + string.Join(",",test.Brands));
                int CountCards(DependencyObject parent) {
                    int count=0;
                    for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++) {
                        var child=VisualTreeHelper.GetChild(parent,i);
                        if(child is ItemsControl items && ReferenceEquals(items.ItemsSource,model.GpuOptimizationCards)) count+=items.Items.Count;
                        count+=CountCards(child);
                    }
                    return count;
                }
                if(CountCards(GraphicsOptimizationCategory)!=test.Count)
                    throw new InvalidOperationException("Vue GPU non synchronisee avec la detection.");
            }
        }
        finally { model.UpdateGpuInventory(original); }
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-GpuVendors-SmokeTest.txt"),
            "OK : 9 scenarios AMD / NVIDIA / Intel / hybrides / doublons / inconnus / vide / ancien cache ; nombre et marque des cartes verifies dans la vue ; 4 controles cache (migration, GPU secondaire, echec temporaire, retrait) ; aucun reglage applique.");
    }
}
