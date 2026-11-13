using System.Diagnostics;
using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;
string root=args.Length>1?args[1]:Path.Combine(Path.GetTempPath(),"Bastos-Resume-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
if(args.FirstOrDefault()=="--child")
{
 var runner=new ProcessExecutionService();
 var engine=new VerifiedOperationService(root,(_,values)=>{
  var a=values.ToArray();string id=a[Array.IndexOf(a,"-OperationId")+1];
  return runner.RunAsync(Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(root,"fixture.ps1")}.Concat(a),timeoutMinutes:1,onStarted:(pid,started)=>{
   File.WriteAllText(Path.Combine(root,"Operations",id+".process.json"),JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,ProcessId=pid,StartedUtc=started}));
  });
 },(_,_,_)=>{});
 await engine.RunAsync("Fixture fermeture","fixture",Array.Empty<string>(),_=>Task.FromResult(new OperationVerification(true,"fixture",Array.Empty<OperationCheck>())),resumeIntent:new("RufusDownload"));return;
}
int count=0,calls=0;
void Check(bool ok,string name){if(!ok)throw new Exception(name);count++;Console.WriteLine("OK : "+name);}
var history=new OperationHistoryService(root);Directory.CreateDirectory(history.DirectoryPath);
OperationHistoryEntry Fixture(string kind="RufusDownload",OperationState state=OperationState.Running,bool uncertain=false)
{
 string id=Guid.NewGuid().ToString("N"),file=Path.Combine(history.DirectoryPath,id+".operation.json");
 var result=new OperationResult{OperationId=id,Name="Fixture",State=state,StartedUtc=DateTime.UtcNow,OwnerProcessId=999999,OwnerProcessStartedUtc=DateTime.UtcNow,
  ExecutionStarted=true,ProcessStopped=true,ActionCompletionUnconfirmed=uncertain,ResumeIntent=new(kind),WorkerReportPath="https://malicious.invalid/run.exe"};
 File.WriteAllText(file,JsonSerializer.Serialize(result));
 File.WriteAllText(Path.Combine(history.DirectoryPath,id+".worker.json"),JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,Success=true}));
 return new(result,file);
}
void Receipt(OperationHistoryEntry e,string? id=null,DateTime? started=null)=>File.WriteAllText(Path.Combine(history.DirectoryPath,e.Reference+".process.json"),JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id??e.Reference,ProcessId=888888,StartedUtc=started??DateTime.UtcNow}));
Task<OperationVerification> Verify(OperationResumeIntent intent,JsonElement payload){calls++;return Task.FromResult(new OperationVerification(true,"Fichiers relus",new[]{new OperationCheck("Artefact relu",true,"fixture")}));}
OperationResumeService Service(bool? owner=false,bool? worker=false,bool? busy=false)=>new(root,Verify,(pid,_)=>pid==999999?owner:worker,_=>busy);
var old=Fixture("UnknownCommand");Check(!(await Service().ReviewAsync(old)).Verified&&calls==0,"Type inconnu jamais rejoue");
var running=Fixture();Receipt(running);
Check(!(await Service(owner:true).ReviewAsync(running)).Verified&&calls==0,"Ancien Bastos encore actif bloque le controle");
Check(!(await Service(owner:null).ReviewAsync(running)).Verified&&calls==0,"Etat du lanceur inconnu bloque le controle");
Check(!(await Service(worker:true).ReviewAsync(running)).Verified&&calls==0,"Worker encore actif ne peut etre declare termine");
Check(!(await Service(worker:null).ReviewAsync(running)).Verified&&calls==0,"Etat du worker inaccessible bloque le controle");
var noReceipt=Fixture();Check(!(await Service().ReviewAsync(noReceipt)).Verified&&calls==0,"Suivi interrompu sans identite worker reste incertain");
Receipt(noReceipt,id:"wrong");Check(!(await Service().ReviewAsync(noReceipt)).Verified&&calls==0,"Recu d un autre worker refuse");
Receipt(noReceipt,started:default(DateTime));Check(!(await Service().ReviewAsync(noReceipt)).Verified&&calls==0,"Date du recu absente refusee");
Check(!(await Service(busy:true).ReviewAsync(running)).Verified&&calls==0,"Outil enfant actif bloque le controle");
Check(!(await Service(busy:null).ReviewAsync(running)).Verified&&calls==0,"Outil enfant inaccessible reste incertain");
var external=Fixture(uncertain:true);Receipt(external);Check(!(await Service().ReviewAsync(external)).Verified&&calls==0,"Parent arrete ne confirme pas un installateur externe non confirme");
string before=File.ReadAllText(running.ReportPath);
var positive=await Service().ReviewAsync(running);
Check(positive.Verified&&calls==1&&positive.Checks.Single().Passed,"Worker termine et artefact relu permettent de proposer la suite");
Check(File.ReadAllText(running.ReportPath)==before&&File.Exists(Path.Combine(history.DirectoryPath,running.Reference+".resume.json")),"Controle separe ne reecrit jamais le resultat initial");
Check(new OperationResumeService(root,Verify,(_,_)=>false,_=>false).ReadLastReview(running)?.Verified==true,"Nouvelle instance retrouve le dernier controle apres fermeture");
var failedCheck=new OperationResumeService(root,(_,_)=>Task.FromResult(new OperationVerification(false,"Fichier modifié",Array.Empty<OperationCheck>())),(_,_)=>false,_=>false);
Check(!(await failedCheck.ReviewAsync(running)).Verified&&File.ReadAllText(running.ReportPath)==before,"Fichier modifie apres premier controle a nouveau refuse");
var bad=Fixture(state:OperationState.Unconfirmed);
File.WriteAllText(Path.Combine(history.DirectoryPath,bad.Reference+".worker.json"),"{\"SchemaVersion\":1,\"OperationId\":\"wrong\",\"Success\":true}");
int previous=calls;Check(!(await Service().ReviewAsync(bad)).Verified&&calls==previous,"Rapport positif d une autre operation refuse");
File.WriteAllText(Path.Combine(history.DirectoryPath,bad.Reference+".worker.json"),"{\"SchemaVersion\":\"bad\"}");
Check(!(await Service().ReviewAsync(bad)).Verified,"Rapport de mauvais type ne fait pas tomber le Journal");
File.Delete(Path.Combine(history.DirectoryPath,bad.Reference+".worker.json"));
Check((await Service().ReviewAsync(bad)).NextStep.Contains("bilan"),"Rapport absent propose un nouveau bilan sans suppression");
var observedOnly=new OperationResumeService(root,Verify,(_,_)=>false,_=>false,_=>new[]{new OperationCheck("Média",true,"Présence uniquement")});
var observedReview=await observedOnly.ReviewAsync(bad);
Check(!observedReview.Verified&&observedReview.Checks.Single().Passed&&observedReview.Message.Contains("Présence uniquement"),"Presence de fichiers sans rapport ne prouve pas une preparation complete");
var partial=new OperationResumeService(root,(_,_)=>Task.FromResult(new OperationVerification(true,"Partiel",Array.Empty<OperationCheck>(),true)),(_,_)=>false,_=>false);
Check(!(await partial.ReviewAsync(running)).Verified,"Resultat partiel ne devient pas une reprise entierement validee");
// Real interruption: kill only our known fixture launcher, never Bastos or a system tool.
string live=Path.Combine(root,"live");Directory.CreateDirectory(live);
File.WriteAllText(Path.Combine(live,"fixture.ps1"),"param($OperationId,$ResultPath,$ProgressPath)\nStart-Sleep -Seconds 3\n[IO.File]::WriteAllText((Join-Path (Split-Path (Split-Path $ResultPath)) 'artifact.txt'),'fixture complete')\n[IO.File]::WriteAllText($ResultPath,(@{SchemaVersion=1;OperationId=$OperationId;Success=$true}|ConvertTo-Json))\n");
var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};start.ArgumentList.Add("--child");start.ArgumentList.Add(live);
using var child=Process.Start(start)!;
string? receipt=null;
for(int i=0;i<150&&receipt==null;i++){receipt=Directory.Exists(Path.Combine(live,"Operations"))?Directory.GetFiles(Path.Combine(live,"Operations"),"*.process.json").FirstOrDefault():null;await Task.Delay(30);}
if(receipt==null)throw new Exception("Fixture worker not launched");
child.Kill();await child.WaitForExitAsync();
var liveHistory=new OperationHistoryService(live);var interrupted=liveHistory.Read().Entries.Single();string originalBytes=File.ReadAllText(interrupted.ReportPath);
Check(interrupted.Result.ResumeIntent?.Kind=="RufusDownload","Intention de reprise persistee avant la fermeture reelle");
var afterRestart=new OperationResumeService(live,(_,_)=>Task.FromResult(new OperationVerification(File.ReadAllText(Path.Combine(live,"artifact.txt"))=="fixture complete","Fichier de la tentative retrouvé",Array.Empty<OperationCheck>())),toolBusy:_=>false);
Check(!(await afterRestart.ReviewAsync(interrupted)).Verified,"Fermeture reelle du lanceur : worker autonome encore actif detecte");
int duplicateLaunches=0;
var reopenedEngine=new VerifiedOperationService(live,(_,_)=>{duplicateLaunches++;return Task.FromResult(new CommandResult(false,1,"","fixture"));},(_,_,_)=>{});
var blocked=await reopenedEngine.RunAsync("Fixture fermeture","fixture",Array.Empty<string>(),_=>Task.FromResult(new OperationVerification(true,"",Array.Empty<OperationCheck>())));
Check(blocked.ErrorCode=="OPERATION_BUSY"&&duplicateLaunches==0,"Nouveau Bastos bloque une seconde execution pendant le worker orphelin");
for(int i=0;i<200;i++){var review=await afterRestart.ReviewAsync(interrupted);if(review.Verified)break;await Task.Delay(50);}
Check((await afterRestart.ReviewAsync(interrupted)).Verified&&File.ReadAllText(interrupted.ReportPath)==originalBytes,"Apres fin reelle du worker : controle repris et rapport original intact");
await reopenedEngine.RunAsync("Fixture fermeture","fixture",Array.Empty<string>(),_=>Task.FromResult(new OperationVerification(true,"",Array.Empty<OperationCheck>())));
Check(duplicateLaunches==1,"Apres fin du worker le verrou intersession autorise une nouvelle tentative explicite");
string corrupt=Path.Combine(root,"corrupt-lock");Directory.CreateDirectory(Path.Combine(corrupt,"Operations"));
string key=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("worker|fixture|[]")));
string corruptLease=Path.Combine(corrupt,"Operations",key+".lease.json");File.WriteAllText(corruptLease,"{broken");int invoked=0;
var guarded=new VerifiedOperationService(corrupt,(_,_)=>{invoked++;throw new Exception();},(_,_,_)=>{});
Check((await guarded.RunAsync("Fixture","fixture",Array.Empty<string>(),_=>throw new Exception())).ErrorCode=="OPERATION_BUSY"&&invoked==0,"Verrou endommage bloque le lancement sans tomber en erreur non geree");
File.WriteAllText(corruptLease,"{\"OperationId\":\"../outside\"}");
Check((await guarded.RunAsync("Fixture","fixture",Array.Empty<string>(),_=>throw new Exception())).ErrorCode=="OPERATION_BUSY"&&invoked==0,"Identite de verrou non conforme ne devient pas un chemin externe");
Console.WriteLine($"PASS : {count} controles reprise ; fermeture d un lanceur fixture et worker PowerShell inoffensif reels, aucune installation.");
