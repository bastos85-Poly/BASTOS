using System;
using System.IO;
using System.Linq;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async System.Threading.Tasks.Task RunInstallationDisplaySmokeAsync()
    {
        var main = (MainViewModel)DataContext;
        if (!main.Installation.ShouldShowAutomatically) throw new InvalidOperationException("Le premier lancement doit proposer le bilan dans les donnees de test vierges.");
        main.OpenInstallationCommand.Execute(null);
        await System.Threading.Tasks.Task.Delay(700);
        if (main.Installation.ShouldShowAutomatically) throw new InvalidOperationException("Le bilan affiche doit etre memorise.");
        async System.Threading.Tasks.Task FinishCheck()
        {
            for(int i=0;i<120 && main.Installation.IsBusy;i++) await System.Threading.Tasks.Task.Delay(500);
            if(main.Installation.IsBusy) throw new InvalidOperationException("Le controle du bilan ne se termine pas.");
        }
        await FinishCheck();
        var first = System.Windows.Application.Current.Windows.OfType<InstallationVerificationWindow>().Single();
        first.Close();
        if(main.Installation.ShouldShowAutomatically) throw new InvalidOperationException("Fermer le bilan ne doit pas le reproposer au demarrage.");
        main.OpenInstallationCommand.Execute(null);
        await System.Threading.Tasks.Task.Delay(700);
        if(!System.Windows.Application.Current.Windows.OfType<InstallationVerificationWindow>().Any()) throw new InvalidOperationException("Le bilan doit rester accessible manuellement.");
        await FinishCheck();
        System.Windows.Application.Current.Windows.OfType<InstallationVerificationWindow>().Single().Close();
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-InstallationDisplay-SmokeTest.txt"),"PASS : premier affichage reel, memorisation apres rendu, absence de repetition, reouverture manuelle ; controles Windows en lecture seule.");
    }
    private void RunInstallationSmoke()
    {
        var model=new InstallationVerificationViewModel(new AppPaths());
        string[] ids={"edition","language","region","keyboard","computer","account","shortcut","finalization"};
        string[] names={"Édition de Windows","Langue de Windows","Format régional","Clavier principal","Nom du PC","Compte local actif","Raccourci Bastos sur le Bureau","Finalisation du premier démarrage"};
        string[] values={"Professional","fr-FR","fr-FR","040C:0000040C","BASTOS-VMNEW","BastosLab","Verified","Completed"};
        var checks=ids.Select((id,index)=>new InstallationCheck(id,names[index],values[index],values[index],"Passed","Conforme au profil demandé. Données simulées pour contrôler l’affichage."))
            .Concat(new[]{"preferredlanguage","privacy","suggestions","onedrive","teams","outlook","copilot","widgets"}.Select(id=>new InstallationCheck(id,id,id=="preferredlanguage"?"fr-FR":"Applied",id=="preferredlanguage"?"fr-FR":"Applied","Passed","Preuve simulée pour l’affichage."))).ToArray();
        model.Display(new(DateTime.UtcNow,checks,""));
        var window=new InstallationVerificationWindow(model){Owner=this};window.Show();
        try{
            void Capture(string state){window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Installation-"+state+".png"));png.Save(output);}
            Capture("Verified");
            if(!ReferenceEquals(window.RecheckInstallationButton.Command,model.CheckCommand)||!window.VerificationSummary.Text.Contains("16 contrôles"))throw new InvalidOperationException("Bilan WPF non lie.");
            checks[0]=checks[0] with{Status="Mismatch",Actual="Core",Detail="Vérifie l’édition dans Paramètres → Système → Informations système et le choix fait dans le profil ISO."};
            checks[5]=checks[5] with{Status="Unavailable",Actual="",Detail="Le compte actif n’a pas pu être lu. Connecte-toi au compte local choisi puis relance le contrôle."};
            model.Display(new(DateTime.UtcNow,checks,""));Capture("Mismatch");
            if(!window.VerificationSummary.Text.Contains("1 écart")||model.Checks.Count!=16)throw new InvalidOperationException("Ecart du bilan non affiche.");
        }finally{window.Close();}
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Installation-SmokeTest.txt"),"OK : bilan WPF complet conforme et partiel, seize controles et consignes, bouton Recontroler lie. Donnees simulees ; aucun parametre Windows modifie.");
    }
}
