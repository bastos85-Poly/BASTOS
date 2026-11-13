using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Bastos.Native.Services;

public interface IMouseAccelerationService
{
    bool Read();
    bool SetEnabled(bool enabled);
}

// Per-user Windows setting. SPI applies it live, persists it and broadcasts the change.
public sealed class MouseAccelerationService : IMouseAccelerationService
{
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint action, uint param,
        [In, Out] int[] values, uint flags);

    private static int[] ReadValues()
    {
        var values = new int[3];
        if (!SystemParametersInfo(3, 0, values, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        return values;
    }

    public bool Read() => ReadValues()[2] != 0;

    public bool SetEnabled(bool enabled)
    {
        MouseProfileService.Apply(acceleration:enabled);
        bool actual = Read();
        if (actual != enabled)
            throw new InvalidOperationException("Windows n’a pas confirmé le changement.");
        return actual;
    }
}
