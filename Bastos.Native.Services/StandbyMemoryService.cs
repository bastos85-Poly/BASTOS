using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace Bastos.Native.Services;

public static class StandbyMemoryService
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)]
    private struct TokenPrivileges { public uint Count; public Luid Luid; public uint Attributes; }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state,
        uint length, out TokenPrivileges previous, out uint returned);
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("ntdll.dll")]
    private static extern int NtSetSystemInformation(int informationClass, ref int command, uint length);

    public static NativeActionResult Clear()
    {
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            return new NativeActionResult(false, "Le nettoyage nécessite les droits administrateur de Windows.", 5);
        IntPtr token = IntPtr.Zero;
        TokenPrivileges previous = default;
        bool adjusted = false;
        try
        {
            using var process = Process.GetCurrentProcess();
            if (!OpenProcessToken(process.Handle, 0x28, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out var luid)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var requested = new TokenPrivileges { Count = 1, Luid = luid, Attributes = 2 };
            bool success = AdjustTokenPrivileges(token, false, ref requested, (uint)Marshal.SizeOf<TokenPrivileges>(), out previous, out _);
            int error = Marshal.GetLastWin32Error();
            if (!success || error != 0) throw new Win32Exception(error);
            adjusted = true;
            // SystemMemoryListInformation=80; MemoryPurgeStandbyList=4.
            // This does not request working-set trimming or a modified-page flush.
            int command = 4;
            int status = NtSetSystemInformation(80, ref command, sizeof(int));
            if (status < 0) return new NativeActionResult(false, $"Windows a refusé le nettoyage (NTSTATUS 0x{status:X8}).", 1);
            return new NativeActionResult(true, "Liste standby vidée. Windows peut la remplir à nouveau au fil de son utilisation.");
        }
        catch (Exception ex) { return new NativeActionResult(false, "Nettoyage impossible : " + ex.Message, 1); }
        finally
        {
            if (adjusted) AdjustTokenPrivileges(token, false, ref previous, (uint)Marshal.SizeOf<TokenPrivileges>(), out _, out _);
            if (token != IntPtr.Zero) CloseHandle(token);
        }
    }
}
