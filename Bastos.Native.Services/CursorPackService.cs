using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
namespace Bastos.Native.Services;

public sealed class CursorPackService
{
    public const string SchemeName="W11 Cursor Dark Free by Jepri Creations";
    private const string Cursors=@"Control Panel\Cursors",Schemes=@"Control Panel\Cursors\Schemes";
    private static readonly (string Role,string File)[] Roles={
        ("Arrow","arrow.cur"),("Help","help.cur"),("AppStarting","appstarting.ani"),("Wait","wait.ani"),("Crosshair","crosshair.cur"),("IBeam","ibeam.cur"),("NWPen","nwpen.cur"),("No","no.cur"),("SizeNS","sizens.cur"),("SizeWE","sizewe.cur"),("SizeNWSE","sizenwse.cur"),("SizeNESW","sizenesw.cur"),("SizeAll","sizeall.cur"),("UpArrow","uparrow.cur"),("Hand","hand.cur"),("Person","person.cur"),("Pin","pin.cur")};
    public sealed record Entry(string Path,string Name,bool Exists,string Kind,string Data);
    public sealed record Backup(int Version,Entry[] Original,Entry[] Applied);
    public sealed record Status(bool Available,bool Applied,bool CanRestore,string Message);
    private readonly string source,store,backupPath;
    [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)]private static extern bool Spi(uint action,uint param,IntPtr data,uint flags);
    public CursorPackService(AppPaths paths){source=Path.Combine(paths.Root,"Assets","Cursor-Dark");store=Path.Combine(paths.DataRoot,"Cursors");backupPath=Path.Combine(paths.DataRoot,"CursorPack.json");}
    private static string Hash(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    private string Destination()
    {
        var hashes=new StringBuilder();
        foreach(var role in Roles){var path=Path.Combine(source,role.File);if(!File.Exists(path))throw new FileNotFoundException("Pack incomplet : "+role.File);var bytes=File.ReadAllBytes(path);
            bool valid=role.File.EndsWith(".cur")?bytes.Length>=6&&bytes[0]==0&&bytes[1]==0&&bytes[2]==2&&bytes[3]==0:bytes.Length>=12&&Encoding.ASCII.GetString(bytes,0,4)=="RIFF"&&Encoding.ASCII.GetString(bytes,8,4)=="ACON";
            if(!valid)throw new InvalidDataException("Fichier de curseur non reconnu : "+role.File);hashes.Append(Hash(path));}
        var license=Path.Combine(source,"CREDITS-AND-LICENSE.txt");if(!File.Exists(license))throw new FileNotFoundException("Crédits et licence du pack introuvables.");hashes.Append(Hash(license));
        return Path.Combine(store,"W11-Dark-"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(hashes.ToString())))[..16]);
    }
    private static Entry Read(string path,string name)
    {
        using var key=Registry.CurrentUser.OpenSubKey(path);if(key==null||!key.GetValueNames().Contains(name,StringComparer.OrdinalIgnoreCase))return new(path,name,false,"","");
        var kind=key.GetValueKind(name);if(kind is not RegistryValueKind.String and not RegistryValueKind.ExpandString and not RegistryValueKind.DWord)throw new InvalidDataException("Type de préférence de curseur non pris en charge : "+name);
        return new(path,name,true,kind.ToString(),Convert.ToString(key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames),System.Globalization.CultureInfo.InvariantCulture)??"");
    }
    private static void Write(Entry e)
    {
        using var key=Registry.CurrentUser.CreateSubKey(e.Path,true);
        if(!e.Exists)key.DeleteValue(e.Name,false);else{
            var kind=Enum.Parse<RegistryValueKind>(e.Kind);object value=kind==RegistryValueKind.DWord?int.Parse(e.Data,System.Globalization.CultureInfo.InvariantCulture):e.Data;
            key.SetValue(e.Name,value,kind);
        }key.Flush();if(Read(e.Path,e.Name)!=e)throw new InvalidOperationException("Préférence de curseur non confirmée : "+e.Name);
    }
    private static Entry[] Targets(string destination)=>Roles.Select(r=>new Entry(Cursors,r.Role,true,"ExpandString",Path.Combine(destination,r.File)))
        .Concat(new[]{new Entry(Cursors,"",true,"String",SchemeName),new Entry(Cursors,"Scheme Source",true,"DWord","1"),new Entry(Schemes,SchemeName,true,"String",string.Join(",",Roles.Select(r=>Path.Combine(destination,r.File))))}).ToArray();
    private void Save(Backup b)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(backupPath)!);var tmp=backupPath+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{using(var f=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(f,b);f.Flush(true);}if(File.Exists(backupPath))File.Replace(tmp,backupPath,backupPath+".previous");else File.Move(tmp,backupPath);}finally{if(File.Exists(tmp))File.Delete(tmp);}
    }
    private Backup Load()
    {
        var b=JsonSerializer.Deserialize<Backup>(File.ReadAllText(backupPath))??throw new InvalidDataException("Sauvegarde vide.");
        var allowed=Targets("").Select(e=>(e.Path,e.Name)).ToHashSet();
        if(b.Version!=1||b.Original.Length!=allowed.Count||b.Applied.Length!=allowed.Count||b.Original.Select(e=>(e.Path,e.Name)).Distinct().Count()!=allowed.Count||b.Applied.Select(e=>(e.Path,e.Name)).Distinct().Count()!=allowed.Count)throw new InvalidDataException("Sauvegarde de curseurs incompatible.");
        foreach(var e in b.Original.Concat(b.Applied))if(!allowed.Contains((e.Path,e.Name))||e.Exists&&e.Kind is not "String" and not "ExpandString" and not "DWord")throw new InvalidDataException("Cible de restauration de curseur non autorisée.");
        return b;
    }
    private static System.Threading.Mutex Mutex()=>new(false,@"Local\BASTOS-CursorPack-"+System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value);
    private static bool Lock(System.Threading.Mutex m){try{if(m.WaitOne(10000))return true;}catch(System.Threading.AbandonedMutexException){return true;}throw new Exception("Une autre modification de curseurs est en cours.");}
    public Status ReadStatus()
    {
        try{var dest=Destination();var applied=Targets(dest).All(e=>Read(e.Path,e.Name)==e)&&Roles.All(r=>File.Exists(Path.Combine(dest,r.File)));return new(true,applied,File.Exists(backupPath),applied?"Pack sombre configuré pour ce compte Windows.":"Pack disponible. Votre thème actuel est conservé jusqu’à l’activation.");}
        catch(Exception ex){return new(false,false,File.Exists(backupPath),ex.Message);}
    }
    public string Apply()
    {
        using var m=Mutex();var held=Lock(m);try{
            var destination=Destination();Directory.CreateDirectory(destination);
            foreach(var file in Roles.Select(r=>r.File).Append("CREDITS-AND-LICENSE.txt")){
                var from=Path.Combine(source,file);var to=Path.Combine(destination,file);
                if(!File.Exists(to))File.Copy(from,to);if(Hash(from)!=Hash(to))throw new IOException("Copie du pack non confirmée : "+file);
            }
            var targets=Targets(destination);var backup=File.Exists(backupPath)?Load():new Backup(1,targets.Select(e=>Read(e.Path,e.Name)).ToArray(),targets);
            Save(backup with{Applied=targets});foreach(var e in targets)Write(e);
            return Spi(0x57,0,IntPtr.Zero,2)?"Pack sombre activé et préférences vérifiées. Le choix est conservé après redémarrage.":"Pack sombre enregistré et vérifié. Rouvrez votre session Windows pour recharger les curseurs.";
        }finally{if(held)m.ReleaseMutex();}
    }
    public string Restore()
    {
        using var m=Mutex();var held=Lock(m);try{
            if(!File.Exists(backupPath))return "Aucun thème précédent sauvegardé par Bastos.";
            var b=Load();bool external=false;
            foreach(var original in b.Original){var applied=b.Applied.Single(e=>e.Path==original.Path&&e.Name==original.Name);var current=Read(original.Path,original.Name);if(current==applied)Write(original);else if(current!=original)external=true;}
            bool reloaded=Spi(0x57,0,IntPtr.Zero,2);File.Move(backupPath,backupPath+".restored-"+Guid.NewGuid().ToString("N"));
            return (external?"Thème précédent restauré ; les changements externes sont conservés.":"Thème précédent restauré et préférences vérifiées.")+(reloaded?"":" Rouvrez votre session pour recharger les curseurs.");
        }finally{if(held)m.ReleaseMutex();}
    }
}
