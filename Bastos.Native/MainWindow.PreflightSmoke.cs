using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class MainWindow
{
    private void RunPreflightSmoke()
    {
        const long gb = 1073741824;
        string diskId = Guid.NewGuid().ToString(), partId = Guid.NewGuid().ToString();
        var options = new RufusInstallOptions { ComputerName = "BASTOS-PC", EditionIsoPath = @"D:\ISO\Windows11-Pro.iso",
            WindowsImageIndex = 6, WindowsEditionId = "Professional", WindowsImageName = "Windows 11 Pro", WindowsUILanguage = "fr-FR",
            EditionIsoSha256 = new string('A',64), DiskSafetySnapshot = "simulation", WindowsDiskIdentity = diskId, RecoveryPartitionGuid = partId };
        var disk = new RecoveryDiskPreview(true,"Plan de test", "D: BASTOS_RECOVERY — 40 Go — disque 0",partId,diskId,"simulation") {
            RecoveryFreeBytes = 18*gb, RecoverySizeBytes = 40*gb, CreateEfi = true, DiskDescription = "Disque 0 — NVMe — 500 Go — GPT / UEFI",
            Partitions = new[] { new RecoveryPartitionPreview(1,Guid.NewGuid().ToString(),"EFI",260*1024*1024,"EFFACER"),
                new RecoveryPartitionPreview(2,Guid.NewGuid().ToString(),"MSR",16*1024*1024,"EFFACER"),
                new RecoveryPartitionPreview(3,Guid.NewGuid().ToString(),"C:",450*gb,"EFFACER"),new RecoveryPartitionPreview(4,partId,"D:",40*gb,"CONSERVER") } };
        var catalog = new WindowsIsoEditionCatalog(options.EditionIsoPath, options.EditionIsoSha256,
            new[] {new WindowsIsoEdition(6,"Windows 11 Pro","Professional") {Languages = new[]{"fr-FR"}}});
        foreach (bool blocked in new[]{false,true})
        {
            var review = RecoveryPreflightBuilder.Build(options.EditionIsoPath,6*gb,options,
                blocked ? disk with {RecoveryFreeBytes = 1*gb} : disk,catalog,"",true);
            var window = new RecoveryPreflightWindow(review) { Owner = this, Title = "BASTOS — Bilan (données simulées pour le test)" };
            window.Show();
            window.UpdateLayout();
            if (window.LaunchButton.IsEnabled) throw new InvalidOperationException("Confirmation initialement active.");
            if(string.IsNullOrWhiteSpace(window.LaunchHint.Text)||window.LaunchButton.ToolTip is not string)
                throw new InvalidOperationException("Raison du lancement indisponible absente.");
            window.Acknowledgement.IsChecked = true;
            if (window.LaunchButton.IsEnabled == blocked) throw new InvalidOperationException("Blocage du bilan incorrect.");
            if(blocked ? !window.LaunchHint.Text.Contains("bloquants") : window.LaunchHint.Text!="")
                throw new InvalidOperationException("Explication non actualisée après la confirmation.");
            void Capture(string suffix)
            {
                window.UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);
                bitmap.Render(window);
                var encoder = new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var output = File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Preflight-"+suffix+".png"));encoder.Save(output);
            }
            Capture(blocked ? "Blocked" : "Ready");
            if (!blocked) { window.ReviewScroll.ScrollToEnd(); Capture("Consequences"); }
            window.Close();
        }
        var main=(Bastos.Native.ViewModels.MainViewModel)DataContext;
        var editionChoices = new WindowsIsoEditionCatalog(options.EditionIsoPath, options.EditionIsoSha256,
            new[] { new WindowsIsoEdition(1,"Windows 11 Home","Core"), new WindowsIsoEdition(2,"Windows 11 Home N","CoreN"),
                new WindowsIsoEdition(4,"Windows 11 Education","Education"), new WindowsIsoEdition(6,"Windows 11 Pro","Professional"),
                new WindowsIsoEdition(7,"Windows 11 Pro N","ProfessionalN"), new WindowsIsoEdition(12,"Windows 11 Enterprise","Enterprise") });
        options.WindowsImageIndex = 0;
        options.WindowsEditionId = "";
        options.WindowsImageName = "";
        var optionsWindow=new RufusInstallWindow(options,options.EditionIsoPath,"Disque simulé","Aucune écriture de disque pendant ce test.",
            ()=>System.Threading.Tasks.Task.FromResult(editionChoices),main.Reinstall.Languages,main.Reinstall.Keyboards){Owner=this};
        optionsWindow.Show();optionsWindow.UpdateLayout();
        try{
            if(optionsWindow.EditionCombo.Items.Count != 3)throw new InvalidOperationException("Seules Home, Education et Pro doivent etre proposees.");
            if(optionsWindow.EditionCombo.DisplayMemberPath != nameof(WindowsIsoEdition.InstallOptionDisplay) ||
                ((WindowsIsoEdition)optionsWindow.EditionCombo.Items[0]).InstallOptionDisplay != "Pro" ||
                ((WindowsIsoEdition)optionsWindow.EditionCombo.Items[1]).InstallOptionDisplay != "Home" ||
                ((WindowsIsoEdition)optionsWindow.EditionCombo.Items[2]).InstallOptionDisplay != "Éducation" ||
                ((WindowsIsoEdition)optionsWindow.EditionCombo.Items[0]).ImageIndex != 6 ||
                ((WindowsIsoEdition)optionsWindow.EditionCombo.SelectedItem).ImageIndex != 6)
                throw new InvalidOperationException("Le menu doit afficher Pro, Home, Éducation et présélectionner Pro sans montrer les index.");
            optionsWindow.UpdateLayout();
            var optionsBitmap = new RenderTargetBitmap((int)optionsWindow.ActualWidth,(int)optionsWindow.ActualHeight,96,96,PixelFormats.Pbgra32);
            optionsBitmap.Render(optionsWindow);
            var optionsEncoder = new PngBitmapEncoder();
            optionsEncoder.Frames.Add(BitmapFrame.Create(optionsBitmap));
            using(var output = File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Edition-Options-Smoke.png"))) optionsEncoder.Save(output);
            if(options.UseExactRufusExperience || options.DisableWidgets || options.DisableConsumerContent)
                throw new InvalidOperationException("Le mode normal doit laisser les nettoyages facultatifs désactivés.");
            optionsWindow.CleanBastosCheckBox.IsChecked=true;
            if(!options.UseCleanBastosInstallation || !options.DisableWidgets || !options.DisableConsumerContent || !options.RemoveOneDrive)
                throw new InvalidOperationException("Le profil propre n’active pas ses réglages de nettoyage.");
            optionsWindow.CleanBastosCheckBox.IsChecked=false;
            if(options.DisableWidgets || options.DisableConsumerContent || options.RemoveOneDrive)
                throw new InvalidOperationException("Le retour au mode normal conserve des nettoyages facultatifs.");
            optionsWindow.KeyboardCombo.SelectedItem=System.Linq.Enumerable.First(main.Reinstall.Keyboards,k=>k.InputLocale=="0409:00000409");
            if(!optionsWindow.KeyboardHint.Text.Contains("Attention"))throw new InvalidOperationException("Avertissement clavier anglais absent.");
            optionsWindow.KeyboardCombo.SelectedItem=System.Linq.Enumerable.First(main.Reinstall.Keyboards,k=>k.InputLocale=="040C:0000040C");
            if(optionsWindow.KeyboardHint.Text.Contains("Attention"))throw new InvalidOperationException("Avertissement clavier non actualisé.");
        }finally{optionsWindow.Close();}
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Preflight-SmokeTest.txt"),
            "OK : confirmation du bilan et blocage espace insuffisant ; profils normal/propre ; avertissement QWERTY/français actualisé. Aucune préparation ni réinstallation lancée.");
    }
}
