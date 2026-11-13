using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
namespace Bastos.Native.ViewModels;
public sealed partial class MainViewModel
{
    public ObservableCollection<StatusCard> SoundOptimizationCards { get; } = new();
    public ObservableCollection<StatusCard> CompetitiveNetworkCards { get; } = new();
    public ObservableCollection<StatusCard> CompetitiveGameCards { get; } = new();
    private readonly Dictionary<string,StatusCard> competitiveCards = new();
    private readonly SemaphoreSlim competitiveGate = new(1,1);
    public AsyncRelayCommand RefreshCompetitiveCommand { get; private set; } = null!;
    private void BuildCompetitiveCards()
    {
        RefreshCompetitiveCommand = new AsyncRelayCommand(RefreshCompetitiveAsync);
        AddCompetitive(SoundOptimizationCards,"audio-game","Audio pour les jeux compétitifs",
            "Demande 48 kHz en PCM 24 bits, ou 16 bits selon les formats réellement acceptés par le périphérique, sans changer le nombre de canaux. Désactive les améliorations audio et le son spatial lorsqu’ils sont accessibles. La période audio reste gérée par Windows et les applications. Relancez les applications audio après application.");
        AddCompetitive(SoundOptimizationCards,"audio-power","Garder le codec audio éveillé",
            "Désactive les délais de veille des pilotes audio pour éviter certains retards au réveil. Peut augmenter la consommation, notamment sur batterie. Redémarrez Windows pour que les pilotes reprennent ces réglages.");
        AddCompetitive(CompetitiveNetworkCards,"udp-fastpath","Traitement rapide des petits paquets UDP",
            "Porte les seuils d’envoi et de copie en réception AFD à 1 500 octets. Réglage expérimental : une baisse du ping n’est pas garantie et son effet dépend de Windows. Les profils de votre carte réseau restent indépendants. Redémarrage recommandé.");
        AddCompetitive(CompetitiveGameCards,"mouse-queue","Marge pour les souris à 1 000–8 000 Hz",
            "Porte la file d’événements du pilote souris à 1 024 entrées pour mieux absorber les pointes d’activité. Ne change ni la fréquence USB de la souris ni sa latence matérielle. Redémarrage requis.");
        AddCompetitive(CompetitiveGameCards,"frame-timers","Timers pour les jeux",
            "Autorise les demandes globales de résolution des timers et désactive le tick dynamique au démarrage. Peut accroître la consommation ; des temps de trame plus réguliers ne sont pas garantis. Ne force pas une résolution permanente à 0,5 ms et ne change pas HPET. Redémarrage requis.");
        AddCompetitive(CompetitiveGameCards,"steam-gpu","Limiter le GPU utilisé par l’interface Steam",
            "Désactive le rendu GPU des affichages Web dans les préférences permanentes de Steam et ajoute -cef-disable-gpu aux démarrages automatiques et raccourcis existants. Le réglage reste actif après redémarrage du PC, même si Steam est ouvert par un jeu. Si Steam est déjà ouvert, relancez-le une seule fois après application. Les jeux gardent leur accélération graphique.");
        AddCompetitive(CompetitiveGameCards,"sdl3","Entrées directes pour les jeux SDL3",
            "Configure le clavier Raw Input, la souris sans messages classiques en mode relatif et la fermeture par Alt+F4. Ces variables ne concernent que les jeux utilisant une version compatible de SDL3 (souris NOLEGACY : SDL 3.6 ou ultérieure). Relancez les jeux ; une nouvelle session Windows peut être nécessaire.");
    }
    private void AddCompetitive(ObservableCollection<StatusCard> list,string id,string title,string description)
    {
        StatusCard card=null!;
        card=new StatusCard(title,description,"État non vérifié — actualisez les réglages",StatusTone.Neutral,
            "Appliquer",new AsyncRelayCommand(()=>RunCompetitiveAsync(card,id,"Apply")),
            "Restaurer mes valeurs",new AsyncRelayCommand(()=>RunCompetitiveAsync(card,id,"Restore")),isChoiceCard:true);
        competitiveCards.Add(id,card);list.Add(card);
    }
    private async Task ReadCompetitiveResultAsync(string file,bool restore=false)
    {
        using var doc=JsonDocument.Parse(await File.ReadAllTextAsync(file));
        foreach(var result in doc.RootElement.GetProperty("Results").EnumerateArray())
        {
            if(!competitiveCards.TryGetValue(result.GetProperty("Id").GetString()??"",out var card))continue;
            bool success=result.GetProperty("Success").GetBoolean();bool applied=result.GetProperty("Applied").GetBoolean();
            var message=result.GetProperty("Message").GetString()??"Résultat indisponible";
            if(result.TryGetProperty("Details",out var details))foreach(var detail in details.EnumerateArray())message+="\n• "+detail.GetString();
            card.State=message;card.Tone=!success?StatusTone.Warning:applied?StatusTone.Success:StatusTone.Neutral;
            int pending=result.TryGetProperty("Pending",out var p)?p.GetInt32():0;
            card.IsPartiallyApplied=!applied&&pending>0;
            if(success||pending>0)card.SelectChoice(applied||pending>0);else card.ClearChoice();
        }
    }
    internal async Task RefreshCompetitiveForTestAsync() { await competitiveGate.WaitAsync(); competitiveGate.Release(); await RefreshCompetitiveAsync(); }
    private async Task RefreshCompetitiveAsync()
    {
        if(!await competitiveGate.WaitAsync(0))return;
        try
        {
            var file=Path.Combine(paths.LogRoot,"Competitive-Read-"+Guid.NewGuid().ToString("N")+".json");
            var result=await workers.RunAsync("Manage-BASTOS-Competitive.ps1",new[]{"-Action","Get","-Id","all","-ResultPath",file},elevate:false,timeoutMinutes:2);
            if(File.Exists(file))await ReadCompetitiveResultAsync(file);
            else foreach(var card in competitiveCards.Values){card.ClearChoice();card.State="Lecture impossible : "+result.Error;card.Tone=StatusTone.Warning;}
        }
        catch(Exception ex){foreach(var card in competitiveCards.Values){card.ClearChoice();card.State="Lecture impossible : "+ex.Message;card.Tone=StatusTone.Warning;}}
        finally{competitiveGate.Release();}
    }
    private async Task RunCompetitiveAsync(StatusCard card,string id,string action)
    {
        if(!await competitiveGate.WaitAsync(0)){card.State="Une autre opération sur ces réglages est en cours.";return;}
        try
        {
            card.State="Vérification et sauvegarde des valeurs…";
            var file=Path.Combine(paths.LogRoot,"Competitive-"+id+"-"+Guid.NewGuid().ToString("N")+".json");
            var result=await workers.RunAsync("Manage-BASTOS-Competitive.ps1",new[]{"-Action",action,"-Id",id,"-ResultPath",file},elevate:true,timeoutMinutes:3);
            if(File.Exists(file))await ReadCompetitiveResultAsync(file,action=="Restore");
            else {card.State="Opération non confirmée : "+result.Error;card.Tone=StatusTone.Warning;}
        }
        catch(Exception ex){card.State="Opération non confirmée : "+ex.Message;card.Tone=StatusTone.Warning;}
        finally{competitiveGate.Release();}
    }
}


