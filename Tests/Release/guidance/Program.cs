using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;
var root=Path.Combine(Path.GetTempPath(),"Bastos-Guidance-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
int count=0;
void Check(bool condition,string label){if(!condition)throw new Exception(label);Console.WriteLine("OK : "+label);count++;}
var failure=new OperationResult {OperationId=Guid.NewGuid().ToString("N"),StartedUtc=DateTime.UtcNow,
 State=OperationState.Failed,ExecutionStarted=true,ErrorCode="RECOVERY_PREPARATION_FAILED",Phase="Copie du média",Message="Ancien message",TechnicalDetail="fixture stack trace"};
Check(failure.UserMessage.Contains("préparation Recovery")&&failure.UserMessage.Contains("À faire")&&failure.UserMessage.Contains("bilan"),"Erreur Recovery et action concrete dans le retour du service");
Check(!failure.UserMessage.Contains("fixture stack trace"),"Detail technique absent du retour utilisateur");
Check(failure.Guidance.Effects.Contains("Copie du média")&&!failure.Guidance.Effects.Contains("Aucune action"),"Phase atteinte ne prouve ni absence de modification ni retour arriere");
var lateJournal=failure with {ErrorCode="JOURNAL_UNWRITABLE"};
Check(!lateJournal.Guidance.Effects.Contains("Aucune action")&&lateJournal.Guidance.NextStep.Contains("droits"),"Echec tardif du journal ne pretend pas que rien ne s est passe");
Check((lateJournal with{ExecutionStarted=false}).Guidance.Effects.Contains("Aucune action"),"Refus avant execution explicite pour la tentative courante");
foreach(string code in new[]{"RECOVERY_PREPARATION_FAILED","VERIFICATION_FAILED","TIMEOUT_STOPPED","ADMIN_CANCELLED","JOURNAL_UNWRITABLE"})
{
 var uncertain=failure with{ErrorCode=code,ProcessStopped=false};
 Check(uncertain.Guidance.NextStep.Contains("Ne lance pas")&&uncertain.Guidance.Effects.Contains("encore travailler"),"Arret inconnu prioritaire sur le code : "+code);
}
var pending=failure with{State=OperationState.Unconfirmed,ActionCompletionUnconfirmed=true};
Check(pending.Guidance.NextStep.Contains("Ne lance pas"),"Outil externe non confirme ne conseille pas une relance");
var partial=failure with{State=OperationState.Partial,ErrorCode="",Message="3 fichiers supprimés ; 2 conservés."};
Check(partial.Guidance.Effects.Contains("3 fichiers")&&partial.UserMessage.Contains("2 conservés"),"Travail partiel connu conserve dans le message");
var old=JsonSerializer.Deserialize<OperationResult>("{\"State\":\"Failed\",\"Message\":\"Ancien rapport\"}")!;
Check(old.ExecutionStarted==null&&!old.Guidance.Effects.Contains("Aucune action"),"Ancien rapport sans preuve de lancement traite avec prudence");
var entry=new OperationHistoryEntry(failure,"fixture");
Check(entry.TechnicalDetail.Contains("fixture stack trace")&&entry.TechnicalDetail.Contains("Ancien message")&&!entry.Message.Contains("fixture stack trace"),"Journal conserve le message original et le detail a part");
var tracked=entry with{Tracking=new("Fin inconnue","Attendre la fin de cet outil.",ExternalUnconfirmed:true)};
Check(tracked.NextStep=="Attendre la fin de cet outil.","Suivi de l outil prioritaire dans le Journal");
Check((failure with{ErrorCode="DISK_PLAN_CHANGED"}).Guidance.NextStep.Contains("Compte, nom du PC"),"Plan divergent renvoie vers le bon ecran");
Check((failure with{ErrorCode="RECOVERY_DISARM_UNCONFIRMED"}).Guidance.NextStep.Contains("Ne redémarre pas"),"Neutralisation incertaine interdit le conseil de redemarrage manuel");
Check((failure with{ErrorCode="WEBVIEW2_SIGNATURE_INVALID"}).Guidance.NextStep.Contains("Ne lance pas ce fichier"),"Signature invalide ne propose pas de contourner le controle");
Check((failure with{ErrorCode="NEW_UNKNOWN_CODE"}).Guidance.Problem=="Ancien message","Code inconnu conserve l explication du module");
Check((failure with{State=OperationState.Succeeded}).UserMessage=="Ancien message","Succes complet conserve son retour simple");
Check((failure with{RestartRequired=true,ErrorCode="ADK_RESTART_REQUIRED"}).Guidance.NextStep.Contains("ADK"),"Redemarrage ADK avec verification apres redemarrage");
bool evidenceBeforeWorker=false;
var engine=new VerifiedOperationService(root,async(_,args)=>{
 var values=args.ToArray();string id=values[Array.IndexOf(values,"-OperationId")+1];
 var journal=JsonSerializer.Deserialize<OperationResult>(File.ReadAllText(Path.Combine(root,"Operations",id+".operation.json")))!;
 evidenceBeforeWorker=journal.ExecutionStarted==true;
 await File.WriteAllTextAsync(values[Array.IndexOf(values,"-ResultPath")+1],JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,Success=false,ErrorCode="RECOVERY_PROFILE_FAILED",Message="fixture"}));
 return new CommandResult(false,1,"", "fixture raw stderr");
},(_,_,_)=>{});
var actual=await engine.RunAsync("Fixture Recovery","fixture.ps1",Array.Empty<string>(),_=>throw new Exception("Verifier must not run"));
Check(evidenceBeforeWorker&&actual.ExecutionStarted==true,"Possibilite de lancement enregistree avant le delegate");
var persisted=new OperationHistoryService(root).Read().Entries.Single();
Check(persisted.Message.Contains("profil")&&persisted.NextStep.Contains("Resélectionne")&&persisted.TechnicalDetail.Contains("fixture raw stderr"),"Echec reel du moteur relu depuis le Journal avec conseil et details separes");
var blockedRoot=Path.Combine(root,"not-a-directory");File.WriteAllText(blockedRoot,"fixture");bool invoked=false;
var blocked=new VerifiedOperationService(blockedRoot,(_,_)=>{invoked=true;throw new Exception();},(_,_,_)=>{});
var noAction=await blocked.RunAsync("fixture","fixture",Array.Empty<string>(),_=>throw new Exception());
Check(!invoked&&noAction.ExecutionStarted==false&&noAction.Guidance.Effects.Contains("Aucune action"),"Journal inaccessible bloque vraiment le lancement et l explique");
var presentation=MessagePresentation.From(failure.UserMessage);
Check(presentation.Summary==failure.Guidance.Problem && presentation.NextStep==failure.Guidance.NextStep && presentation.Effects==failure.Guidance.Effects,
 "Presentation separe resultat, action et effets sans supprimer les preuves");
