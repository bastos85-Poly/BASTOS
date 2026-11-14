using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class NativeVmProbe {
 static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
 static Dictionary<string,object> expected;
 const string Evidence=@"C:\VM-Lab\PostInstallProbe.json";
 static string Text(object o){return Convert.ToString(o,CultureInfo.InvariantCulture)??"";}
 static string E(string key){return Text(expected[key]);}
 static object R(RegistryKey root,string path,string key){using(var k=root.OpenSubKey(path)){return k==null?null:k.GetValue(key);}}
 static List<Dictionary<string,object>> Query(string ns,string query){
  var rows=new List<Dictionary<string,object>>();
  using(var search=new ManagementObjectSearcher(ns,query))using(var all=search.Get())foreach(ManagementObject row in all){
   using(row){var data=new Dictionary<string,object>(StringComparer.OrdinalIgnoreCase);foreach(PropertyData p in row.Properties)data[p.Name]=p.Value;rows.Add(data);}
  }
  return rows;
 }
 static string Hash(string p){using(var s=File.OpenRead(p))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(s)).Replace("-","");}
 static string HashDeviceImage(string p){using(var h=CreateFile(p,0x80000000,7,IntPtr.Zero,3,0x08000000,IntPtr.Zero)){if(h.IsInvalid)throw new Win32Exception();using(var s=new FileStream(h,FileAccess.Read))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(s)).Replace("-","");}}
 static string Drive(object value){if(value is ushort || value is byte || value is int)return ((char)Convert.ToInt32(value)).ToString();return Text(value);}
 static bool SameGuid(object a,object b){Guid x,y;return Guid.TryParse(Text(a),out x)&&Guid.TryParse(Text(b),out y)&&x==y;}
 static bool IdentityMatches(string manufacturer,string model,string machine,string user,object uuid,object expectedUuid){
  return manufacturer=="Microsoft Corporation"&&model=="Virtual Machine"&&machine=="BASTOS-VMNEW"&&user=="BastosLab"&&SameGuid(uuid,expectedUuid);
 }
 static int SelfTest(){
  string id=Guid.NewGuid().ToString();int count=0;
  Action<bool> check=ok=>{if(!ok)throw new InvalidOperationException("Native probe guard fixture failed");count++;};
  check(IdentityMatches("Microsoft Corporation","Virtual Machine","BASTOS-VMNEW","BastosLab",id,id));
  check(!IdentityMatches("Physical vendor","Desktop","BASTOS-VMNEW","BastosLab",id,id));
  check(!IdentityMatches("Microsoft Corporation","Virtual Machine","HOST","BastosLab",id,id));
  check(!IdentityMatches("Microsoft Corporation","Virtual Machine","BASTOS-VMNEW","Other",id,id));
  check(!IdentityMatches("Microsoft Corporation","Virtual Machine","BASTOS-VMNEW","BastosLab",Guid.NewGuid(),id));
  check(!IdentityMatches("Microsoft Corporation","Virtual Machine","BASTOS-VMNEW","BastosLab",id,""));
  check(SameGuid("{"+id.ToUpperInvariant()+"}",id));
  var sample=Json.Deserialize<Dictionary<string,object>>("{\"Checks\":[{\"Status\":\"Passed\"},{\"Status\":\"NotRequested\"}]}");
  check(((System.Collections.IEnumerable)sample["Checks"]).Cast<Dictionary<string,object>>().Count()==2);
  Console.WriteLine("PASS : "+count+" native probe guard and JSON fixtures; no system operations.");return 0;
 }
 static void Guard(){
  var pc=Query("root\\cimv2","SELECT Manufacturer,Model FROM Win32_ComputerSystem").Single();
  if(!IdentityMatches(Text(pc["Manufacturer"]),Text(pc["Model"]),Environment.MachineName,Environment.UserName,
     Query("root\\cimv2","SELECT UUID FROM Win32_ComputerSystemProduct").Single()["UUID"],E("VmUuid")))
   throw new InvalidOperationException("Sonde refusee : identite du laboratoire non confirmee.");
  var disks=Query("root\\Microsoft\\Windows\\Storage","SELECT Guid FROM MSFT_Disk");
  if(disks.Count!=1||!SameGuid(disks[0]["Guid"],E("DiskGuid")))throw new InvalidOperationException("Sonde refusee : disque virtuel divergent.");
  if(Hash(System.Reflection.Assembly.GetExecutingAssembly().Location)!=E("NativeProbeSha256"))throw new InvalidOperationException("Sonde refusee : executable de verification divergent.");
 }
 [STAThread] static int Main(string[] args){
  if(args.Length==1&&args[0]=="--self-test")return SelfTest();
  if(args.Length!=0)return 21;
  try{expected=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(@"C:\VM-Lab\Expected.json"));Guard();}
  catch(Exception ex){MessageBox.Show(ex.Message,"Sonde BASTOS refusee");return 20;}
  var result=new Dictionary<string,object>();
  try{
   DateTime until=DateTime.UtcNow.AddMinutes(8);string receipt=@"C:\ProgramData\BASTOS-ISO\Logs\Rufus-FirstLogon.ok";
   while(DateTime.UtcNow<until){
    try{if(File.Exists(receipt)&&File.Exists(@"C:\ProgramData\BASTOS-ISO\Logs\Installation-Verification.json")){
     var state=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(@"C:\ProgramData\BASTOS-ISO\Logs\Recovery-Finalization.json"));
     if(new[]{"Completed","Blocked","Incomplete"}.Contains(Text(state["Status"])))break;
    }}catch(IOException){}catch(ArgumentException){}
    Thread.Sleep(3000);
   }
   IntPtr token;bool blank=LogonUser("BastosLab",Environment.MachineName,"",2,0,out token);int blankError=Marshal.GetLastWin32Error();if(token!=IntPtr.Zero)CloseHandle(token);
   bool wrong=LogonUser("BastosLab",Environment.MachineName,"Never-configured-"+Guid.NewGuid().ToString("N"),2,0,out token);int wrongError=Marshal.GetLastWin32Error();if(token!=IntPtr.Zero)CloseHandle(token);
   IntPtr userInfo;uint infoError=NetUserGetInfo(null,"BastosLab",1,out userInfo);if(infoError!=0)throw new Win32Exception((int)infoError);
   bool passwordRequired;try{passwordRequired=(((UserInfo1)Marshal.PtrToStructure(userInfo,typeof(UserInfo1))).Flags&0x20)==0;}finally{NetApiBufferFree(userInfo);}
   var parts=Query("root\\Microsoft\\Windows\\Storage","SELECT DiskNumber,PartitionNumber,Guid,GptType,Size,Offset,DriveLetter,IsHidden FROM MSFT_Partition");
   var c=parts.Single(p=>Drive(p["DriveLetter"])=="C");
   var efi=parts.Where(p=>SameGuid(p["GptType"],"C12A7328-F81F-11D2-BA4B-00A0C93EC93B")).ToArray();
   var disks=Query("root\\Microsoft\\Windows\\Storage","SELECT Number,Guid,Size FROM MSFT_Disk");
   string key=Text(R(Registry.CurrentUser,@"Keyboard Layout\Preload","1"));
   var locale=new StringBuilder(85);if(GetSystemDefaultLocaleName(locale,locale.Capacity)==0)throw new Win32Exception();
   string shortcut=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"BASTOS.lnk");
   string windowsExe=@"C:\ProgramData\BASTOS-ISO\Bastos.Native\BASTOS-Native.exe";
   string target="";if(File.Exists(shortcut)){dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));try{dynamic link=shell.CreateShortcut(shortcut);try{target=(string)link.TargetPath;}finally{Marshal.FinalReleaseComObject(link);}}finally{Marshal.FinalReleaseComObject(shell);}}
   var checks=new Dictionary<string,bool>();
   checks["CandidateOnWindows"]=File.Exists(windowsExe)&&Hash(windowsExe)==E("CandidateSha256");
   checks["WindowsPro"]=Text(R(Registry.LocalMachine,@"SOFTWARE\Microsoft\Windows NT\CurrentVersion","EditionID"))=="Professional";
   checks["ComputerName"]=Environment.MachineName=="BASTOS-VMNEW";
   checks["LocalUser"]=Environment.UserName=="BastosLab"&&!WindowsIdentity.GetCurrent().User.Value.EndsWith("-500",StringComparison.Ordinal);
   checks["Passwordless"]=blank||(!passwordRequired&&blankError==1327&&!wrong&&wrongError==1326);
   checks["French"]=CultureInfo.CurrentCulture.Name=="fr-FR"&&locale.ToString()=="fr-FR";
   checks["Azerty"]=key.Equals("0000040C",StringComparison.OrdinalIgnoreCase);
   checks["DesktopObserved"]=Convert.ToBoolean(expected["DesktopObserved"])&&Process.GetProcessesByName("explorer").Length>0;
   checks["SingleVirtualDisk"]=disks.Count==1&&SameGuid(disks[0]["Guid"],E("DiskGuid"));
   checks["TemporaryRecoveryRemoved"]=!parts.Any(p=>SameGuid(p["Guid"],E("RecoveryGuid")));
   checks["SpaceReturnedToWindows"]=Convert.ToUInt64(c["Size"])>=Convert.ToUInt64(expected["OldWindowsBytes"])+Convert.ToUInt64(expected["RecoveryBytes"])-2UL*1024*1024*1024;
   checks["WindowsRecreated"]=!SameGuid(c["Guid"],E("OldWindowsGuid"));
   checks["EfiPolicy"]=efi.Length==1&&(SameGuid(efi[0]["Guid"],E("OldEfiGuid"))==Convert.ToBoolean(expected["KeepEfi"]));
   checks["FirstLogonComplete"]=File.Exists(receipt);
   checks["DesktopShortcut"]=File.Exists(shortcut);
   checks["DesktopShortcutTarget"]=string.Equals(Path.GetFullPath(target),windowsExe,StringComparison.OrdinalIgnoreCase);
   var final=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(@"C:\ProgramData\BASTOS-ISO\Logs\Recovery-Finalization.json"));
   var details=(Dictionary<string,object>)final["Details"];
   checks["FinalizationVerified"]=Text(final["Status"])=="Completed"&&SameGuid(details["RecoveryGuid"],E("RecoveryGuid"))&&SameGuid(details["WindowsGuid"],c["Guid"])&&SameGuid(details["DiskGuid"],E("DiskGuid"));
   var winre=parts.Where(p=>SameGuid(p["GptType"],"DE94BBA4-06D1-4D40-A16A-BFD50179D6AC")).ToArray();
   checks["HiddenWinRE"]=winre.Length==1&&Convert.ToBoolean(winre[0]["IsHidden"])&&(winre[0]["DriveLetter"]==null||Drive(winre[0]["DriveLetter"])=="\0"||Drive(winre[0]["DriveLetter"])=="")&&Convert.ToUInt64(winre[0]["Offset"])==parts.Max(p=>Convert.ToUInt64(p["Offset"]));
   string winreImage=winre.Length==1?@"\\?\GLOBALROOT\device\harddisk"+Text(c["DiskNumber"])+@"\partition"+Text(winre[0]["PartitionNumber"])+@"\Recovery\WindowsRE\Winre.wim":"";
   checks["WinREImageVerified"]=winre.Length==1&&HashDeviceImage(winreImage)==Hash(@"C:\ProgramData\BASTOS-ISO\Winre-Finalization.wim");
   string profilePath=@"C:\ProgramData\BASTOS-ISO\Installation-Expected.json";
   var profile=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(profilePath));
   var report=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(@"C:\ProgramData\BASTOS-ISO\Logs\Installation-Verification.json"));
   var reportChecks=((System.Collections.IEnumerable)report["Checks"]).Cast<Dictionary<string,object>>().ToArray();
   checks["InstallationReportMatchesProfile"]=Text(report["ProfileId"])==Text(profile["ProfileId"])&&Text(report["ProfileSha256"])==Hash(profilePath);
   checks["InstallationReportConformity"]=reportChecks.Length==16&&reportChecks.Cast<Dictionary<string,object>>().All(check=>Text(check["Status"])=="Passed"||Text(check["Status"])=="NotRequested");
   result["Passed"]=checks.Values.All(v=>v);result["Checks"]=checks;
   result["LocalLogonError"]=blank?0:blankError;result["WrongPasswordError"]=wrongError;result["PasswordRequired"]=passwordRequired;
   result["Partitions"]=parts;result["User"]=Environment.UserName;result["ComputerName"]=Environment.MachineName;result["KeyboardRegistry"]=key;result["ShortcutTarget"]=target;
  }catch(Exception ex){result["Passed"]=false;result["Error"]=ex.ToString();}
  result["Schema"]=2;result["NativeProbeSha256"]=E("NativeProbeSha256");result["RunId"]=E("RunId");result["CheckedUtc"]=DateTime.UtcNow.ToString("o");
  try{Guard();File.WriteAllText(Evidence,Json.Serialize(result),new UTF8Encoding(false));Shutdown();return Convert.ToBoolean(result["Passed"])?0:1;}
  catch(Exception ex){MessageBox.Show(ex.Message,"Sonde BASTOS non terminee");return 2;}
 }
 static void Shutdown(){
  IntPtr token;if(!OpenProcessToken(Process.GetCurrentProcess().Handle,0x28,out token))throw new Win32Exception();
  try{Luid luid;if(!LookupPrivilegeValue(null,"SeShutdownPrivilege",out luid))throw new Win32Exception();var privileges=new TokenPrivileges{Count=1,Luid=luid,Attributes=2};if(!AdjustTokenPrivileges(token,false,ref privileges,0,IntPtr.Zero,IntPtr.Zero)||Marshal.GetLastWin32Error()!=0)throw new Win32Exception();}finally{CloseHandle(token);}
  if(!InitiateSystemShutdownEx(null,"Fin du test BASTOS dans la VM de laboratoire",3,true,false,0x80040001))throw new Win32Exception();
 }
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct UserInfo1{public string Name,Password;public uint PasswordAge,Privilege;public string HomeDir,Comment;public uint Flags;public string ScriptPath;}
 [StructLayout(LayoutKind.Sequential)] struct Luid{public uint Low;public int High;}
 [StructLayout(LayoutKind.Sequential)] struct TokenPrivileges{public uint Count;public Luid Luid;public uint Attributes;}
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool LogonUser(string u,string d,string p,int type,int provider,out IntPtr token);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern int GetSystemDefaultLocaleName(StringBuilder name,int count);
 [DllImport("netapi32.dll",CharSet=CharSet.Unicode)]static extern uint NetUserGetInfo(string server,string name,uint level,out IntPtr buffer);
 [DllImport("netapi32.dll")]static extern uint NetApiBufferFree(IntPtr buffer);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool LookupPrivilegeValue(string system,string name,out Luid luid);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref TokenPrivileges privileges,uint length,IntPtr previous,IntPtr returned);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool InitiateSystemShutdownEx(string machine,string message,uint timeout,bool force,bool reboot,uint reason);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateFileW")]static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
}
