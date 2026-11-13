using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Bastos.Native.Models;
namespace Bastos.Native.Services;

public sealed record OperationResumeReview(string OperationId, DateTime CheckedUtc, bool Verified, string Message, string NextStep,
    IReadOnlyList<OperationCheck> Checks);

// Rechecks only. No installer, cleanup, boot scheduling or original arguments are replayed.
public sealed class OperationResumeService(string logRoot, Func<OperationResumeIntent, JsonElement, Task<OperationVerification>> verify,
    Func<int, DateTime, bool?>? isAlive = null, Func<OperationResumeIntent,bool?>? toolBusy = null,
    Func<OperationResumeIntent,IReadOnlyList<OperationCheck>>? inventory = null)
{
    private readonly OperationHistoryService history = new(logRoot);
    private readonly SemaphoreSlim gate = new(1,1);
    public static bool Supported(OperationResumeIntent? intent) => intent?.Kind is "RufusDownload" or "RecoveryPreparation" or "IsoBuild" or "WebView2" or "Adk";
    public OperationResumeReview? ReadLastReview(OperationHistoryEntry entry)
    {
        try{
            history.ResolveReport(entry);
            string path=Path.Combine(history.DirectoryPath,entry.Reference+".resume.json");
            if(!File.Exists(path))return null;
            var review=Read<OperationResumeReview>(path,256*1024);
            return review.OperationId==entry.Reference&&review.CheckedUtc>=entry.Result.StartedUtc&&review.CheckedUtc<=DateTime.UtcNow.AddMinutes(2)?review:null;
        }catch{return null;}
    }
    public async Task<OperationResumeReview> ReviewAsync(OperationHistoryEntry selected)
    {
        await gate.WaitAsync();
        try
        {
            string original = history.ResolveReport(selected);
            var current = Read<OperationResult>(original,4*1024*1024);
            string id = selected.Reference;
            OperationResumeReview Result(bool valid,string message,string next,IReadOnlyList<OperationCheck>? checks=null) =>
                new(id,DateTime.UtcNow,valid,message,next,checks??Array.Empty<OperationCheck>());
            if(current.OperationId!=id||current.SchemaVersion!=1||!Supported(current.ResumeIntent))
                return Result(false,"Ce rapport ne contient pas les informations nécessaires à un contrôle de reprise.","Retourne au module concerné et vérifie son état. Les anciennes actions ne sont jamais rejouées depuis ce rapport.");
            if(current.State==OperationState.Running && OwnerAlive(current.OwnerProcessId,current.OwnerProcessStartedUtc)!=false)
                return Result(false,"Le lancement d’origine est encore actif ou son état ne peut pas être confirmé.","Attends sa fin et actualise le Journal. Aucune seconde tentative lancée.");
            bool stopped = current.ExecutionStarted==false || (current.State!=OperationState.Running && current.ProcessStopped && !current.ActionCompletionUnconfirmed);
            string receipt=Path.Combine(history.DirectoryPath,id+".process.json");
            if(!stopped && File.Exists(receipt))
            {
                var identity=Read<ProcessReceipt>(receipt,8192);
                stopped=!current.ActionCompletionUnconfirmed&&identity.SchemaVersion==1&&identity.OperationId==id&&identity.StartedUtc!=default&&OwnerAlive(identity.ProcessId,identity.StartedUtc)==false;
            }
            if(!stopped)
                return Result(false,"La fin de l’outil externe n’est pas confirmée ; ses fichiers peuvent encore évoluer.","Vérifie l’outil dans Windows, puis actualise Journal. Le contrôle ne relance ni installation ni préparation.");
            if((toolBusy??ToolsBusy)(current.ResumeIntent!)!=false)
                return Result(false,"Un outil pouvant encore utiliser ces fichiers est actif ou son état est inaccessible.","Attends la fin des outils d’installation ou d’image, puis relance ce contrôle. Aucun processus n’a été arrêté.");
            string report=Path.Combine(history.DirectoryPath,id+".worker.json");
            if(!File.Exists(report))
            {
                var observed=inventory?.Invoke(current.ResumeIntent!)??Array.Empty<OperationCheck>();
                string presence=observed.Count==0?"": "\nPrésence uniquement : "+string.Join(" ; ",observed.Select(c=>c.Name+" "+(c.Passed?"présent":"absent")))+". Ces éléments seuls ne prouvent pas que la préparation est complète.";
                return await Save(Result(false,"Le rapport final de l’outil est absent. Une préparation partielle peut subsister."+presence,"Retourne au module : son bilan recontrôle les fichiers et les cibles avant une nouvelle préparation. Aucun fichier n’a été supprimé ni aucune action relancée.",observed));
            }
            using var data=ReadJson(report,16*1024*1024);
            var payload=data.RootElement;
            if(payload.GetProperty("SchemaVersion").GetInt32()!=1||payload.GetProperty("OperationId").GetString()!=id||
                payload.GetProperty("Success").ValueKind!=JsonValueKind.True)
                return await Save(Result(false,"L’outil n’a pas enregistré de résultat réussi pour cette tentative.","Consulte son erreur, puis rouvre le module pour un nouveau bilan. Les fichiers existants sont conservés."));
            var checkedResult=await verify(current.ResumeIntent!,payload);
            return await Save(Result(checkedResult.Valid&&!checkedResult.Partial,checkedResult.Message,
                checkedResult.Valid&&!checkedResult.Partial?"Les éléments contrôlés peuvent être réutilisés. Continue dans le module ; le bilan et les confirmations restent requis avant toute écriture ou tout redémarrage.":
                "Les éléments existants ne sont pas entièrement validés. Retourne au module pour corriger le blocage et refaire son bilan ; aucune action n’a été relancée.",checkedResult.Checks));
        }
        catch(Exception error)
        {return new(selected.Reference,DateTime.UtcNow,false,"Contrôle de reprise impossible : le rapport ou les fichiers attendus ne sont plus lisibles.","Actualise le Journal et consulte les détails d’origine. Aucun programme ni lien fourni par le rapport n’a été ouvert.",new[]{new OperationCheck("Lecture du contrôle",false,error.Message)});}
        finally{gate.Release();}
    }
    private bool? OwnerAlive(int pid,DateTime? started)
    {
        if(pid<=0||started==null)return null;
        if(isAlive!=null)return isAlive(pid,started.Value);
        try{using var process=Process.GetProcessById(pid);return !process.HasExited&&process.StartTime.ToUniversalTime()==started.Value.ToUniversalTime();}
        catch(ArgumentException){return false;}catch(InvalidOperationException){return false;}catch{return null;}
    }
    private static T Read<T>(string file,int maximum) where T:class {using var json=ReadJson(file,maximum);return json.RootElement.Deserialize<T>()??throw new JsonException();}
    private static JsonDocument ReadJson(string file,int maximum)
    {
        RefuseLinks(file);
        var info=new FileInfo(file);
        if(info.Length>maximum||(info.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Rapport trop volumineux ou redirigé.");
        using var input=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        return JsonDocument.Parse(input);
    }
    private async Task<OperationResumeReview> Save(OperationResumeReview review)
    {
        string file=Path.Combine(history.DirectoryPath,review.OperationId+".resume.json"),temporary=file+"."+Guid.NewGuid().ToString("N")+".tmp";
        RefuseLinks(file);
        try{await using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))await JsonSerializer.SerializeAsync(output,review,new JsonSerializerOptions{WriteIndented=true});File.Move(temporary,file,true);return review;}
        finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
    private static void RefuseLinks(string path)
    {
        if(Path.GetFullPath(path).StartsWith(@"\\",StringComparison.Ordinal))throw new IOException("Chemin réseau refusé.");
        for(FileSystemInfo? item=new FileInfo(path);item!=null;item=item is FileInfo f?f.Directory:((DirectoryInfo)item).Parent)
            if(item.Exists&&(item.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Chemin redirigé refusé.");
    }
    private static bool? ToolsBusy(OperationResumeIntent intent)
    {
        string[] names=intent.Kind switch{
            "RecoveryPreparation"=>new[]{"dism","DismHost","robocopy","bcdboot","bcdedit"},
            "IsoBuild"=>new[]{"dism","DismHost","robocopy","oscdimg"},
            "Adk"=>new[]{"adksetup","msiexec"},
            "WebView2"=>new[]{"MicrosoftEdgeWebview2Setup","MicrosoftEdgeUpdate"},_=>Array.Empty<string>()};
        try{foreach(string name in names){var processes=Process.GetProcessesByName(name);bool found=processes.Length>0;foreach(var process in processes)process.Dispose();if(found)return true;}return false;}catch{return null;}
    }
    private sealed record ProcessReceipt(int SchemaVersion,string OperationId,int ProcessId,DateTime StartedUtc);
}
