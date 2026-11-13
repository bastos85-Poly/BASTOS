using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

int count=0;
void Check(bool value,string name){if(!value)throw new Exception(name);count++;Console.WriteLine("OK : "+name);}
void Refuse(Action action,string name){bool refused=false;try{action();}catch(Exception ex)when(ex is IOException or InvalidDataException or ArgumentException or UnauthorizedAccessException){refused=true;}Check(refused,name);}
string root=Path.Combine(Path.GetTempPath(),"Bastos-Export-Tests-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);string logs=Path.Combine(root,"Logs"),operations=Path.Combine(logs,"Operations");Directory.CreateDirectory(operations);
string selected=Guid.NewGuid().ToString("N"),guid="deadbeef-1234-4321-9876-123456789abc",hex=new('b',64);
var redactor=new DiagnosticRedactor(new[]{"Alicia","ALICIA-PC","DOMAIN"});
var service=new DiagnosticExportService(logs,"7.120.28","10.0.26200.1",redactor);
string sensitive="Compte local : FutureAccount\nNom du PC : FUTURE-PC\nsecret=UniquePrivateSecret\npassword: UniquePassword\nAuthorization: Bearer abc123\nC:\\Users\\Alicia\\Documents\\prive.txt\n\\\\serveur\\partage\\private.dat\nhttps://user:pass@example.org/?token=secret\ncontact alicia@example.org\n192.168.19.28 2001:db8::1234 aa:bb:cc:dd:ee:ff\nS-1-5-21-100-200-300-1000\n"+guid+"\n"+hex+"\nAAAAA-BBBBB-CCCCC-DDDDD-EEEEE\nAlicia sur ALICIA-PC";
for(int index=0;index<25;index++){
    string id=index==0?selected:Guid.NewGuid().ToString("N");
    var result=new OperationResult{OperationId=id,Name="Préparation Alicia "+index,State=OperationState.Failed,StartedUtc=DateTime.UtcNow.AddMinutes(-index),EndedUtc=DateTime.UtcNow.AddMinutes(-index),
        ExecutionKind="Alicia",ErrorCode="RECOVERY_PREPARATION_FAILED",Message=sensitive,Phase="Copie C:\\Users\\Alicia\\prive.iso",TechnicalDetail=sensitive,
        OwnerProcessId=12345,BootStamp="SENSITIVE_BOOT_STAMP",JournalPath="C:\\secret.json",WorkerReportPath="C:\\private-worker.json",ResumeIntent=new("RecoveryPreparation","C:\\private.iso","SECRET_OPTIONS"),
        Checks=new[]{new OperationCheck("Fichier ISO",false,"Erreur code 5\n"+sensitive),new OperationCheck("Nom du PC",false,"Demande : FUTURE-PC"),new OperationCheck("Compte local actif",false,"Demande : FutureAccount")}};
    string path=Path.Combine(operations,id+".operation.json");File.WriteAllText(path,JsonSerializer.Serialize(result));File.SetLastWriteTimeUtc(path,DateTime.UtcNow.AddMinutes(-index));
}
File.WriteAllText(Path.Combine(operations,selected+".worker.json"),"SECRET_WORKER_DO_NOT_SHARE");
File.WriteAllText(Path.Combine(logs,"BASTOS-Native.log"),"SECRET_LEGACY_DO_NOT_SHARE");
string invalid=Path.Combine(operations,Guid.NewGuid().ToString("N")+".operation.json");File.WriteAllText(invalid,"{invalid");File.SetLastWriteTimeUtc(invalid,DateTime.UtcNow.AddDays(-1));
var original=Directory.GetFiles(operations).ToDictionary(p=>p,p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))));
var basic=service.Prepare(selected,false,false);
Check(basic.Operations==1&&basic.Documents.Count==3&&!basic.Details,"Resume selectionne limite a trois fichiers");
Check(basic.Skipped==1,"Rapport corrompu signale sans bloquer l export");
string basicText=string.Join("\n",basic.Documents.Select(d=>d.Content));
foreach(string secret in new[]{"Alicia","ALICIA-PC","FutureAccount","FUTURE-PC",selected,"secret.json","SECRET_OPTIONS","SECRET_WORKER_DO_NOT_SHARE","SECRET_LEGACY_DO_NOT_SHARE","SENSITIVE_BOOT_STAMP","192.168.19.28",guid,hex,"alicia@example.org"})
    Check(!basicText.Contains(secret,StringComparison.OrdinalIgnoreCase),"Resume sans donnee privee : "+secret);
