using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;
namespace Bastos.Native.Services;
public static class KeyboardRepeatService
{
    [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)]
    private static extern bool Get(uint action,uint param,out uint value,uint flags);
    [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)]
    private static extern bool Set(uint action,uint value,IntPtr unused,uint flags);
    public static bool Apply(int delay,int speed)
    {
        if(delay<0||delay>3||speed<0||speed>31)throw new ArgumentOutOfRangeException();
        // A service session has no interactive keyboard. Registry persistence is still verified by the caller.
        if(System.Diagnostics.Process.GetCurrentProcess().SessionId==0)return false;
        if(!Set(0x17,(uint)delay,IntPtr.Zero,3)||!Set(0x0b,(uint)speed,IntPtr.Zero,3))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Windows ne confirme pas la répétition du clavier ; le profil reste à vérifier.");
        if(!Get(0x16,0,out var d,0)||!Get(0x0a,0,out var v,0)||d!=delay||v!=speed)
            throw new InvalidOperationException("La session Windows ne confirme pas la répétition demandée.");
        return true;
    }
    public static string Describe()
    {
        using var key=Registry.CurrentUser.OpenSubKey(@"Control Panel\Keyboard");
        string saved="Enregistré : délai "+(key?.GetValue("KeyboardDelay")??"absent")+"/3, vitesse "+(key?.GetValue("KeyboardSpeed")??"absente")+"/31";
        if(Get(0x16,0,out var d,0)&&Get(0x0a,0,out var s,0))return saved+" ; session : "+d+"/3, "+s+"/31.";
        return saved+" ; session non vérifiable.";
    }
}
