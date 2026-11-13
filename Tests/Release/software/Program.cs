using System.Text.Json;
using System.Text.Json.Nodes;
using Bastos.Native.Services;
int count=0;
void Check(bool condition,string name){if(!condition)throw new Exception(name);count++;Console.WriteLine("OK : "+name);}
JsonObject Fixture()=>JsonSerializer.SerializeToNode(new{Schema=2,UserSid="test-user",Success=true,Requested=1,Items=new[]{new{Name="Open-Shell",Id="Open-Shell.Open-Shell-Menu",Success=true,Verified=true,Status="Installed",ExitCode=0}}})!.AsObject();
SoftwareInstallationSummary Read(JsonObject root,bool process=true)=>SoftwareInstallationReport.Read(JsonSerializer.SerializeToUtf8Bytes(root),new[]{"Open-Shell.Open-Shell-Menu"},process,"test-user");
Check(Read(Fixture()).Success,"Presence verifiee et processus termine donnent un succes");
foreach(string status in new[]{"Installed","AlreadyPresent"}){var r=Fixture();r["Items"]![0]!["Status"]=status;Check(Read(r).Success,"Statut confirme : "+status);}
Check(!Read(Fixture(),false).Success,"Processus en echec interdit le succes");
foreach(string property in new[]{"Verified","Success"}){var r=Fixture();r["Items"]![0]![property]=false;Check(!Read(r).Success,"Preuve absente : "+property);}
foreach(string property in new[]{"Verified","Status","Items","Requested","Schema"}){var r=Fixture();if(property is "Verified" or "Status")r["Items"]![0]!.AsObject().Remove(property);else r.Remove(property);Check(!Read(r).Success,"Champ manquant refuse : "+property);}
var wrong=Fixture();wrong["Items"]![0]!["Id"]="Vendor.Other";Check(!Read(wrong).Success,"Rapport d un autre logiciel refuse");
var user=Fixture();user["UserSid"]="another-user";Check(!Read(user).Success,"Rapport d un autre compte refuse");
var duplicate=Fixture();duplicate["Items"]!.AsArray().Add(duplicate["Items"]![0]!.DeepClone());Check(!Read(duplicate).Success,"Elements supplementaires refuses");
var cancelled=Fixture();cancelled["Success"]=false;cancelled["Items"]![0]!["Success"]=false;cancelled["Items"]![0]!["Verified"]=false;cancelled["Items"]![0]!["Status"]="Failed";cancelled["Items"]![0]!["ErrorCode"]="ADMIN_CANCELLED";
Check(Read(cancelled).Message.Contains("administrateur annulée")&&Read(cancelled).Message.Contains("Open-Shell"),"Annulation UAC affichee avec le logiciel concerne");
var pending=cancelled.DeepClone().AsObject();pending["Items"]![0]!["ErrorCode"]="INSTALLATION_UNCONFIRMED";Check(Read(pending).Message.Contains("encore travailler"),"Processus non confirme n invite pas a relancer immediatement");
var restart=Fixture();restart["Items"]![0]!["RestartRequired"]=true;Check(Read(restart).Message.Contains("redémarrage"),"Redemarrage demande signale sans le lancer");
var error=Fixture();error["Error"]="Wrong account";Check(!Read(error).Success&&Read(error).Message.Contains("Wrong account"),"Erreur du worker conservee");
Check(!SoftwareInstallationReport.Read("{"u8.ToArray(),new[]{"id"},true).Success,"JSON corrompu sans faux succes");
Check(!SoftwareInstallationReport.Read(JsonSerializer.SerializeToUtf8Bytes(new{Schema=2,Items=Array.Empty<object>(),Requested=0,Success=true}),Array.Empty<string>(),true).Success,"Selection vide sans faux succes");
foreach(string path in args){using var d=JsonDocument.Parse(File.ReadAllBytes(path));var ids=d.RootElement.GetProperty("Items").EnumerateArray().Select(i=>i.GetProperty("Id").GetString()!).ToArray();var result=SoftwareInstallationReport.Read(File.ReadAllBytes(path),ids,d.RootElement.GetProperty("Success").GetBoolean());Check(result.Success==Path.GetFileName(path).Contains("Positive"),"Rapport worker reel : "+Path.GetFileName(path));}
Console.WriteLine($"PASS : {count} controles des rapports logiciels.");
