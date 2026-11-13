using Bastos.Native.Services;
const int absent=unchecked((int)0x8A150014);
var shell=new SoftwarePackage("Outils","Open-Shell","Open-Shell.Open-Shell-Menu");
if(args.Length==1 && args[0]=="--uninstall-open-shell")
{
    var real=new SoftwareUninstallationService((exe,a,admin)=>new ProcessExecutionService().RunAsync(exe,a,elevate:admin));
    var result=await real.UninstallWingetAsync(ProcessExecutionService.FindExecutable("winget.exe")!,shell);
    Console.WriteLine(real.Detail);Console.WriteLine(result.Message);Environment.Exit(result.Success?0:1);
}
int passed=0;
async Task Check(string name,CommandResult removal,CommandResult verify,bool expected,string contains="",SoftwarePackage package=null)
{
    var calls=new List<(string[] Args,bool Admin)>();
    var service=new SoftwareUninstallationService((exe,a,admin)=>{calls.Add((a.ToArray(),admin));return Task.FromResult(calls.Count==1?removal:verify);});
    var result=await service.UninstallWingetAsync("winget.exe",package??shell);
    if(result.Success!=expected || !result.Message.Contains(contains))throw new Exception(name+": "+result.Message);
    if(calls.Count>0 && (calls[0].Admin != ((package??shell).Id==shell.Id) || !calls[0].Args.Contains("--exact")))throw new Exception("Elevation or exact ID: "+name);
    if(calls.Count>1 && calls[1].Admin)throw new Exception("Verification elevated");
    if((!removal.ProcessStopped || removal.ExitCode==1223 || removal.ExitCode==1603) && calls.Count!=1)throw new Exception("Unexpected verification/retry");
    Console.WriteLine("PASS "+name);passed++;
}
CommandResult R(int code)=>new(code==0,code,"output","error");
await Check("Verified removal with targeted admin",R(0),R(absent),true,"absence vérifiée");
await Check("Already absent independently verified",R(absent),R(absent),true);
await Check("False success rejected",R(0),R(0),false,"encore détecté");
await Check("Source/network failure not absence",R(0),R(-1),false,"Impossible");
await Check("UAC cancellation explained",R(1223),R(absent),false,"annulée");
await Check("MSI failure preserved",R(1603),R(absent),false,"1603");
await Check("Running removal not retried",R(-2) with{ProcessStopped=false},R(absent),false,"en cours");
await Check("Running verification not success",R(0),R(absent) with{ProcessStopped=false},false);
await Check("Reboot reported without reboot",R(3010),R(absent),true,"redémarrage");
await Check("Ordinary package not elevated",R(0),R(absent),true,package:new("Outils","Test","Vendor.Test"));
await Check("Invalid ID rejected",R(0),R(absent),false,"invalide",new("Outils","Test","--invalid"));
Console.WriteLine($"{passed} PASS");
