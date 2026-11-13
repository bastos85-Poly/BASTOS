using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
using Bastos.Native.Services;

// Explicit integration action: install only the Open-Shell package requested by the user.
if(args.Length!=1)throw new ArgumentException("Application root required.");
string root=Path.GetFullPath(args[0]);
using var lease=new WorkerIntegrityService(root).Acquire("Install-BASTOS-SoftwareSelection.ps1");
string directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BASTOS","Logs");
Directory.CreateDirectory(directory);
string id=Guid.NewGuid().ToString("N"),sid=WindowsIdentity.GetCurrent().User!.Value;
string selection=Path.Combine(directory,"Software-Selection-"+id+".json"),progress=Path.Combine(directory,"Software-Progress-"+id+".txt"),result=Path.Combine(directory,"Software-Result-"+id+".json");
await File.WriteAllTextAsync(selection,JsonSerializer.Serialize(new[]{new{Name="Open-Shell",Id="Open-Shell.Open-Shell-Menu",Source="winget"}}));
var info=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe")){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
foreach(string value in new[]{"-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",Path.Combine(root,"Install-BASTOS-SoftwareSelection.ps1"),"-SelectionPath",selection,"-ProgressPath",progress,"-ResultPath",result,"-ExpectedUserSid",sid})info.ArgumentList.Add(value);
Console.WriteLine("Integrity verified: "+lease.CheckedFiles+" files. Installing Open-Shell only; Windows may ask for administrator approval.");
using var process=Process.Start(info)??throw new InvalidOperationException("Worker did not start.");
var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
await process.WaitForExitAsync();
await File.WriteAllTextAsync(Path.Combine(directory,"Software-Integration-"+id+".log"),await output+await error);
if(!File.Exists(result)){Console.WriteLine("No installation report. Exit: "+process.ExitCode);Environment.ExitCode=1;return;}
var summary=SoftwareInstallationReport.Read(await File.ReadAllBytesAsync(result),new[]{"Open-Shell.Open-Shell-Menu"},process.ExitCode==0,sid);
Console.WriteLine(summary.Message);Console.WriteLine("Report: "+result);
Environment.ExitCode=summary.Success?0:1;
