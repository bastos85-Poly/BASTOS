using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;

int count=0;
void Check(bool value,string message){if(!value)throw new Exception(message);count++;Console.WriteLine("OK : "+message);}
void Refuse(Action action,string code,string message){WorkerIntegrityException? failure=null;try{action();}catch(WorkerIntegrityException ex){failure=ex;}Check(failure?.Code==code,message);}
string root=Path.Combine(Path.GetTempPath(),"Bastos-Integrity-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
string main=Path.Combine(root,"Main.ps1"),module=Path.Combine(root,"Common.psm1"),nested=Path.Combine(root,"Nested.cmd"),sentinel=Path.Combine(root,"ShouldRun.txt");
File.WriteAllText(main,"[IO.File]::WriteAllText('"+sentinel.Replace("'","''")+"','ran')");File.WriteAllText(module,"# module fixture");File.WriteAllText(nested,"@rem fixture");
var original=new[]{main,module,nested}.ToDictionary(p=>p,p=>File.ReadAllBytes(p));
byte[] Catalog(params string[] paths)=>JsonSerializer.SerializeToUtf8Bytes(new{Schema=1,Files=paths.Select(path=>new{Path=Path.GetFileName(path),Sha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)))})});
byte[] catalog=Catalog(main,module,nested);var guard=new WorkerIntegrityService(root,catalog);
using(var lease=guard.Acquire("Main.ps1")){
    Check(lease.CheckedFiles==3,"Script, module et script secondaire verifies");
    bool writeBlocked=false,deleteBlocked=false;try{File.AppendAllText(module,"tamper");}catch(IOException){writeBlocked=true;}try{File.Delete(main);}catch(IOException){deleteBlocked=true;}
    Check(writeBlocked&&deleteBlocked,"Remplacement et ecriture bloques pendant le suivi");
}
// A real harmless PowerShell launch follows a successful check.
using(var lease=guard.Acquire("Main.ps1")){
    var run=await new ProcessExecutionService().RunAsync(Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe"),new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",main});
    Check(run.Success&&File.ReadAllText(sentinel)=="ran","Script inoffensif reel lance apres controle conforme");
}File.Delete(sentinel);
File.AppendAllText(module,"changed");Refuse(()=>guard.Acquire("Main.ps1"),"ENGINE_FILE_CHANGED","Module modifie refuse");Check(!File.Exists(sentinel),"Aucun effet du script lors du refus");File.WriteAllBytes(module,original[module]);
File.Delete(nested);Refuse(()=>guard.Acquire("Main.ps1"),"ENGINE_FILE_MISSING","Script secondaire absent refuse");File.WriteAllBytes(nested,original[nested]);
using(var writer=new FileStream(module,FileMode.Open,FileAccess.Write,FileShare.Read))Refuse(()=>guard.Acquire("Main.ps1"),"ENGINE_FILE_UNREADABLE","Fichier ouvert en ecriture refuse");
Refuse(()=>guard.Acquire("../Main.ps1"),"ENGINE_FILE_UNLISTED","Chemin hors moteur refuse");Refuse(()=>guard.Acquire("Other.ps1"),"ENGINE_FILE_UNLISTED","Script non repertorie refuse");
Refuse(()=>new WorkerIntegrityService(root,Encoding.UTF8.GetBytes("{}")),"ENGINE_CATALOG_INVALID","Catalogue incomplet refuse");
foreach(var files in new[]{new[]{new{Path="..\\Escape.ps1",Sha256=new string('A',64)}},new[]{new{Path="Main.ps1",Sha256="bad"}},new[]{new{Path="Main.ps1",Sha256=new string('A',64)},new{Path="main.ps1",Sha256=new string('A',64)}}})
    Refuse(()=>new WorkerIntegrityService(root,JsonSerializer.SerializeToUtf8Bytes(new{Schema=1,Files=files})),"ENGINE_CATALOG_INVALID","Entree de catalogue invalide refusee");
