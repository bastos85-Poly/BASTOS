using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
namespace Bastos.Native.Services;

public sealed record CancellationStatus(bool CanRequest, bool Requested, string Message);

// Cooperative only: never kills a process. Worker boundaries are authoritative;
// a late request may be refused and must never be presented as completed cancellation.
public sealed class OperationCancellation(IProgress<CancellationStatus>? progress = null) : IDisposable
{
    private readonly object gate = new();
    private readonly CancellationTokenSource source = new();
    private string? requestPath;
    private bool allowed, requested;
    public CancellationToken Token => source.Token;
    public bool Requested { get { lock(gate)return requested; } }
    public void AllowRead() => Set(true,"Arrêt possible après le contrôle en lecture en cours ; aucun processus ne sera forcé à s’arrêter.");
    public void Lock(string reason) => Set(false,reason);
    private void Set(bool canRequest,string message)
    {
        lock(gate){allowed=canRequest;progress?.Report(new(canRequest&&!requested,requested,requested&&canRequest?
            "Demande d’annulation envoyée. Attends le point d’arrêt et son résultat ; ne ferme pas Bastos.":message));}
    }
    public bool Request()
    {
        lock(gate)
        {
            if(!allowed||requested)return false;
            try
            {
                if(requestPath!=null){using var file=new FileStream(requestPath,FileMode.CreateNew,FileAccess.Write,FileShare.Read);file.WriteByte(1);file.Flush(true);}
                requested=true;source.Cancel();Set(true,"");return true;
            }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException)
            {progress?.Report(new(true,false,"La demande n’a pas pu être écrite : vérifie l’accès au dossier des journaux puis réessaie."));return false;}
        }
    }
    public void ThrowIfRequested()=>Token.ThrowIfCancellationRequested();
    public string BindWorker(string directory)
    {
        lock(gate)
        {
            ThrowIfRequested();Directory.CreateDirectory(directory);
            requestPath=Path.Combine(directory,"Cancel-"+Guid.NewGuid().ToString("N")+".request");
            Set(true,"Annulation possible au prochain point d’arrêt sûr. Une copie ou un traitement d’image déjà commencé doit se terminer.");
            return requestPath;
        }
    }
    public async Task<T> TrackAsync<T>(Task<T> task)
    {
        while(!task.IsCompleted)
        {
            ReadBoundary();await Task.WhenAny(task,Task.Delay(150));
        }
        ReadBoundary();return await task;
    }
    private void ReadBoundary()
    {
        lock(gate)
        {
            if(requestPath==null)return;
            try
            {
                string path=requestPath+".state.json";
                if(!File.Exists(path)||new FileInfo(path).Length>8192)return;
                using var json=JsonDocument.Parse(File.ReadAllText(path));
                if(json.RootElement.GetProperty("State").GetString()=="Locked")
                    Set(false,"Cette phase doit aller jusqu’au bout : "+json.RootElement.GetProperty("Reason").GetString()+
                        (requested?" La demande peut être arrivée après le dernier point d’arrêt ; le résultat final fait foi.":""));
            }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or System.Collections.Generic.KeyNotFoundException){}
        }
    }
    public void Dispose(){Lock("Opération terminée. Consulte le résultat affiché.");source.Dispose();}
}
