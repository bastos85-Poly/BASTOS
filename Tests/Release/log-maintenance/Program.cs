using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

int count=0;
void Check(bool value,string message){if(!value)throw new Exception(message);count++;Console.WriteLine("OK : "+message);}
void Refuse(Action action,string message){bool refused=false;try{action();}catch(Exception ex)when(ex is IOException or InvalidDataException or ArgumentException){refused=true;}Check(refused,message);}
string root=Path.Combine(Path.GetTempPath(),"Bastos-Maintenance-"+Guid.NewGuid().ToString("N")),logs=Path.Combine(root,"Logs"),ops=Path.Combine(logs,"Operations");Directory.CreateDirectory(ops);
DateTime clock=DateTime.UtcNow;var service=new LogMaintenanceService(logs,(pid,_)=>pid==7?true:pid==8?null:false,()=>clock);
string Write(string name,string content,int days){string path=Path.Combine(ops,name);File.WriteAllText(path,content);File.SetLastWriteTimeUtc(path,clock.AddDays(-days));return path;}
string Operation(int days=61,OperationState state=OperationState.Succeeded,OperationResumeIntent? resume=null,bool restart=false,bool stopped=true,bool unconfirmed=false,int owner=9,int receipt=9){
    string id=Guid.NewGuid().ToString("N");var result=new OperationResult{OperationId=id,Name="Opération fixture",State=state,StartedUtc=clock.AddDays(-days).AddMinutes(-1),EndedUtc=clock.AddDays(-days),ResumeIntent=resume,RestartRequired=restart,ProcessStopped=stopped,ActionCompletionUnconfirmed=unconfirmed,OwnerProcessId=owner,OwnerProcessStartedUtc=clock.AddDays(-days).AddHours(-1)};
    Write(id+".operation.json",JsonSerializer.Serialize(result),days);Write(id+".worker.json",JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,Success=true}),days);Write(id+".progress.txt","100\tTerminé",days);
    Write(id+".process.json",JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,ProcessId=receipt,StartedUtc=clock.AddDays(-days).AddHours(-1)}),days);return id;
}
for(int index=0;index<200;index++)Operation(1);
string candidate=Operation(),failed=Operation(state:OperationState.Failed),running=Operation(state:OperationState.Running),partial=Operation(state:OperationState.Partial),resume=Operation(resume:new("RecoveryPreparation")),restart=Operation(restart:true),unconfirmed=Operation(unconfirmed:true),notStopped=Operation(stopped:false),ownerAlive=Operation(owner:7),ownerUnknown=Operation(owner:8),workerAlive=Operation(receipt:7),workerUnknown=Operation(receipt:8),leased=Operation();
Write(new string('a',64)+".lease.json",JsonSerializer.Serialize(new{OperationId=leased}),61);
string malformed=Guid.NewGuid().ToString("N");Write(malformed+".operation.json","{bad",61);string orphan=Guid.NewGuid().ToString("N");Write(orphan+".worker.json.tmp","orphan",61);
Write(candidate+".operation.json.tmp","abandoned temporary",61);
string unknown=Path.Combine(logs,"Recovery-Options-private.json");File.WriteAllText(unknown,"keep account options");File.SetLastWriteTimeUtc(unknown,clock.AddDays(-100));
string active=Path.Combine(logs,"BASTOS-Native.log");File.WriteAllText(active,"active log");File.SetLastWriteTimeUtc(active,clock.AddDays(-100));
string Archive(int days,bool error=false,int? stampDays=null){string path=Path.Combine(logs,"BASTOS-Native-Archive-"+clock.AddDays(-(stampDays??days)).ToString("yyyyMMdd'T'HHmmssfff")+"-"+Guid.NewGuid().ToString("N")+".log");File.WriteAllText(path,error?"date\tERROR\tkeep diagnostic":"date\tINFO\tarchive");File.SetLastWriteTimeUtc(path,clock.AddDays(-days));return path;}
string oldArchive=Archive(61),errorArchive=Archive(61,true),freshArchive=Archive(1),newNameOldTime=Archive(61,stampDays:1);
var plan=service.Scan();Check(plan.Complete&&plan.Items.Count>200,"Analyse complete et inventaire borne aux dossiers prevus");
var old=plan.Items.Single(i=>i.Id==candidate);Check(old.Eligible&&old.Files.Count==5,"Ancienne reussite et temporaire associe proposes ensemble");
Check(plan.Items.Count(i=>i.Eligible)==2,"Seulement ancienne reussite et archive INFO ancienne nettoyables");
foreach(string id in new[]{failed,running,partial,resume,restart,unconfirmed,notStopped,ownerAlive,ownerUnknown,workerAlive,workerUnknown,leased,malformed,orphan})Check(!plan.Items.Single(i=>i.Id==id).Eligible,"Operation protegee : "+id);
Check(plan.Items.Count(i=>i.Reason.StartsWith("Parmi les 200"))==200,"Deux cents operations les plus recentes protegees");
Check(plan.Items.Single(i=>i.Files.Any(f=>f.RelativePath==Path.GetFileName(errorArchive))).Reason.Contains("erreurs"),"Archives d erreurs conservees");
Check(!plan.Items.Single(i=>i.Files.Any(f=>f.RelativePath==Path.GetFileName(newNameOldTime))).Eligible,"Archive nouvellement creee conservee meme si ancienne date de fichier");
Check(plan.TotalBytes==plan.CleanableBytes+plan.ProtectedBytes,"Tailles analysees et protegees coherentes");
var hashes=Directory.GetFiles(ops).Where(p=>!Path.GetFileName(p).StartsWith(candidate)).ToDictionary(p=>p,p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))));
// Frozen snapshot: a content change with identical timestamp and length is detected.
string progress=Path.Combine(ops,candidate+".progress.txt");byte[] progressBytes=File.ReadAllBytes(progress);File.WriteAllBytes(progress,progressBytes.Select((b,i)=>i==0?(byte)'9':b).ToArray());File.SetLastWriteTimeUtc(progress,old.Files.Single(f=>f.RelativePath.EndsWith(".progress.txt")).ModifiedUtc);
var changed=service.Clean(plan,new[]{candidate});Check(changed.DeletedFiles==0&&changed.SkippedItems==1&&File.Exists(progress),"Contenu modifie apres apercu conserve, meme taille et date");File.WriteAllBytes(progress,progressBytes);File.SetLastWriteTimeUtc(progress,clock.AddDays(-61));
plan=service.Scan();using(var held=new FileStream(Path.Combine(ops,candidate+".operation.json"),FileMode.Open,FileAccess.Read,FileShare.Read)){
    var locked=service.Clean(plan,new[]{candidate});Check(locked.DeletedFiles==0&&old.Files.All(f=>File.Exists(Path.Combine(logs,f.RelativePath))),"Groupe entier conserve si un seul fichier est utilise");
}
plan=service.Scan();string newLease=Write(new string('b',64)+".lease.json",JsonSerializer.Serialize(new{OperationId=candidate}),61);
var newlyNeeded=service.Clean(plan,new[]{candidate});Check(newlyNeeded.DeletedFiles==0&&newlyNeeded.SkippedItems==1,"Nouvelle reference de suivi apres apercu preserve la tentative");File.Delete(newLease);
string badLease=Write(new string('c',64)+".lease.json","{unreadable",61);Check(!service.Scan().Items.Single(i=>i.Id==candidate).Eligible,"Suivi illisible preserve les groupes d operations");File.Delete(badLease);
using(var heldLease=new FileStream(Path.Combine(ops,new string('a',64)+".lease.json"),FileMode.Open,FileAccess.ReadWrite,FileShare.None))Check(!service.Scan().Items.Single(i=>i.Id==candidate).Eligible,"Suivi occupe par un lancement preserve les groupes");
string changedState=Operation();var statePlan=service.Scan();string statePath=Path.Combine(ops,changedState+".operation.json");var changedResult=JsonSerializer.Deserialize<OperationResult>(File.ReadAllBytes(statePath))!;File.WriteAllText(statePath,JsonSerializer.Serialize(changedResult with{State=OperationState.Failed}));File.SetLastWriteTimeUtc(statePath,clock.AddDays(-61));Check(service.Clean(statePlan,new[]{changedState}).DeletedFiles==0,"Etat devenu erreur apres apercu protege le rapport");
plan=service.Scan();clock=clock.AddMinutes(16);Refuse(()=>service.Clean(plan,new[]{candidate}),"Apercu expire refuse avant suppression");clock=clock.AddMinutes(-16);
plan=service.Scan();var deleted=service.Clean(plan,new[]{candidate});Check(deleted.DeletedFiles==5&&old.Files.All(f=>!File.Exists(Path.Combine(logs,f.RelativePath))),"Suppression reelle par handles des seuls cinq fichiers approuves");
Check(deleted.DeletedBytes==old.Bytes&&File.Exists(deleted.ReportPath),"Bilan local et taille exacte des fichiers retires");using(var report=JsonDocument.Parse(File.ReadAllBytes(deleted.ReportPath)))Check(report.RootElement.GetProperty("State").GetString()=="Completed"&&report.RootElement.GetProperty("DeletedFiles").GetArrayLength()==5,"Bilan enregistre les suppressions confirmees");
bool originalsIntact=hashes.All(entry=>{
    if(!File.Exists(entry.Key))return false;
    string hash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(entry.Key)));
    return hash==entry.Value;
});
Check(originalsIntact,"Tous les rapports utiles conserves octet pour octet");
plan=service.Scan();var archiveItem=plan.Items.Single(i=>i.Files.Any(f=>f.RelativePath==Path.GetFileName(oldArchive)));
var archived=service.Clean(plan,new[]{archiveItem.Id});
// Windows may briefly inspect a newly created fixture. The engine must preserve
// locked files; retry only this positive fixture with a new preview, never force it.
var retryUntil=DateTime.UtcNow.AddSeconds(3);
while(archived.DeletedFiles==0 && archived.SkippedItems==1 && archived.Issues.Count==1 && (archived.Issues[0].Contains("code 32") || archived.Issues[0].Contains("code 33")) && DateTime.UtcNow<retryUntil)
{
    await Task.Delay(100);
    plan=service.Scan();
    archived=service.Clean(plan,new[]{archiveItem.Id});
}Check(archived.DeletedFiles==1&&!File.Exists(oldArchive)&&File.Exists(errorArchive)&&File.Exists(freshArchive)&&File.Exists(active)&&File.Exists(unknown),"Seule archive INFO ancienne selectionnee retiree");
string longRoot=Path.Combine(root,new string('p',80),new string('q',80));Directory.CreateDirectory(longRoot);
string longArchive=Path.Combine(longRoot,Path.GetFileName(oldArchive));File.WriteAllText(longArchive,"INFO long path");File.SetLastWriteTimeUtc(longArchive,clock.AddDays(-61));
var longService=new LogMaintenanceService(longRoot,(_,_)=>false,()=>clock);var longPlan=longService.Scan();
Check(longArchive.Length>260&&longPlan.Complete&&longPlan.Items.Single().Eligible&&longService.Clean(longPlan,new[]{longPlan.Items.Single().Id}).DeletedFiles==1&&!File.Exists(longArchive),"Archive locale au dela de MAX_PATH supprimee par handle verifie");
string outside=Path.Combine(root,"outside.txt");File.WriteAllText(outside,"keep");var fake=plan with{Items=new[]{new MaintenanceItem("escape","escape","",true,new[]{new MaintenanceFile("..\\outside.txt",4,clock,"fake")})}};
Check(service.Clean(fake,new[]{"escape"}).DeletedFiles==0&&File.ReadAllText(outside)=="keep","Plan forge ne peut pas viser un fichier hors perimetre");
Refuse(()=>service.Clean(plan,Array.Empty<string>()),"Selection vide refusee");Refuse(()=>service.Scan(0),"Retention inferieure a trente jours refusee");
string link=Path.Combine(root,"LinkedLogs");Directory.CreateSymbolicLink(link,logs);Refuse(()=>new LogMaintenanceService(link).Scan(),"Dossier de journaux redirige refuse");Directory.Delete(link);
string linkedArchive=Archive(61);File.Delete(linkedArchive);File.CreateSymbolicLink(linkedArchive,outside);var linkedPlan=service.Scan();Check(!linkedPlan.Items.Single(i=>i.Files.Any(f=>f.RelativePath==Path.GetFileName(linkedArchive))).Eligible&&File.ReadAllText(outside)=="keep","Fichier redirige conserve sans toucher sa cible");File.Delete(linkedArchive);
var vm=new LogMaintenanceViewModel(service);await vm.AnalyzeAsync();Check(!vm.CanClean&&vm.Rows.Count>0,"Modele n autorise rien sans candidat");Archive(61);await vm.AnalyzeAsync();Check(vm.CanClean,"Bouton active avec apercu et candidat coche");foreach(var row in vm.Rows.Where(r=>r.Eligible))row.Selected=false;Check(!vm.CanClean,"Decocher tous les candidats desactive le nettoyage");vm.KeepDays=90;Check(!vm.CanClean&&vm.Rows.Count==0&&vm.Total=="—","Changement de retention invalide l apercu");
// Non-destructive rotation and bounded reading of the active native log.
var paths=new AppPaths(root,Path.Combine(root,"RotationData"));Directory.CreateDirectory(paths.LogRoot);byte[] large=Encoding.UTF8.GetBytes(new string('x',5*1024*1024)+"\noriginal");File.WriteAllBytes(paths.NativeLog,large);
var logger=new OperationLogService(paths);logger.Write("Test","new message");string rotated=Directory.GetFiles(paths.LogRoot,"BASTOS-Native-Archive-*.log").Single();Check(File.ReadAllBytes(rotated).SequenceEqual(large)&&File.ReadAllText(paths.NativeLog).Contains("new message"),"Rotation preserve integralement le journal ancien sans le tronquer");Check(logger.ReadLatest(1).Contains("new message"),"Lecture du journal courant conservee apres rotation");
Parallel.For(0,50,i=>new OperationLogService(paths).Write("Parallel","message "+i));Check(File.ReadAllLines(paths.NativeLog).Length==51,"Ecritures concurrentes serialisees sans perte de lignes");
var busyPaths=new AppPaths(root,Path.Combine(root,"BusyRotationData"));Directory.CreateDirectory(busyPaths.LogRoot);File.WriteAllBytes(busyPaths.NativeLog,large);var busyLogger=new OperationLogService(busyPaths);
using(var reader=new FileStream(busyPaths.NativeLog,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))busyLogger.Write("Test","held reader");Check(Directory.GetFiles(busyPaths.LogRoot,"BASTOS-Native-Archive-*.log").Length==0&&File.ReadAllText(busyPaths.NativeLog).Contains("held reader"),"Rotation differee si lecteur ouvert, contenu conserve et message ajoute");
string auditRoot=Path.Combine(root,"AuditBlocked");Directory.CreateDirectory(auditRoot);string oldAuditArchive=Path.Combine(auditRoot,Path.GetFileName(errorArchive).Replace(Path.GetFileName(errorArchive),"BASTOS-Native-Archive-"+clock.AddDays(-61).ToString("yyyyMMdd'T'HHmmssfff")+"-"+Guid.NewGuid().ToString("N")+".log"));File.WriteAllText(oldAuditArchive,"INFO old");File.SetLastWriteTimeUtc(oldAuditArchive,clock.AddDays(-61));File.WriteAllText(Path.Combine(auditRoot,"Maintenance"),"blocks audit directory");var auditService=new LogMaintenanceService(auditRoot,(_,_)=>false,()=>clock);var auditPlan=auditService.Scan();Refuse(()=>auditService.Clean(auditPlan,auditPlan.Items.Where(i=>i.Eligible).Select(i=>i.Id).ToArray()),"Bilan impossible a creer refuse avant toute suppression");Check(File.Exists(oldAuditArchive),"Fichier conserve si bilan non enregistrable");
Check(vm.CleanDisabledReason.Contains("analyse"),"Nettoyage indisponible explique apres invalidation de l apercu");
await vm.AnalyzeAsync();
if(vm.CanClean){Check(vm.CleanDisabledReason=="","Aucun message de blocage apres analyse valide");foreach(var row in vm.Rows.Where(r=>r.Eligible))row.Selected=false;Check(vm.CleanDisabledReason.Contains("Coche"),"Selection nettoyable vide expliquee");}
else Check(vm.CleanDisabledReason.Contains("Aucun élément"),"Absence de candidat expliquee sans suggerer une suppression protegee");
Console.WriteLine($"PASS : {count} controles maintenance et rotation ; suppressions uniquement dans les fixtures : {root}");