File.Delete(module);File.CreateSymbolicLink(module,main);Refuse(()=>guard.Acquire("Main.ps1"),"ENGINE_LINK_REFUSED","Module redirige refuse");File.Delete(module);File.WriteAllBytes(module,original[module]);
string linked=Path.Combine(root,"Linked");Directory.CreateSymbolicLink(linked,root);Refuse(()=>new WorkerIntegrityService(linked,catalog).Acquire("Main.ps1"),"ENGINE_LINK_REFUSED","Dossier moteur redirige refuse");Directory.Delete(linked);
using(var lease=guard.Acquire("Main.ps1"))Check(lease.CheckedFiles==3,"Tous les verrous liberes apres un refus");
// Production entry point and embedded baseline, with an isolated copy of the real engine.
string app=Path.Combine(root,"Application");Directory.CreateDirectory(app);
using var baseline=JsonDocument.Parse(File.ReadAllBytes(Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_SOURCE")!,"Assets","EngineIntegrity.json")));
var paths=new AppPaths(app,Path.Combine(root,"Data"));
foreach(var entry in baseline.RootElement.GetProperty("Files").EnumerateArray()){
    string relative=entry.GetProperty("Path").GetString()!,dest=Path.Combine(app,relative);Directory.CreateDirectory(Path.GetDirectoryName(dest)!);File.Copy(Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_RUNTIME")!,relative),dest);
}
var timer=Stopwatch.StartNew();using(var lease=new WorkerIntegrityService(app).Acquire("Initialize-BASTOS-Recovery.ps1"))Check(lease.CheckedFiles==baseline.RootElement.GetProperty("Files").GetArrayLength(),"Catalogue embarque verifie sur le moteur reel copie");Console.WriteLine("Controle complet (ms) : "+timer.ElapsedMilliseconds);
string worker=Path.Combine(app,"Initialize-BASTOS-Recovery.ps1");byte[] workerOriginal=File.ReadAllBytes(worker);
File.WriteAllText(worker,"[IO.File]::WriteAllText('"+sentinel.Replace("'","''")+"','unexpected')");
File.WriteAllText(Path.Combine(app,"BASTOS-App-Manifest.json"),JsonSerializer.Serialize(new{Files=new[]{new{Path="Initialize-BASTOS-Recovery.ps1",Sha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(worker)))}}}));
File.WriteAllText(Path.Combine(app,"BASTOS-Build.json"),"{\"AppManifestSha256\":\"forged\"}");
var runner=new ProcessExecutionService();var log=new OperationLogService(paths);var workers=new PowerShellWorkerService(paths,runner,log);
var invalidName=await workers.RunAsync("../Main.ps1",Array.Empty<string>());Check(invalidName.ExecutionBlocked&&invalidName.ErrorCode=="ENGINE_FILE_UNLISTED","Entree invalide indique aussi un lancement bloque");
var blocked=await workers.RunAsync("Initialize-BASTOS-Recovery.ps1",Array.Empty<string>());
Check(!blocked.Success&&blocked.ExecutionBlocked&&blocked.ErrorCode=="ENGINE_FILE_CHANGED"&&!File.Exists(sentinel),"Vrai lanceur bloque avant PID et effets, meme avec manifeste externe remplace");
Check(blocked.Error.Contains("Initialize-BASTOS-Recovery.ps1"),"Erreur indique precisement le fichier divergent");
var verified=new VerifiedOperationService(paths.LogRoot,(script,args)=>workers.RunAsync(script,args),(_,_,_)=>{});
var operation=await verified.RunAsync("Fixture blocage", "Initialize-BASTOS-Recovery.ps1", Array.Empty<string>(),_=>throw new Exception("Verifier must not run"));
Check(operation.State==OperationState.Failed&&operation.ErrorCode=="ENGINE_FILE_CHANGED"&&operation.ExecutionStarted==false,"Journal indique lancement bloque et execution non engagee");
Check(!File.Exists(Path.Combine(paths.LogRoot,"Operations",operation.OperationId+".process.json"))&&!File.Exists(operation.WorkerReportPath),"Aucun recu PID ni faux rapport worker sur refus");
Check(operation.Checks.Count==1&&operation.Guidance.NextStep.Contains("même version"),"Controle et consigne de reparation dans le journal");
File.WriteAllBytes(worker,workerOriginal);using(var lease=new WorkerIntegrityService(app).Acquire("Initialize-BASTOS-Recovery.ps1"))Check(lease.CheckedFiles==baseline.RootElement.GetProperty("Files").GetArrayLength(),"Reparation de la fixture retablit le controle sans reinitialiser la confiance");
Console.WriteLine($"PASS : {count} controles integrite, aucun script sensible execute. Fixtures : {root}");
