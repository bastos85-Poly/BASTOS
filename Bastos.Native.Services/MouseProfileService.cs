using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace Bastos.Native.Services;

// The existing mouse toggle and the profile controls share this single backup.
public static class MouseProfileService
{
    public sealed record State(int Threshold1,int Threshold2,int Acceleration,int Speed);
    public sealed record Backup(State Original,State Applied)
    { public MouseCurveProfiles.Pair? OriginalCurves {get;init;} public MouseCurveProfiles.Pair? AppliedCurves {get;init;} }
    private static readonly string FilePath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BASTOS","MouseProfile.json");
    [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)]
    private static extern bool Spi(uint action,uint param,[In,Out] int[] data,uint flags);
    [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)]
    private static extern bool SpiValue(uint action,uint param,IntPtr data,uint flags);
    private static void Check(bool success){if(!success)throw new Win32Exception(Marshal.GetLastWin32Error());}
    public static bool HasSavedProfile => File.Exists(FilePath);
    public static State Read(){var a=new int[3];var speed=new int[1];Check(Spi(3,0,a,0));Check(Spi(0x70,0,speed,0));return new(a[0],a[1],a[2],speed[0]);}
    public static string Curves()
    {
        using var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Control Panel\Mouse");
        return key?.GetValue("SmoothMouseXCurve") is byte[] x && key.GetValue("SmoothMouseYCurve") is byte[] y
            ?"Courbes Windows enregistrées ("+x.Length+" / "+y.Length+" octets).":"Courbes personnalisées non exposées ; aucune courbe n’est remplacée.";
    }
    private static void Save(Backup backup)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);var tmp=FilePath+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{using(var stream=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(stream,backup);stream.Flush(true);}if(File.Exists(FilePath))File.Replace(tmp,FilePath,FilePath+".previous");else File.Move(tmp,FilePath);}
        finally{if(File.Exists(tmp))File.Delete(tmp);}
    }
    private static void Write(State s){Check(Spi(4,0,new[]{s.Threshold1,s.Threshold2,s.Acceleration},3));Check(SpiValue(0x71,0,new IntPtr(s.Speed),3));if(Read()!=s)throw new InvalidOperationException("Valeurs de souris non confirmées.");}
    public static void Apply(bool? acceleration=null,int? speed=null,bool windowsProfile=false)
    {
        using var mutex=new System.Threading.Mutex(false,@"Local\BASTOS-MouseProfile-"+System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value);
        bool held=false;try{
            try{held=mutex.WaitOne(10000);}catch(System.Threading.AbandonedMutexException){held=true;}if(!held)throw new Exception("Une autre modification de la souris est en cours.");
            var current=Read();if(speed.HasValue&&(speed<1||speed>20))throw new ArgumentOutOfRangeException(nameof(speed),"La vitesse doit être comprise entre 1 et 20.");
            var desired=windowsProfile?new State(6,10,1,10):current with{Acceleration=acceleration.HasValue?(acceleration.Value?1:0):current.Acceleration,Speed=speed??current.Speed};
            var backup=File.Exists(FilePath)?JsonSerializer.Deserialize<Backup>(File.ReadAllText(FilePath))!:new Backup(current,current);
            Save(backup with{Applied=desired});
            try{Write(desired);}catch{try{Write(current);}finally{Save(backup with{Applied=Read()});}throw;}
        }finally{if(held)mutex.ReleaseMutex();}
    }
    public static void ApplyCurve(string name)
    {
        using var mutex=new System.Threading.Mutex(false,@"Local\BASTOS-MouseProfile-"+System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value);
        bool held=false;try{
            try{held=mutex.WaitOne(10000);}catch(System.Threading.AbandonedMutexException){held=true;}if(!held)throw new Exception("Une autre modification de la souris est en cours.");
            var desired=MouseCurveProfiles.Profile(name);var curves=MouseCurveProfiles.Read();var current=Read();
            var backup=File.Exists(FilePath)?JsonSerializer.Deserialize<Backup>(File.ReadAllText(FilePath))!:new Backup(current,current);
            var updated=backup with{OriginalCurves=backup.OriginalCurves??curves,AppliedCurves=desired};
            Save(updated);
            try{MouseCurveProfiles.Write(desired);}catch{try{MouseCurveProfiles.Write(curves);Save(backup);}catch{}throw;}
        }finally{if(held)mutex.ReleaseMutex();}
    }
    public static string Restore()
    {
        using var mutex=new System.Threading.Mutex(false,@"Local\BASTOS-MouseProfile-"+System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value);
        bool held=false;try{
            try{held=mutex.WaitOne(10000);}catch(System.Threading.AbandonedMutexException){held=true;}if(!held)throw new Exception("Une autre modification de la souris est en cours.");
            if(!File.Exists(FilePath))return "Aucune modification de profil sauvegardée.";
            var b=JsonSerializer.Deserialize<Backup>(File.ReadAllText(FilePath))!;var now=Read();var restored=MergeRestore(now,b);
            if(restored!=now)Write(restored);
            bool curvesExternal=false;
            if(b.OriginalCurves!=null&&b.AppliedCurves!=null){
                var curves=MouseCurveProfiles.Read();var restoreCurves=MouseCurveProfiles.MergeRestore(curves,b.OriginalCurves,b.AppliedCurves);
                curvesExternal=restoreCurves!=b.OriginalCurves;MouseCurveProfiles.Write(restoreCurves);
            }
            File.Move(FilePath,FilePath+".restored-"+Guid.NewGuid().ToString("N"));
            return restored==b.Original&&!curvesExternal?"Profil précédent restauré et relu. Après changement de courbe, fermez puis rouvrez la session Windows.":"Profil restauré ; les changements externes ont été conservés.";
        }finally{if(held)mutex.ReleaseMutex();}
    }
    public static State MergeRestore(State current,Backup b)=>new(current.Threshold1==b.Applied.Threshold1?b.Original.Threshold1:current.Threshold1,current.Threshold2==b.Applied.Threshold2?b.Original.Threshold2:current.Threshold2,current.Acceleration==b.Applied.Acceleration?b.Original.Acceleration:current.Acceleration,current.Speed==b.Applied.Speed?b.Original.Speed:current.Speed);
}
