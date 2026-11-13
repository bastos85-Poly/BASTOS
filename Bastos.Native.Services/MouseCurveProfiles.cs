using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Win32;
namespace Bastos.Native.Services;

public static class MouseCurveProfiles
{
    public sealed record Value(bool Exists,string Data);
    public sealed record Pair(Value X,Value Y);
    private static readonly Dictionary<string,Pair> Profiles=new()
    {
        ["Défaut"] = new(new(true,"AAAAAAAAAAAVbgAAAAAAAABAAQAAAAAAKdwDAAAAAAAAACgAAAAAAA=="),new(true,"AAAAAAAAAAD9EQEAAAAAAAAkBAAAAAAAAPwSAAAAAAAAwLsBAAAAAA==")),
        ["MarkC"] = new(new(true,"AAAAAAAAAADAzAwAAAAAAICZGQAAAAAAQGYmAAAAAAAAMzMAAAAAAA=="),new(true,"AAAAAAAAAAAAADgAAAAAAAAAcAAAAAAAAACoAAAAAAAAAOAAAAAAAA==")),
        ["CPL"] = new(new(true,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUAAAAAAA=="),new(true,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4MxUAAAAAAA==")),
        ["CheeseM"] = new(new(true,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMgAAAAAAA=="),new(true,"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVABAAAAAA==")),
        ["Courbes nulles"] = new(new(true,Convert.ToBase64String(new byte[40])),new(true,Convert.ToBase64String(new byte[40]))),
    };
    public static string[] Names => new[]{"Défaut","MarkC","CPL","CheeseM","Courbes nulles"};
    public static Pair Profile(string name) => Profiles.TryGetValue(name,out var p)?p:throw new ArgumentException("Profil de courbe inconnu.");
    private static Value ReadValue(RegistryKey key,string name)
    {
        if(!key.GetValueNames().Contains(name))return new(false,"");
        if(key.GetValueKind(name)!=RegistryValueKind.Binary||key.GetValue(name) is not byte[] data)throw new InvalidOperationException("La courbe existante n’est pas un tableau binaire ; aucune modification.");
        return new(true,Convert.ToBase64String(data));
    }
    public static Pair Read(){using var key=Registry.CurrentUser.OpenSubKey(@"Control Panel\Mouse");return key==null?new(new(false,""),new(false,"")):new(ReadValue(key,"SmoothMouseXCurve"),ReadValue(key,"SmoothMouseYCurve"));}
    public static string CurrentName(){var current=Read();return Profiles.FirstOrDefault(p=>p.Value==current).Key??"Personnalisé";}
    public static void Write(Pair pair)
    {
        using var key=Registry.CurrentUser.CreateSubKey(@"Control Panel\Mouse",true);
        void Set(string name,Value value){if(value.Exists)key.SetValue(name,Convert.FromBase64String(value.Data),RegistryValueKind.Binary);else key.DeleteValue(name,false);}
        Set("SmoothMouseXCurve",pair.X);Set("SmoothMouseYCurve",pair.Y);key.Flush();
        if(Read()!=pair)throw new InvalidOperationException("Courbes non confirmées après écriture.");
    }
    public static Pair MergeRestore(Pair current,Pair original,Pair applied)=>new(current.X==applied.X?original.X:current.X,current.Y==applied.Y?original.Y:current.Y);
}
