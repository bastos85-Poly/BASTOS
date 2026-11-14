using Bastos.Native.Models;
using Bastos.Native.Services;
using System.Text.Json;
using System.Security.Cryptography;
const long gb=1073741824L;
int count=0;
void Check(bool ok,string message){if(!ok)throw new Exception(message);count++;}
string diskId=Guid.NewGuid().ToString(),partId=Guid.NewGuid().ToString(),hash=new('A',64),iso=@"D:\Windows.iso";
var options=new RufusInstallOptions{EditionIsoPath=iso,EditionIsoSha256=hash,WindowsImageIndex=6,WindowsEditionId="Professional",WindowsImageName="Windows 11 Pro",WindowsUILanguage="fr-FR",DiskSafetySnapshot="fixture",WindowsDiskIdentity=diskId,RecoveryPartitionGuid=partId};
var catalog=new WindowsIsoEditionCatalog(iso,hash,new[]{new WindowsIsoEdition(6,"Windows 11 Pro","Professional"){Languages=new[]{"fr-FR"}}});
var disk=new RecoveryDiskPreview(true,"fixture","D:",partId,diskId,"fixture"){RecoverySizeBytes=40*gb,RecoveryFreeBytes=3*gb,Partitions=new[]{new RecoveryPartitionPreview(5,partId,"D:",40*gb,"CONSERVER")}};
RecoveryPreflight Review(RecoveryDiskPreview d)=>RecoveryPreflightBuilder.Build(iso,9*gb,options,d,catalog,"",false);
Check(Review(disk).Profile.Contains("supprimé automatiquement")&&Review(disk).Profile.Contains("Toutes les données"),"Review warns before confirmation that temporary Recovery is erased after successful installation");
Check(!Review(disk).CanContinue,"Fresh copy still requires ISO plus reserve");
Check(Review(disk with{RecoveryFreeBytes=11*gb}).CanContinue,"Exact fresh-copy threshold accepted");
var reuse=disk with{CacheMode="Reuse",CacheIsoSha256=hash,CacheRequiredFreeBytes=2*gb};
Check(Review(reuse).CanContinue,"Verified existing media accepted with less than ISO size free");
Check(Review(reuse).RequiredFreeBytes==2*gb,"Displayed space follows verified plan");
Check(Review(reuse).Space.Contains("réutilisables"),"Reuse described in review");
Check(Review(reuse with{RecoveryFreeBytes=2*gb}).CanContinue,"Exact reuse reserve accepted");
Check(!Review(reuse with{RecoveryFreeBytes=2*gb-1}).CanContinue,"Reuse still enforces reserve");
var boot=reuse with{CacheMode="Boot",CacheRequiredFreeBytes=3*gb};
Check(Review(boot).CanContinue,"Boot-only space budget accepted");
Check(!Review(boot with{RecoveryFreeBytes=3*gb-1}).CanContinue,"Boot staging budget enforced");
Check(Review(boot).Space.Contains("seul le démarrage"),"Boot-only action described");
foreach(var invalid in new[]{reuse with{CacheIsoSha256=new('B',64)},reuse with{CacheIsoSha256=""},reuse with{CacheMode="Unknown"},reuse with{CacheRequiredFreeBytes=0},reuse with{CacheRequiredFreeBytes=2*gb-1}}){
 Check(!Review(invalid).CanContinue,"Unverified or undersized cache plan cannot bypass full budget");
 Check(Review(invalid).RequiredFreeBytes==11*gb,"Fallback displayed consistently");
}
Check(!Review(reuse with{DiskSnapshot="changed"}).CanContinue,"Reuse never bypasses disk identity");
Check(!Review(reuse with{Partitions=Array.Empty<RecoveryPartitionPreview>()}).CanContinue,"Reuse never bypasses partition detail");
Check(!Review(reuse with{RecoveryFreeBytes=-1}).CanContinue,"Unknown free space stays blocked");
Check(!Review(reuse with{RecoveryFreeBytes=41*gb}).CanContinue,"Inconsistent volume measurements stay blocked");
Check(!Review(reuse with{Success=false}).CanContinue,"Failed storage preview stays blocked");
options.UseCleanBastosInstallation=true;
Check(!options.UseExactRufusExperience && options.DisableTelemetry && options.RemoveOneDrive,"Clean checkbox selects consistent effective settings");
Check(!Review(reuse).CanContinue,"Normal cached image cannot satisfy clean preparation");
Check(Review(reuse with{CacheCleanupProfile="minimal-2"}).CanContinue,"Matching clean image may be reused");
options.UseExactRufusExperience=true;
Check(!options.UseCleanBastosInstallation,"Selecting strict Rufus clears clean mode");
Check(!Review(reuse with{CacheCleanupProfile="minimal-2"}).CanContinue,"Clean cached image cannot satisfy normal preparation");
string temp=Path.Combine(Path.GetTempPath(),"Bastos-CacheVerify-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
try{
 string source=Path.Combine(temp,"source.iso"),root=Path.Combine(temp,"media");Directory.CreateDirectory(Path.Combine(root,"sources"));
 File.WriteAllText(source,"fixture ISO");
 string sourceHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(source)));
 foreach(string name in new[]{"boot","install"})File.WriteAllText(Path.Combine(root,"sources",name+".wim"),"MSWIM fixture "+name);
 string bootHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(root,"sources","boot.wim"))));
 string installHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(root,"sources","install.wim"))));
 string operation=Guid.NewGuid().ToString("N"),bootId=Guid.NewGuid().ToString();
 File.WriteAllText(Path.Combine(root,"BASTOS-ISO.sha256"),sourceHash);File.WriteAllText(Path.Combine(root,"BASTOS-BOOT-ID.txt"),bootId);
 File.WriteAllText(Path.Combine(root,"BASTOS-Recovery-Unattend.xml"),"<unattend/>");
 File.WriteAllText(Path.Combine(root,"BASTOS-RECOVERY-SELECTION.json"),JsonSerializer.Serialize(new{Schema=3,PostInstallMode="WindowsOnly",CurrentWindowsDiskIdentity=diskId,WindowsTargetDiskIdentity=diskId,RecoveryDiskIdentity=diskId,RecoveryPartitionGuid=partId,OperationId=operation}));
 string snapshot=JsonSerializer.Serialize(new{Schema=1,Disks=new{WindowsDisk=new{Guid=diskId},InstallDisk=new{Guid=diskId},TargetDisk=new{Guid=diskId}}});
 var report=JsonSerializer.SerializeToElement(new{OperationId=operation,Action="Provision",IsoSha256=sourceHash,BootId=bootId});
 var probe=JsonSerializer.SerializeToElement(new{SchemaVersion=1,OperationId=operation,Action="InspectResult",Success=true,Root=root,StorageSnapshot=snapshot,RecoveryPartitionGuid=partId,BootId=bootId});
 var expected=new RecoveryExpectation(source,"WindowsOnly",root,ImageIndex:6,EditionId:"Professional");
 async Task<bool> Verify(int schema,int windowsRevision=1,int bootRevision=1,string cleanupProfile=""){
  File.WriteAllText(Path.Combine(root,"BASTOS-MEDIA-STATE.json"),JsonSerializer.Serialize(new{Schema=schema,CleanupProfile=cleanupProfile,WindowsCacheRevision=windowsRevision,BootCacheRevision=bootRevision,PostInstallMode="WindowsOnly",IsoPath=source,IsoSha256=sourceHash,ProImageIndex=6,WindowsEditionId="Professional",InstallWimSanitized=true,BootWimSha256=bootHash,InstallWimSha256=installHash}));
  return (await RecoveryOperationVerifiers.VerifyAsync(expected,report,probe,false)).Valid;
 }
 Check(await Verify(8),"Legacy prepared media still independently verifiable");
 Check(await Verify(9),"New cache schema passes independent verification");
 var requestedKeyboard=expected with{Keyboard="0409:00000409",UiLanguage="fr-FR",UserName="BastOS",ComputerName="BASTOS-PC"};
 string answerPath=Path.Combine(root,"BASTOS-Recovery-Unattend.xml");
 void KeyboardAnswer(string first,string second,string ui="fr-FR",string user="BastOS",string pc="BASTOS-PC")=>File.WriteAllText(answerPath,$"<unattend xmlns=\"urn:schemas-microsoft-com:unattend\"><settings pass=\"windowsPE\"><component><InputLocale>{first}</InputLocale><UILanguage>{ui}</UILanguage></component></settings><settings pass=\"oobeSystem\"><component><InputLocale>{second}</InputLocale><UILanguage>{ui}</UILanguage><ComputerName>{pc}</ComputerName><LocalAccount><Name>{user}</Name></LocalAccount></component></settings></unattend>");
 KeyboardAnswer("040C:00000409","040C:00000409");
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"French Windows with US QWERTY accepts the generated French input-language prefix");
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard with{Keyboard="040C:00000409"},report,probe,false)).Valid,"Already associated input locale remains valid");
 KeyboardAnswer("040C:0000040C","040C:0000040C");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"AZERTY cannot satisfy a QWERTY request");
 KeyboardAnswer("0409:00000409","0409:00000409");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"English input language cannot silently replace the French association");
 KeyboardAnswer("040C:00000409","040C:0000040C");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Conflicting setup and OOBE keyboards remain blocked");
 KeyboardAnswer("040C:00000409","040C:00000409","en-US");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Wrong Windows UI language remains blocked");
 KeyboardAnswer("040C:00000409","040C:00000409",user:"Other");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Wrong account remains blocked");
 KeyboardAnswer("040C:00000409","040C:00000409",pc:"Other-PC");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Wrong computer name remains blocked");
 KeyboardAnswer("040C:00000809","040C:00000809");
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard with{Keyboard="0809:00000809"},report,probe,false)).Valid,"French Windows with UK QWERTY preserves the distinct physical layout");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"UK QWERTY cannot satisfy a US QWERTY request");
 KeyboardAnswer("0409:00000409","0409:00000409","en-US");
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard with{UiLanguage="en-US"},report,probe,false)).Valid,"English Windows with US QWERTY remains valid");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard with{Keyboard="invalid"},report,probe,false)).Valid,"Malformed requested keyboard stays blocked");
 // Actual new account flow: no OOBE LocalAccount, one specialize writer.
 string accountPayload=Path.Combine(root,"sources","$OEM$","$1","ProgramData","BASTOS-ISO");Directory.CreateDirectory(accountPayload);
 string workerPath=Path.Combine(accountPayload,"Initialize-BASTOS-LocalAccount.ps1"),profilePath=Path.Combine(accountPayload,"Installation-Expected.json");
 File.WriteAllText(workerPath,"# harmless account worker fixture, never executed");
 string workerHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(workerPath)));
 var accountProfile=new Dictionary<string,object?>{{"Schema",2},{"AccountProvisioning","SpecializePasswordlessV1"},{"PasswordMode","Empty"},{"UserName","BastOS"},{"ComputerName","BASTOS-PC"},{"UILanguage","fr-FR"},{"KeyboardLayout","040C:00000409"},{"EditionId","Professional"},{"AccountWorkerSha256",workerHash},{"AutoLogonEnabled",true}};
 void SaveAccountProfile()=>File.WriteAllText(profilePath,JsonSerializer.Serialize(accountProfile));
 string specializeXml="""
 <unattend xmlns="urn:schemas-microsoft-com:unattend"><settings pass="specialize"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64"><RunSynchronous><RunSynchronousCommand><Order>1</Order><Path>powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\Initialize-BASTOS-LocalAccount.ps1"</Path><WillReboot>Never</WillReboot></RunSynchronousCommand></RunSynchronous></component><component><ComputerName>BASTOS-PC</ComputerName></component></settings><settings pass="oobeSystem"><component><InputLocale>040C:00000409</InputLocale><UILanguage>fr-FR</UILanguage><AutoLogon><Username>BastOS</Username><Domain>BASTOS-PC</Domain><Enabled>true</Enabled><Password><Value/><PlainText>true</PlainText></Password></AutoLogon></component></settings></unattend>
 """;
 SaveAccountProfile();File.WriteAllText(answerPath,specializeXml);
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Specialize account flow passes without a second OOBE account writer");
 foreach(var pair in new[]{("UserName",(object)"Other"),("ComputerName",(object)"Other-PC"),("KeyboardLayout",(object)"040C:0000040C"),("UILanguage",(object)"en-US"),("EditionId",(object)"Core"),("PasswordMode",(object)"Other"),("AccountProvisioning",(object)"Unknown"),("AccountWorkerSha256",(object)new string('F',64)),("Schema",(object)3)}){
  var previous=accountProfile[pair.Item1];accountProfile[pair.Item1]=pair.Item2;SaveAccountProfile();
  Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Mismatched specialize profile rejected: "+pair.Item1);
  accountProfile[pair.Item1]=previous;SaveAccountProfile();
 }
 File.AppendAllText(workerPath,"# altered");
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Changed account worker rejected");
 File.WriteAllText(workerPath,"# harmless account worker fixture, never executed");
 foreach(var badXml in new[]{specializeXml.Replace("pass=\"specialize\"","pass=\"windowsPE\""),specializeXml.Replace(".ps1\"</Path>",".ps1\" -VerifyOnly</Path>"),specializeXml.Replace("<Username>BastOS</Username>","<Username>Other</Username>"),specializeXml.Replace("<Value/>","<Value>unexpected</Value>"),specializeXml.Replace("</AutoLogon>","</AutoLogon><LocalAccount><Name>BastOS</Name></LocalAccount>")}){
  File.WriteAllText(answerPath,badXml);Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Conflicting writer, pass, invocation or AutoLogon refused");
 }
 File.WriteAllText(answerPath,specializeXml);File.Delete(profilePath);
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Specialize flow without bound account profile refused");
 SaveAccountProfile();
 accountProfile["AutoLogonEnabled"]=false;SaveAccountProfile();
 var noAuto=System.Xml.Linq.XDocument.Parse(specializeXml);noAuto.Descendants().Single(e=>e.Name.LocalName=="AutoLogon").Remove();File.WriteAllText(answerPath,noAuto.ToString());
 Check((await RecoveryOperationVerifiers.VerifyAsync(requestedKeyboard,report,probe,false)).Valid,"Specialize flow supports explicit AutoLogon off");
 Directory.Delete(accountPayload,true);
 File.WriteAllText(answerPath,"<unattend/>");
 Check(!await Verify(9,2),"Unknown Windows cache revision refused by verifier");
 Check(!await Verify(9,1,2),"Unknown boot cache revision refused by verifier");
 Check(!await Verify(10),"Unknown media schema refused by verifier");
 Check(!await Verify(9,cleanupProfile:"minimal-2"),"Independent verifier rejects unexpected clean image");
 var minimal=expected with{CleanupProfile="minimal-2"};
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(minimal,report,probe,false)).Valid,"Clean image requires offline cleanup receipt");
 File.WriteAllText(Path.Combine(root,"BASTOS-Minimal-Offline.json"),JsonSerializer.Serialize(new{Schema=1,Profile="minimal-2",RemainingTargets=Array.Empty<string>()}));
 Check((await RecoveryOperationVerifiers.VerifyAsync(minimal,report,probe,false)).Valid,"Clean image receipt and image hashes accepted together");
 File.WriteAllText(Path.Combine(root,"BASTOS-Minimal-Offline.json"),JsonSerializer.Serialize(new{Schema=1,Profile="minimal-2",RemainingTargets=new[]{"Microsoft.BingNews"}}));
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(minimal,report,probe,false)).Valid,"Remaining offline app blocks final verification");
 await Verify(9);
 // Driver verification uses actual files, separate from the export mocks.
 Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Selected backup cannot be omitted");
 string drivers=Path.Combine(root,"BASTOS-Drivers","Active"),packages=Path.Combine(drivers,"Packages");Directory.CreateDirectory(packages);
 File.WriteAllText(Path.Combine(packages,"audio.inf"),"fixture INF");File.WriteAllText(Path.Combine(packages,"audio.sys"),"fixture SYS");
 var files=Directory.GetFiles(packages).Select(p=>new{Path=Path.GetFileName(p),Bytes=new FileInfo(p).Length,Sha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p)))}).ToArray();
 void DriverManifest(string machine,string architecture="AMD64")=>File.WriteAllText(Path.Combine(drivers,"Manifest.json"),JsonSerializer.Serialize(new{Schema=1,Architecture=architecture,SourceComputer=machine,InfCount=1,TotalBytes=files.Sum(f=>f.Bytes),Files=files}));
 File.WriteAllText(Path.Combine(root,"BASTOS-DRIVERS.enabled"),"1\r\n");DriverManifest(Environment.MachineName);
 Check(await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Driver inventory independently rehashed");
 Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,false),"Unchecked option cannot silently supply retained drivers");
 DriverManifest("another-PC");Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Other source machine refused");
 DriverManifest(Environment.MachineName,"ARM64");Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Other architecture refused");
 DriverManifest(Environment.MachineName);
 File.AppendAllText(Path.Combine(packages,"audio.sys"),"tampered");Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Modified driver refused");
 File.WriteAllText(Path.Combine(packages,"audio.sys"),"fixture SYS");
 File.WriteAllText(Path.Combine(packages,"unlisted.inf"),"unexpected");Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Extra unlisted INF refused");File.Delete(Path.Combine(packages,"unlisted.inf"));
 File.WriteAllText(Path.Combine(root,"BASTOS-DRIVERS.enabled"),"0\r\n");
 Check(await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,false),"Opt-out permits retained backup without using it");
 Check(!await RecoveryOperationVerifiers.VerifyDriverBackupAsync(root,true),"Selected option requires active handoff marker");
 File.WriteAllText(Path.Combine(root,"BASTOS-DRIVERS.enabled"),"1\r\n");
 // Check the integrated final gate, not only the standalone helper.
 Check(!(await RecoveryOperationVerifiers.VerifyAsync(expected,report,probe,false)).Valid,"Final gate rejects unexpected driver selection");
 var withDrivers=expected with{PreserveDrivers=true};
 await Verify(9);
 Check((await RecoveryOperationVerifiers.VerifyAsync(withDrivers,report,probe,false)).Valid,"Final gate accepts verified selected drivers");
 File.WriteAllText(Path.Combine(root,"BASTOS-DRIVERS.enabled"),"0\r\n");
 File.AppendAllText(Path.Combine(root,"sources","install.wim"),"modified");
 Check(!await Verify(9),"Final verifier still rejects changed Windows bytes");
}finally{Directory.Delete(temp,true);}
Console.WriteLine($"PASS : {count} preflight and independent-verifier cache checks; no disk actions.");
if(args.Length==4){
 using var operationDoc=JsonDocument.Parse(File.ReadAllText(args[0]));
 var expectation=JsonSerializer.Deserialize<RecoveryExpectation>(operationDoc.RootElement.GetProperty("ResumeIntent").GetProperty("ExpectedJson").GetString()!)??throw new Exception("Missing persisted expectation");
 using var reportDoc=JsonDocument.Parse(File.ReadAllText(args[1]));
 using var probeDoc=JsonDocument.Parse(File.ReadAllText(args[2]));
 var recheck=await RecoveryOperationVerifiers.VerifyAsync(expectation,reportDoc.RootElement,probeDoc.RootElement,false);
 File.WriteAllText(args[3],JsonSerializer.Serialize(new{ReadOnly=true,OperationId=operationDoc.RootElement.GetProperty("OperationId").GetString(),recheck.Valid,recheck.Message,recheck.Checks},new JsonSerializerOptions{WriteIndented=true}));
 if(!recheck.Valid)throw new Exception("Prepared-media verification failed: "+recheck.Message);
 Console.WriteLine("PASS : existing prepared media independently rehashed and verified; no boot armed.");
}

