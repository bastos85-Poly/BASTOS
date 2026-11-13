using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Bastos.Native.Models;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class MainWindow
{
    private void RunAvailabilitySmoke(MainViewModel model)
    {
        var vm=model.Reinstall;
        var originalIso=vm.SelectedIso;
        var originalPage=model.SelectedNavigation;
        int originalStep=ReinstallSteps.SelectedIndex;
        var fakeIso=new IsoChoice("ISO simulée — aucune exécution",Path.Combine(Path.GetTempPath(),"Availability-fixture.iso"));
        var busyProperty=typeof(ReinstallViewModel).GetProperty(nameof(vm.IsBusy));
        var catalogProperty=typeof(ReinstallViewModel).GetProperty(nameof(vm.IsCatalogRefreshing));
        IEnumerable<T> Descendants<T>(DependencyObject item) where T:DependencyObject
        {
            if(item is T match)yield return match;
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(item);i++)foreach(var child in Descendants<T>(VisualTreeHelper.GetChild(item,i)))yield return child;
        }
        try
        {
            model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="reinstall");
            ReinstallSteps.SelectedIndex=2;
            vm.SelectedIso=null;
            UpdateLayout();
            var launch=Descendants<Button>(this).Single(b=>ReferenceEquals(b.Command,vm.BootRecoveryCommand));
            if(launch.IsEnabled||!vm.BootRecoveryCommand.DisabledReason.Contains("étape 2")||
                launch.ToolTip is not string hint||!hint.Contains("ISO")||!ToolTipService.GetShowOnDisabled(launch)||
                !Descendants<TextBlock>(this).Any(t=>t.IsVisible&&t.Text==vm.BootRecoveryCommand.DisabledReason))
                throw new InvalidOperationException("Prérequis ISO absent, masqué ou non accessible au survol.");
            SaveSmokeVisual(this,"BASTOS-Availability-NoISO.png");
            vm.Isos.Add(fakeIso);vm.SelectedIso=fakeIso;UpdateLayout();
            if(!launch.IsEnabled||vm.BootRecoveryCommand.DisabledReason!="")throw new InvalidOperationException("L’explication ne disparaît pas après la sélection.");
            SaveSmokeVisual(this,"BASTOS-Availability-Ready.png");
            // Private state changes only in the isolated WPF harness; no engine invoked.
            busyProperty!.SetValue(vm,true);UpdateLayout();
            if(launch.IsEnabled||vm.DeleteIsoCommand.CanExecute(null)||vm.RufusOptionsCommand.CanExecute(null)||
                vm.CanChooseLocalIso||vm.IsCatalogReady||!vm.BootRecoveryCommand.DisabledReason.Contains("opération"))
                throw new InvalidOperationException("Actions concurrentes non expliquées pendant l’opération.");
            SaveSmokeVisual(this,"BASTOS-Availability-Busy.png");
            busyProperty.SetValue(vm,false);catalogProperty!.SetValue(vm,true);UpdateLayout();
            if(launch.IsEnabled||!vm.BootRecoveryCommand.DisabledReason.Contains("catalogue"))throw new InvalidOperationException("Chargement du catalogue non expliqué.");
            catalogProperty.SetValue(vm,false);UpdateLayout();
            if(!launch.IsEnabled)throw new InvalidOperationException("Action non rétablie après le chargement.");
            File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Availability-SmokeTest.txt"),
                "PASS : ISO absente, sélection, opération en cours, catalogue en cours et retour disponible ; vrai bouton WPF, aide visible et infobulle sur bouton désactivé. Aucune commande sensible exécutée.");
        }
        finally
        {
            busyProperty!.SetValue(vm,false);catalogProperty!.SetValue(vm,false);
            vm.Isos.Remove(fakeIso);vm.SelectedIso=originalIso;
            ReinstallSteps.SelectedIndex=originalStep;model.SelectedNavigation=originalPage;
        }
    }
}
