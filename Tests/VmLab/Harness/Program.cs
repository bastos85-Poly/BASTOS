using System.IO;
using System.Text.Json;
using Bastos.Native.Services;
using Bastos.Native.Models;

if (args.Length != 2 || args[0] is not ("prepare" or "prepare-keep-efi" or "boot") || args[1].Length != 32)
    throw new InvalidOperationException("VM test : mode et identifiant de laboratoire requis.");
string id=args[1];
if (Environment.MachineName != "BASTOS-VMLAB" || !File.Exists(@"D:\BASTOS-VM-KEEP.txt") || File.ReadAllText(@"D:\BASTOS-VM-KEEP.txt") != id)
    throw new InvalidOperationException("VM test : machine de laboratoire non reconnue.");
var runner=new ProcessExecutionService();
var guard=await runner.RunAsync(Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),
    new[]{"-NoProfile","-Command","$c=Get-CimInstance Win32_ComputerSystem;$a=Get-Partition -DriveLetter C;$b=Get-Partition -DriveLetter D;if($c.Manufacturer -ne 'Microsoft Corporation' -or $c.Model -ne 'Virtual Machine' -or $a.DiskNumber -ne $b.DiskNumber -or (Get-Volume -DriveLetter D).FileSystemLabel -ne 'BASTOS_RECOVERY'){exit 12};if(@(Get-Disk).Count -ne 1){exit 13}"});
if(!guard.Success || !guard.ProcessStopped)throw new InvalidOperationException("VM test : isolation invitée non confirmée.");
string output=@"D:\VM-Test-Results";Directory.CreateDirectory(output);
void Save(string name,object value)=>File.WriteAllText(Path.Combine(output,name+".json"),JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}));
var paths=new AppPaths();var log=new OperationLogService(paths);var workers=new PowerShellWorkerService(paths,runner,log);
var modules=new ModuleOperationService(paths,workers,runner,log);var service=new ReinstallService(paths,workers,modules,log);
if(paths.Root != @"D:\Application")throw new InvalidOperationException("VM test : racine applicative divergente.");
var iso=new IsoChoice("Windows 11 Pro — laboratoire",@"C:\ISO\Windows11-Pro.iso");
var options=new RufusInstallOptions {UserName="BastosLab",ComputerName="BASTOS-VMNEW",WindowsLocale="fr-FR",WindowsUILanguage="fr-FR",KeyboardLayout="040C:0000040C",KeepOnlyRecoveryPartition=args[0]!="prepare-keep-efi"};
var progress=new LabProgress(p=>{Save("progress",p);Console.WriteLine($"{p.Percent:N0}% {p.Phase} {p.Message}");});
if(args[0].StartsWith("prepare"))
{
    var disk=await service.PreviewRecoveryAsync(options);Save("disk-before",disk);
    if(!disk.Success)throw new InvalidOperationException(disk.Message);
    options.DiskSafetySnapshot=disk.DiskSnapshot;options.RecoveryPartitionGuid=disk.PartitionGuid;options.WindowsDiskIdentity=disk.DiskIdentity;
    var catalog=await service.ReadIsoEditionsAsync(iso);Save("iso",catalog);
    var pro=catalog.Images.Single(e=>e.EditionId=="Professional");
    options.WindowsImageIndex=pro.ImageIndex;options.WindowsEditionId=pro.EditionId;options.WindowsImageName=pro.ImageName;
    options.EditionIsoPath=catalog.IsoPath;options.EditionIsoSha256=catalog.IsoSha256;
    var missing=await service.ReviewRecoveryAsync(new IsoChoice("Missing",@"C:\ISO\definitely-missing.iso"),options,true);Save("missing-iso-refused",missing);
    if(missing.CanContinue)throw new InvalidOperationException("ISO absente non refusée.");
    var altered=JsonSerializer.Deserialize<RufusInstallOptions>(JsonSerializer.Serialize(options))!;
    altered.DiskSafetySnapshot=altered.DiskSafetySnapshot.Replace("\"Model\":", "\"Model\":\"SIMULATED\",\"OldModel\":");
    var changed=await service.PreviewRecoveryAsync(altered);Save("changed-plan-refused",changed);
    if(changed.Success)throw new InvalidOperationException("Plan divergent non refusé.");
    if(args[0]=="prepare-keep-efi")
    {
        string filler=Path.Combine(@"D:\", "VM-SPACE-TEST-"+Guid.NewGuid().ToString("N")+".tmp");
        try
        {
            long fillBytes=disk.RecoveryFreeBytes-new FileInfo(iso.Path).Length-2147483648L+16777216L;
            if(fillBytes<=0)throw new InvalidOperationException("Test espace : état de départ insuffisant.");
            using(var file=new FileStream(filler,FileMode.CreateNew,FileAccess.Write,FileShare.None))file.SetLength(fillBytes);
            var noSpace=await service.ReviewRecoveryAsync(iso,options,true);Save("insufficient-space-refused",noSpace);
            if(noSpace.CanContinue || !noSpace.Blockers.Any(b=>b.StartsWith("Espace insuffisant")))throw new InvalidOperationException("Espace insuffisant non refusé.");
        }
        finally{if(File.Exists(filler))File.Delete(filler);}
    }
    var review=await service.ReviewRecoveryAsync(iso,options,true);Save("review",review);
    if(!review.CanContinue)throw new InvalidOperationException(string.Join(" / ",review.Blockers));
    service.SaveRufusOptions(options);
    var prepared=await service.ProvisionRecoveryAsync(iso,new("Français","French","fr-FR"),new("AZERTY","040C:0000040C"),"BastOS",progress,approvedOptions:options);
    Save("prepare",new {prepared.Success,prepared.Message});
    if(!prepared.Success)throw new InvalidOperationException(prepared.Message);
    if(File.ReadAllText(@"D:\BASTOS-VM-KEEP.txt")!=id)throw new InvalidOperationException("Témoin D: modifié.");
}
else
{
    options=service.ReadRufusOptions();
    var boot=await service.BootRecoveryAsync(iso,options,recoveryProgress:progress);Save("boot",new{boot.Success,boot.Message});
    if(!boot.Success)throw new InvalidOperationException(boot.Message);
}
foreach(var file in Directory.GetFiles(Path.Combine(paths.LogRoot,"Operations"),"*.json"))File.Copy(file,Path.Combine(output,Path.GetFileName(file)),true);
Console.WriteLine("PASS : phase VM "+args[0]+" terminée et preuves conservées sur D:.");

sealed class LabProgress(Action<RecoveryBuildProgress> report) : IProgress<RecoveryBuildProgress>
{
    private readonly object gate=new();
    public void Report(RecoveryBuildProgress value){lock(gate)report(value);}
}
