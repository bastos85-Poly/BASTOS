using System.Text.Json;
using Bastos.Native.Services;
using Bastos.Native.Models;
string root=Path.Combine(Path.GetTempPath(),"Bastos-Cancel-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
int count=0;void Check(bool value,string name){if(!value)throw new Exception(name);count++;Console.WriteLine("OK : "+name);}
var states=new List<CancellationStatus>();
using(var control=new OperationCancellation(new Sink(s=>states.Add(s))))
{
 control.Lock("Installer en cours");Check(!control.Request(),"Installation verrouillee ne produit aucune demande");
 control.AllowRead();Check(control.Request()&&control.Token.IsCancellationRequested,"Lecture reversible annulable");
 Check(!control.Request(),"Double demande ignoree");
 try{control.BindWorker(root);throw new Exception("bind after cancel");}catch(OperationCanceledException){Check(true,"Annulation prealable empeche le lancement suivant");}
}
using(var control=new OperationCancellation(new Sink(s=>states.Add(s))))
{
 string file=control.BindWorker(root);Check(control.Request()&&File.Exists(file),"Demande cooperative ecrite pour ce worker");
 await File.WriteAllTextAsync(file+".state.json",JsonSerializer.Serialize(new{State="Locked",Reason="Ecritures disque"}));
 await control.TrackAsync(Task.FromResult(0));Check(!states.Last().CanRequest&&states.Last().Requested&&states.Last().Message.Contains("résultat final"),"Demande tardive distinguee de l annulation confirmee");
}
using(var control=new OperationCancellation(new Sink(s=>states.Add(s))))
{
 string file=control.BindWorker(root);await File.WriteAllTextAsync(file+".state.json","{broken");await control.TrackAsync(Task.FromResult(1));
 Check(control.Request(),"Statut incomplet ne fait pas tomber le suivi ni ne tue le processus");
}
using(var control=new OperationCancellation(new Sink(s=>states.Add(s))))
{
 string file=control.BindWorker(root);await File.WriteAllTextAsync(file+".state.json","{\"State\":\"Locked\",\"Reason\":\"Publication\"}");
 await control.TrackAsync(Task.FromResult(0));Check(!control.Request()&&!File.Exists(file),"Publication finale verrouillee ne cree pas de demande");
}
async Task<OperationResult> Run(bool? cleanup,string scope="IsoBuildCheckpoint",bool stopped=true,bool reported=true)
{
 var engine=new VerifiedOperationService(Path.Combine(root,Guid.NewGuid().ToString("N")),async(_,args)=>{
  var a=args.ToArray();string id=a[Array.IndexOf(a,"-OperationId")+1],path=a[Array.IndexOf(a,"-ResultPath")+1];
  var report=new Dictionary<string,object?>{{"SchemaVersion",1},{"OperationId",id},{"Success",false},{"Cancelled",reported},{"CancellationScope",scope}};
  if(cleanup!=null)report["CancellationCleanupVerified"]=cleanup;
  if(!reported)report["ErrorCode"]="CANCELLATION_CLEANUP_UNCONFIRMED";
  await File.WriteAllTextAsync(path,JsonSerializer.Serialize(report));return new CommandResult(false,reported?2:1,"",""){ProcessStopped=stopped};
 },(_,_,_)=>{});
 return await engine.RunAsync("Simulation","fixture.ps1",Array.Empty<string>(),_=>throw new Exception("Verification must not run"));
}
Check((await Run(true)).State==OperationState.Cancelled,"ISO annulee uniquement avec nettoyage confirme");
var recovery=await Run(true,"RecoveryBeforeWrites");Check(recovery.State==OperationState.Cancelled&&recovery.ErrorCode=="RECOVERY_CANCELLED"&&recovery.UserMessage.Contains("avant les écritures"),"Annulation Recovery distinguee d une ISO annulee");
Check((await Run(false)).State==OperationState.Unconfirmed,"Nettoyage echoue reste non confirme");
Check((await Run(null)).State==OperationState.Unconfirmed,"Ancien rapport sans preuve de nettoyage reste non confirme");
Check((await Run(true,"UnknownScope")).State==OperationState.Unconfirmed,"Point d arret inconnu refuse");
Check((await Run(true,stopped:false)).State==OperationState.Unconfirmed,"Processus potentiellement actif jamais marque annule");
Check((await Run(false,reported:false)).ErrorCode=="CANCELLATION_CLEANUP_UNCONFIRMED","Echec de nettoyage expose un conseil adapte");
using(var token=new CancellationTokenSource())
{
 token.Cancel();
 try{await WindowsDownloadCatalog.RefreshAsync(Array.Empty<WindowsDownloadChoice>(),token.Token);throw new Exception("Catalogue must cancel");}
 catch(OperationCanceledException){Check(true,"Catalogue preannule arrete avant toute requete reseau");}
}
Console.WriteLine($"PASS : {count} controles annulation C# ; aucun outil systeme execute.");
sealed class Sink(Action<CancellationStatus> send):IProgress<CancellationStatus>{public void Report(CancellationStatus value)=>send(value);}