Check(!presentation.Summary.Contains(failure.OperationId) && presentation.Details.Contains(failure.OperationId),"Reference disponible dans les details seulement");
var appended=MessagePresentation.From(failure.UserMessage+" Aucun redémarrage demandé. Le démarrage n’a pas été neutralisé.");
Check(appended.NextStep.Contains("Aucun redémarrage demandé")&&appended.NextStep.Contains("pas été neutralisé"),"Avertissements ajoutes apres la reference toujours visibles");
var unknown="Erreur inconnue. Ne redémarre pas.\nD:\\Recovery\\profil.json\nCode : 42";
Check(MessagePresentation.From(unknown).Summary==unknown,"Texte non structure conserve integralement, meme avec chemin ou code");
Check(MessagePresentation.From("Rapport\nÀ faire : attendre\nÉtat : inconnu").NextStep=="","Format incomplet ou inverse conserve visible");
Check(MessagePresentation.From(failure.UserMessage,"stderr complet").Details.Contains("stderr complet"),"Diagnostic explicite consultable avec la reference");
var active=MessagePresentation.From((failure with {ProcessStopped=false}).UserMessage);
Check(active.NextStep.Contains("Ne lance pas")&&active.Effects.Contains("encore travailler"),"Consignes de fin incertaine visibles hors des details");
Check(MessagePresentation.From(partial.UserMessage).Effects.Contains("2 conservés"),"Bilan partiel visible hors des details");
foreach(string code in new[]{"RECOVERY_BOOT_FAILED","RECOVERY_DISARM_UNCONFIRMED","RECOVERY_RESTART_FAILED"})
 Check((failure with{ErrorCode=code,RestartRequired=true}).Guidance.NextStep.Contains("Ne redémarre pas"),"Redemarrage demande ne masque pas la consigne Recovery : "+code);
var integrity=failure with{ErrorCode="ENGINE_FILE_CHANGED",Message="Fichier modifié : D:\\Application\\script.ps1"};
Check(!integrity.Guidance.Problem.Contains("D:\\")&&new OperationHistoryEntry(integrity,"fixture").TechnicalDetail.Contains(integrity.Message),"Erreur integrite courte, fichier exact conserve dans le Journal");
Console.WriteLine($"PASS : {count} controles des erreurs utiles ; workers simules uniquement.");
