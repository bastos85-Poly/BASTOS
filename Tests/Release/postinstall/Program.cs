using System.Text.Json;
using System.Text.Json.Nodes;
using Bastos.Native.Services;
using Bastos.Native.Models;

int count=0;
void Check(bool value,string text){if(!value)throw new Exception(text);count++;Console.WriteLine("OK : "+text);}
string profile=Guid.NewGuid().ToString(),hash=new('A',64),request=Guid.NewGuid().ToString("N");DateTime started=DateTime.UtcNow.AddSeconds(-1);
string[] ids={"edition","language","region","keyboard","computer","account","shortcut","finalization"};
JsonObject Fixture()=>JsonSerializer.SerializeToNode(new{Schema=1,ProfileId=profile,ProfileSha256=hash,RequestId=request,CheckedUtc=DateTime.UtcNow,MachineGuid=Guid.NewGuid().ToString(),UserSid="S-1-5-21-1-2-3-1001",Checks=ids.Select(id=>new{Id=id,Name=id,Expected="value",Actual="value",Status="Passed",Detail="confirmed"})})!.AsObject();
InstallationReview Parse(JsonObject data)=>InstallationVerificationService.Parse(JsonSerializer.SerializeToUtf8Bytes(data),profile,hash,request,started);
void Refuse(Action<JsonObject> mutate,string text){var data=Fixture();mutate(data);bool refused=false;try{Parse(data);}catch(Exception ex)when(ex is InvalidDataException or IOException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException){refused=true;}Check(refused,text);}
var passed=Parse(Fixture());Check(!passed.Passed&&passed.Checks.Count==9&&passed.Checks[^1].Status=="Unavailable","Ancien bilan conserve ses huit preuves sans confirmer le nettoyage absent");
foreach(string status in new[]{"Mismatch","Unavailable"}){var data=Fixture();data["Checks"]![0]!["Status"]=status;data["Checks"]![0]!["Actual"]="other";var review=Parse(data);Check(!review.Passed&&review.Checks[0].Status==status,"Etat distinct : "+status);}
Refuse(d=>d["ProfileId"]=Guid.NewGuid().ToString(),"Autre profil refuse");
Refuse(d=>d["ProfileSha256"]=new string('B',64),"Profil modifie refuse");
Refuse(d=>d["RequestId"]="old-request","Ancien rapport refuse");
Refuse(d=>d["CheckedUtc"]=DateTime.UtcNow.AddDays(-1),"Rapport ancien refuse");
Refuse(d=>d["CheckedUtc"]=DateTime.UtcNow.AddHours(1),"Date future refusee");
Refuse(d=>d["Schema"]=3,"Schema inconnu refuse");
Refuse(d=>d["MachineGuid"]="","Identite machine manquante refusee");
Refuse(d=>d["UserSid"]="S-1-5-18","Contexte SYSTEM refuse");
Refuse(d=>d["Checks"]!.AsArray().RemoveAt(0),"Controle absent refuse");
Refuse(d=>d["Checks"]![1]!["Id"]="edition","Controle duplique refuse");
Refuse(d=>d["Checks"]![1]!["Status"]="Success","Statut non reconnu refuse");
Refuse(d=>d["Checks"]![1]!["Expected"]="","Succes sans attente refuse");
Refuse(d=>d["Checks"]![1]!["Actual"]="different","Succes contradictoire refuse");
Refuse(d=>d["Checks"]![1]=null,"Controle nul refuse sans exception non geree");
var shuffled=Fixture();shuffled["Checks"]=new JsonArray(shuffled["Checks"]!.AsArray().Reverse().Select(n=>n!.DeepClone()).ToArray());Check(Parse(shuffled).Checks[0].Id=="edition","Ordre du bilan stable");
Check(new OperationResult{State=OperationState.Partial,ErrorCode="INSTALLATION_REVIEW_REQUIRED"}.Guidance.NextStep.Contains("Bilan après réinstallation"),"Erreur dirige vers le bilan utile");
foreach(string file in args){using var actual=JsonDocument.Parse(File.ReadAllBytes(file));var root=actual.RootElement;var review=InstallationVerificationService.Parse(File.ReadAllBytes(file),root.GetProperty("ProfileId").GetString()!,root.GetProperty("ProfileSha256").GetString()!,root.GetProperty("RequestId").GetString()!,root.GetProperty("CheckedUtc").GetDateTime().AddSeconds(-1));Check(root.GetProperty("Schema").GetInt32()==1?!review.Passed&&review.Checks.Count==9:review.Checks.Count==16&&review.Passed==Path.GetFileName(file).Contains("Positive"),"Rapport reel VM accepte avec couverture explicite : "+Path.GetFileName(file));}
string[] extras={"preferredlanguage","privacy","suggestions","onedrive","teams","outlook","copilot","widgets"};
string[] optionNames={"DisableTelemetry","DisableConsumerContent","RemoveOneDrive","RemoveTeams","RemoveOutlook","DisableCopilot","DisableWidgets"};
JsonObject FullFixture(){var data=Fixture();data["Schema"]=2;foreach(string id in extras){string expected=id=="preferredlanguage"?"fr-FR":id=="widgets"?"Configured":"Applied";data["Checks"]!.AsArray().Add(JsonSerializer.SerializeToNode(new{Id=id,Name=id,Expected=expected,Actual=expected,Status="Passed",Detail="verified"}));}return data;}
var fullProfile=new JsonObject{["Schema"]=2,["UILanguage"]="fr-FR",["Options"]=new JsonObject(optionNames.Select(n=>KeyValuePair.Create<string,JsonNode?>(n,JsonValue.Create(true))))};
var full=Parse(FullFixture());Check(full.Passed&&full.Checks.Count==16,"Bilan complet exige les seize controles");
InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(fullProfile),full);
Check(true,"Chaque option du rapport correspond au profil confirme");
foreach(string id in extras){var data=FullFixture();data["Checks"]!.AsArray().RemoveAt(Array.IndexOf(extras,id)+8);bool refused=false;try{Parse(data);}catch(InvalidDataException){refused=true;}Check(refused,"Controle nouveau manquant refuse : "+id);}
foreach(string id in extras){var data=FullFixture();var check=data["Checks"]!.AsArray().Single(c=>c!["Id"]!.GetValue<string>()==id)!;check["Status"]="Unavailable";check["Actual"]="Unknown";Check(!Parse(data).Passed,"Controle non verifie interdit un succes : "+id);}
var skipped=FullFixture();skipped["Checks"]![11]!["Status"]="NotRequested";skipped["Checks"]![11]!["Expected"]="NotRequested";skipped["Checks"]![11]!["Actual"]="NotRequested";
bool skippedSelected=false;try{InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(fullProfile),Parse(skipped));}catch(InvalidDataException){skippedSelected=true;}Check(skippedSelected,"Option OneDrive selectionnee ne peut pas etre omise");
fullProfile["Options"]!["RemoveOneDrive"]=false;InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(fullProfile),Parse(skipped));Check(Parse(skipped).Passed,"Option reellement decochee est distincte d un echec");
var strictProfile=fullProfile.DeepClone().AsObject();strictProfile["Options"]!["RufusExperienceVersion"]="4.15";
var configured=FullFixture();configured["Checks"]![9]!["Expected"]="Configured";configured["Checks"]![9]!["Actual"]="Configured";
foreach(string option in optionNames.Skip(2))strictProfile["Options"]![option]=false;
for(int i=11;i<16;i++){configured["Checks"]![i]!["Expected"]="NotRequested";configured["Checks"]![i]!["Actual"]="NotRequested";configured["Checks"]![i]!["Status"]="NotRequested";}
InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(strictProfile),Parse(configured));Check(Parse(configured).Passed,"Mode Rufus accepte une configuration OOBE explicitement archivee");
bool appliedRefused=false;configured["Checks"]![9]!["Expected"]="Applied";configured["Checks"]![9]!["Actual"]="Applied";
try{InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(strictProfile),Parse(configured));}catch(InvalidDataException){appliedRefused=true;}Check(appliedRefused,"Mode Rufus ne pretend pas mesurer la collecte effective");
var cleanProfile=fullProfile.DeepClone().AsObject();foreach(string option in optionNames)cleanProfile["Options"]![option]=true;cleanProfile["Options"]!["CleanBastosVersion"]="1";
var cleanReport=FullFixture();cleanReport["Checks"]![10]!["Expected"]="Configured";cleanReport["Checks"]![10]!["Actual"]="Configured";
InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(cleanProfile),Parse(cleanReport));Check(Parse(cleanReport).Passed,"Profil propre distingue configuration Demarrer et preuve visuelle");
bool falseVisualProof=false;try{InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(cleanProfile),Parse(FullFixture()));}catch(InvalidDataException){falseVisualProof=true;}Check(falseVisualProof,"Profil propre refuse un bilan qui surestime la verification de Demarrer");
// Regression: widgets report configuration, never visual proof.
foreach(string state in new[]{"Mismatch","Unavailable"}){
 var data=cleanReport.DeepClone().AsObject();data["Checks"]![15]!["Status"]=state;data["Checks"]![15]!["Actual"]="Unknown";
 InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(cleanProfile),Parse(data));
 Check(!Parse(data).Passed,"Widgets non conformes ne deviennent pas un succes : "+state);
}
var overstated=FullFixture();overstated["Checks"]![10]!["Expected"]="Configured";overstated["Checks"]![10]!["Actual"]="Configured";overstated["Checks"]![15]!["Expected"]="Applied";overstated["Checks"]![15]!["Actual"]="Applied";
bool widgetsRefused=false;try{InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(cleanProfile),Parse(overstated));}catch(InvalidDataException){widgetsRefused=true;}
Check(widgetsRefused,"Widgets : preuve visuelle surestimee refusee");
var omitted=cleanReport.DeepClone().AsObject();for(int i=0;i<3;i++)omitted["Checks"]![15]![new[]{"Expected","Actual","Status"}[i]]="NotRequested";
bool omittedRefused=false;try{InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(cleanProfile),Parse(omitted));}catch(InvalidDataException){omittedRefused=true;}Check(omittedRefused,"Widgets selectionnes ne peuvent pas etre omis");
var noWidgets=cleanProfile.DeepClone().AsObject();noWidgets["Options"]!["DisableWidgets"]=false;
InstallationVerificationService.ValidateOptionExpectations(JsonSerializer.SerializeToElement(noWidgets),Parse(omitted));Check(Parse(omitted).Passed,"Widgets decoches acceptes comme non demandes");
string displayRoot=Path.Combine(Path.GetTempPath(),"Bastos-ReviewDisplay-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(displayRoot);
try
{
    string profilePath=Path.Combine(displayRoot,"profile.json"),statePath=Path.Combine(displayRoot,"State");
    InstallationReviewDisplayState State(string identity="windows-1")=>new(statePath,profilePath,()=>identity);
    Check(!State().ShouldShow(),"Aucun bilan automatique sans profil");
    File.WriteAllText(profilePath,"profile-1");
    Check(State().ShouldShow(),"Premiere ouverture propose le bilan");
    var displayed=State().PrepareMarkShown();
    Check(State().ShouldShow(),"Preparer la fenetre ne marque pas un affichage reussi");
    displayed();
    Check(!State().ShouldShow(),"Nouvelle instance conserve le bilan deja affiche");
    displayed();
    Check(!State().ShouldShow(),"Enregistrement repete sans reouverture automatique");
    Check(State("windows-2").ShouldShow(),"Nouvelle installation Windows repropose le bilan");
    File.WriteAllText(profilePath,"profile-2");
    Check(State().ShouldShow(),"Nouveau profil repropose le bilan");
    displayed();
    Check(State().ShouldShow(),"Ancienne fenetre ne masque pas le nouveau profil");
    State().PrepareMarkShown()();
    Check(!State().ShouldShow(),"Bilan partiel ou conforme reste consultable sans repetition automatique");
    string marker=Directory.GetFiles(Path.Combine(statePath,"InstallationReviews"),"*.shown").Last();
    foreach(string file in Directory.GetFiles(Path.Combine(statePath,"InstallationReviews"),"*.shown")) File.WriteAllText(file,"interrupted");
    Check(State().ShouldShow(),"Marqueur incomplet repropose le bilan");
}
finally { Directory.Delete(displayRoot,true); }
if(Environment.GetEnvironmentVariable("BASTOS_REGRESSION_PROFILE") is string realProfile && Environment.GetEnvironmentVariable("BASTOS_REGRESSION_REPORT") is string realReport){
 using var expected=JsonDocument.Parse(File.ReadAllBytes(realProfile));using var report=JsonDocument.Parse(File.ReadAllBytes(realReport));var r=report.RootElement;
 var actual=InstallationVerificationService.Parse(File.ReadAllBytes(realReport),expected.RootElement.GetProperty("ProfileId").GetString()!,Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(realProfile))),r.GetProperty("RequestId").GetString()!,r.GetProperty("CheckedUtc").GetDateTime().AddSeconds(-1));
 InstallationVerificationService.ValidateOptionExpectations(expected.RootElement,actual);Check(actual.Passed,"Rapport reel de reinstallation : seize controles et contrat natif acceptes");
}
Console.WriteLine($"PASS : {count} controles du bilan apres reinstallation.");
