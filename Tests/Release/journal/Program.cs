using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
var root = Path.Combine(Path.GetTempPath(), "BASTOS-Journal-Tests-" + Guid.NewGuid().ToString("N"));
var service = new OperationHistoryService(root);
int checks = 0;
void Check(bool ok, string label) { if (!ok) throw new Exception(label); checks++; Console.WriteLine("OK " + label); }
Check(service.Read().Entries.Count == 0, "Dossier absent");
Directory.CreateDirectory(service.DirectoryPath);
string Write(OperationState state, int minutes = 0) {
 var id = Guid.NewGuid().ToString("N");
 File.WriteAllText(Path.Combine(service.DirectoryPath, id + ".operation.json"), JsonSerializer.Serialize(new OperationResult {
 OperationId = id, Name = "Test " + state, State = state, StartedUtc = DateTime.UtcNow.AddMinutes(minutes),
 Message = "Explication " + state, ErrorCode = "EXEMPLE", WorkerReportPath = "https://example.com/unsafe", JournalPath = "C:/unsafe.exe",
 Checks = new[] {new OperationCheck("Vérification", true, "preuve")}})); return id;
}
var succeeded = Write(OperationState.Succeeded, 10);
foreach (var state in Enum.GetValues<OperationState>().Where(s => s != OperationState.Succeeded)) Write(state);
var snapshot = service.Read();
Check(snapshot.Entries.Count == 7, "Sept états relus");
Check(snapshot.Entries.First().Reference == succeeded, "Tri chronologique");
foreach (var e in snapshot.Entries) { Check(!string.IsNullOrEmpty(e.Status), "Libellé " + e.Result.State); Check(e.Checks.Single().Contains("preuve"), "Preuve " + e.Result.State); }
Check(snapshot.Entries.Single(e => e.Result.State == OperationState.Running).FollowUp.Contains("ancien"), "Fin absente explicitée");
Check(snapshot.Entries.Count(e => e.NeedsAttention) == 6, "Partiels et échecs à vérifier");
Check(service.ResolveReport(snapshot.Entries.First()).StartsWith(service.DirectoryPath), "Chemin JSON ignoré à l'ouverture");
try { service.ResolveReport(snapshot.Entries.First() with { ReportPath = "C:/unsafe.exe" }); throw new Exception("Path accepted"); } catch(IOException) { checks++; }
File.WriteAllText(Path.Combine(service.DirectoryPath, "broken.operation.json"), "{");
File.WriteAllText(Path.Combine(service.DirectoryPath, Guid.NewGuid().ToString("N") + ".operation.json"), "{\"OperationId\":\"mismatch\",\"StartedUtc\":\"2026-10-15T10:00:00Z\"}");
File.WriteAllText(Path.Combine(service.DirectoryPath, "large.operation.json"), new string('x', 4*1024*1024+1));
Check(service.Read().Skipped == 3 && service.Read().Entries.Count == 7, "Rapports corrompus isolés");
Check(service.Read(2).Entries.Count + service.Read(2).Skipped == 2, "Nombre de lectures borné");
File.Delete(snapshot.Entries.First().ReportPath);
try { service.ResolveReport(snapshot.Entries.First()); throw new Exception("Missing file accepted"); } catch(IOException) { checks++; }
var paths = new AppPaths();
var actual = new OperationHistoryService(paths.LogRoot).Read();
Check(actual.Entries.Count > 0, "Historique réel lisible sans modification");
var vm = new JournalViewModel(paths);
await vm.RefreshAsync();
Check(vm.Entries.Count == actual.Entries.Count, "Chargement du modèle de page");
vm.Filter = "À vérifier"; Check(vm.Entries.All(e => e.NeedsAttention), "Filtre à vérifier");
vm.Filter = "Réussies"; Check(vm.Entries.All(e => !e.NeedsAttention), "Filtre réussies");
vm.Filter = "Toutes";
var first = vm.Entries.First(); vm.Search = first.Reference;
Check(vm.Entries.Count == 1 && vm.Selected?.Reference == first.Reference, "Recherche par référence");
vm.Search = "impossible-" + Guid.NewGuid(); Check(vm.Entries.Count == 0 && !vm.HasSelection && !vm.OpenReportCommand.CanExecute(null), "Recherche vide et bouton désactivé");
vm.Search = ""; await vm.RefreshAsync(); Check(vm.Entries.Count == actual.Entries.Count, "Actualisation après filtrage");
var isolatedVm = new JournalViewModel(paths,service);
var restartId=Guid.NewGuid().ToString("N");
File.WriteAllText(Path.Combine(service.DirectoryPath,restartId+".operation.json"),JsonSerializer.Serialize(new OperationResult{OperationId=restartId,Name="Fixture redémarrage",StartedUtc=DateTime.UtcNow,State=OperationState.Failed,RestartRequired=true,BootStamp=OperationTrackingService.CurrentBootStamp??""}));
await isolatedVm.RefreshAsync();
Check(isolatedVm.HasRecoveryNotice && isolatedVm.RecoveryNotice.Contains("1 redémarrage"),"Rappel de redémarrage au chargement");
isolatedVm.Filter="À vérifier";
Check(isolatedVm.Entries.Any(e=>e.Reference==restartId),"Rappel accessible dans les opérations à vérifier");
Check(OperationTrackingService.Evaluate(new OperationResult{State=OperationState.Failed,ErrorCode="ADK_RESTART_REQUIRED"},null).RestartPending,"Ancienne demande ADK reconnue sans inventer une date de démarrage");
var guidanceId=Guid.NewGuid().ToString("N");
File.WriteAllText(Path.Combine(service.DirectoryPath,guidanceId+".operation.json"),JsonSerializer.Serialize(new OperationResult{OperationId=guidanceId,Name="Fixture conseils",StartedUtc=DateTime.UtcNow,State=OperationState.Failed,ErrorCode="RECOVERY_PROFILE_FAILED",Message="MotUniqueOriginalInchange"}));
await isolatedVm.RefreshAsync();isolatedVm.Filter="Toutes";isolatedVm.Search="MotUniqueOriginalInchange";
Check(isolatedVm.Entries.Count==1&&isolatedVm.Selected?.Reference==guidanceId,"Recherche du message original conservee apres reformulation");
isolatedVm.Search="Resélectionne";
Check(isolatedVm.Entries.Any(e=>e.Reference==guidanceId),"Recherche des nouvelles actions conseillees");
// Disabled feedback follows the same predicate, including false-to-false reason changes.
bool allowed=false;string reason="Choisis un élément.";int invoked=0,notifications=0;
var guarded=new Bastos.Native.Infrastructure.RelayCommand(()=>invoked++,()=>allowed,()=>reason);
guarded.PropertyChanged+=(_,e)=>{if(e.PropertyName=="DisabledReason")notifications++;};
guarded.Execute(null);Check(invoked==0&&guarded.DisabledReason==reason,"Commande synchrone refuse vraiment l execution indisponible");
reason="Attends la fin du chargement.";guarded.RaiseCanExecuteChanged();
Check(notifications==1&&guarded.DisabledReason==reason,"Raison actualisee meme si la commande reste desactivee");
allowed=true;guarded.RaiseCanExecuteChanged();guarded.Execute(null);
Check(invoked==1&&guarded.DisabledReason=="","Explication disparait lorsque le prerequis est satisfait");
var signal=new TaskCompletionSource();int asyncInvoked=0;
var asynchronous=new Bastos.Native.Infrastructure.AsyncRelayCommand(async()=>{asyncInvoked++;await signal.Task;},()=>allowed,()=>"Choisis un élément.");
allowed=false;await asynchronous.ExecuteAsync();Check(asyncInvoked==0&&asynchronous.DisabledReason.Contains("Choisis"),"Commande asynchrone bloquee conserve une action utile");
allowed=true;var pending=asynchronous.ExecuteAsync();
Check(!asynchronous.CanExecute(null)&&asynchronous.DisabledReason.Contains("en cours"),"Action en cours expliquee et seconde tentative refusee");
await asynchronous.ExecuteAsync();Check(asyncInvoked==1,"Aucun double lancement pendant l attente");
signal.SetResult();await pending;
Check(asynchronous.CanExecute(null)&&asynchronous.DisabledReason=="","Disponibilite et message retablis apres execution");
var exceptional=new Bastos.Native.Infrastructure.AsyncRelayCommand(()=>throw new InvalidOperationException("fixture"));
try{await exceptional.ExecuteAsync();}catch(InvalidOperationException){}
Check(exceptional.CanExecute(null)&&exceptional.DisabledReason=="","Erreur ne laisse pas la commande marquee en cours");
Console.WriteLine($"PASS {checks} contrôles Journal ; {actual.Entries.Count} opérations réelles lues.");