using(var json=JsonDocument.Parse(basic.Documents.Single(d=>d.Name=="Diagnostic.json").Content)){
    var op=json.RootElement.GetProperty("Operations")[0];Check(op.GetProperty("Code").GetString()=="RECOVERY_PREPARATION_FAILED"&&op.GetProperty("Etat").GetString()=="Failed","Codes et resultat conserves");
    Check(!op.TryGetProperty("Details",out _)&&op.GetProperty("Controles").GetInt32()==3,"Textes libres absents et compte des controles conserve");
}
var detailed=service.Prepare(selected,false,true);string detailJson=detailed.Documents.Single(d=>d.Name=="Diagnostic.json").Content;
foreach(string secret in new[]{"Alicia","ALICIA-PC","FutureAccount","FUTURE-PC","UniquePrivateSecret","UniquePassword","abc123","prive.txt","private.dat","example.org","192.168.19.28","2001:db8","aa:bb:cc","S-1-5-21",guid,hex,"AAAAA-BBBBB"})
    Check(!detailJson.Contains(secret,StringComparison.OrdinalIgnoreCase),"Details masques : "+secret);
Check(detailJson.Contains("Erreur code 5"),"Detail technique non personnel conserve");
Check(detailed.Preview.Contains("peut contenir une information personnelle"),"Limite du masquage clairement indiquee");
string zipPath=Path.Combine(root,"Diagnostic.zip");service.Export(detailed,zipPath);
using(var zip=ZipFile.OpenRead(zipPath)){
    Check(zip.Entries.Count==3,"Archive ne contient que les trois fichiers annonces");
    foreach(var document in detailed.Documents){using var stream=zip.GetEntry(document.Name)!.Open();using var reader=new StreamReader(stream,Encoding.UTF8);Check(reader.ReadToEnd()==document.Content,"Archive identique a l apercu : "+document.Name);}
}
using(var manifest=JsonDocument.Parse(detailed.Documents.Single(d=>d.Name=="Manifeste.json").Content))foreach(var item in manifest.RootElement.GetProperty("Fichiers").EnumerateArray()){
    var document=detailed.Documents.Single(d=>d.Name==item.GetProperty("Nom").GetString());Check(document.Sha256==item.GetProperty("SHA256").GetString()&&document.Bytes==item.GetProperty("Octets").GetInt32(),"Manifeste des contenus masques coherent : "+document.Name);
}
var recent=service.Prepare(null,true,false);Check(recent.Operations==20,"Historique limite aux 20 derniers rapports");
Refuse(()=>service.Prepare(null,false,false),"Selection absente refusee");
Refuse(()=>service.Prepare("../../secret",false,true),"Selection hors journal refusee");
Refuse(()=>service.Prepare(Guid.NewGuid().ToString("N"),false,false),"Selection disparue sans repli silencieux vers tout l historique");
byte[] beforeZip=File.ReadAllBytes(zipPath);Refuse(()=>service.Export(basic,zipPath),"Archive existante jamais ecrasee");Check(beforeZip.SequenceEqual(File.ReadAllBytes(zipPath)),"Archive existante intacte");
Refuse(()=>service.Export(basic,Path.Combine(root,"Bad.ps1")),"Extension executable refusee");
Refuse(()=>service.Export(basic,"\\\\server\\share\\diagnostic.zip"),"Destination reseau refusee");
Refuse(()=>service.Export(basic,Path.Combine(root,"Missing","Test.zip")),"Dossier disparu signale");
Check(!Directory.EnumerateFiles(root,"*.tmp").Any(),"Aucun ZIP temporaire restant");
var unknown=JsonSerializer.Deserialize<OperationResult>(File.ReadAllText(Path.Combine(operations,selected+".operation.json")))!;
File.WriteAllText(Path.Combine(operations,selected+".operation.json"),JsonSerializer.Serialize(unknown with{ErrorCode="PRIVATE_ERROR_SECRET",ResumeIntent=new("PRIVATE_CATEGORY_SECRET")}));
var unknownPackage=service.Prepare(selected,false,false);Check(!unknownPackage.Preview.Contains("PRIVATE_ERROR_SECRET")&&!unknownPackage.Preview.Contains("PRIVATE_CATEGORY_SECRET")&&unknownPackage.Preview.Contains("CODE_NON_REPERTORIE"),"Codes et categories inconnus non recopies");
Check(!new DiagnosticExportService(logs,"PRIVATE_VERSION_SECRET","PRIVATE_OS_SECRET").Prepare(selected,false,false).Preview.Contains("PRIVATE_"),"Metadonnees de version filtrees");
File.WriteAllText(Path.Combine(operations,selected+".operation.json"),JsonSerializer.Serialize(unknown));
Check(redactor.Clean(new string('A',129*1024)).Contains("trop volumineux"),"Texte trop volumineux retire avant masquage");
Check(redactor.Clean("Informations utiles\n"+new string('A',5000)).Length<1300,"Texte exporte borne");
string link=Path.Combine(root,"LinkedReports");Directory.CreateSymbolicLink(link,logs);
try{Refuse(()=>new DiagnosticExportService(link,"7.120.28","10.0").Prepare(selected,false,false),"Dossier de rapports redirige refuse");}
finally{Directory.Delete(link);}
string outLink=Path.Combine(root,"LinkedOutput");Directory.CreateSymbolicLink(outLink,root);
try{Refuse(()=>service.Export(basic,Path.Combine(outLink,"Forbidden.zip")),"Destination redirigee refusee");}
finally{Directory.Delete(outLink);}
// Changes after preview do not silently enter the archive.
File.WriteAllText(Path.Combine(operations,selected+".operation.json"),"{changed after preview}");
service.Export(basic,Path.Combine(root,"Frozen.zip"));using(var zip=ZipFile.OpenRead(Path.Combine(root,"Frozen.zip"))){using var reader=new StreamReader(zip.GetEntry("Diagnostic.json")!.Open());Check(reader.ReadToEnd()==basic.Documents.Single(d=>d.Name=="Diagnostic.json").Content,"Export fige malgre modification du journal");}
foreach(var pair in original.Where(p=>!p.Key.EndsWith(selected+".operation.json")))Check(pair.Value==Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(pair.Key))),"Rapport original intact : "+Path.GetFileName(pair.Key));
// View-model privacy changes invalidate the previous snapshot immediately.
var vm=new DiagnosticExportViewModel(service,null);await vm.PrepareAsync();Check(vm.CanExport&&vm.Preview.Length>0,"Apercu du modele prepare");
vm.IncludeDetails=true;Check(!vm.CanExport&&vm.Preview.Length==0&&vm.Files.Count==0,"Changement de confidentialite invalide l ancien apercu");await vm.PrepareAsync();Check(vm.CanExport&&vm.Files.Count==3,"Nouvel apercu requis avant export detaille");
await vm.ExportAsync(zipPath);Check(vm.Status.Contains("Export non créé")&&vm.CanExport,"Erreur destination expliquee et apercu conserve pour reessayer");
var missingVm=new DiagnosticExportViewModel(service,Guid.NewGuid().ToString("N"));await missingVm.PrepareAsync();Check(!missingVm.CanExport&&missingVm.Preview==""&&missingVm.Status.Contains("Aperçu indisponible"),"Echec de preparation bloque le bouton export");
Check(vm.ExportDisabledReason=="","Export disponible sans indication obsolete");
vm.IncludeDetails=false;Check(!vm.CanExport&&vm.ExportDisabledReason.Contains("aperçu"),"Nouvel apercu requis explique sans conserver une autorisation obsolete");
Check(missingVm.ExportDisabledReason.Contains("aperçu"),"Bouton export indisponible explique apres echec");
Console.WriteLine($"PASS : {count} controles export et confidentialite. Fixtures isolees : {root}");
