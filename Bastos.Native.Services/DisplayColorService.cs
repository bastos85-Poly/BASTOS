using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Bastos.Native.Services;

// Gamma-ramp math adapted from EXFIL (MIT, copyright 2026 Blazzer).
// The ramp is neutral across R/G/B; saturation is handled by the display driver.
public sealed class DisplayColorService : IDisposable
{
    private readonly Dictionary<string, ushort[]> originalRamps = new(StringComparer.OrdinalIgnoreCase);
    private readonly AmdSaturationService? amd;

    public DisplayColorService()
    {
        amd = AmdSaturationService.TryOpen();
    }

    public (int Current, int Minimum, int Maximum, int Default)? Vibrance => amd?.ReadPrimary();

    public void Apply(double gamma, double brightness, double contrast, int vibrance)
    {
        var ramp = BuildRamp(gamma, brightness, contrast);
        var applied = 0;
        for (var n = 1; n <= 16; n++)
        {
            var name = $@"\\.\DISPLAY{n}";
            var dc = CreateDCW(name, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (dc == IntPtr.Zero) continue;
            try
            {
                var current = new ushort[768];
                if (!GetDeviceGammaRamp(dc, current)) continue;
                if (!originalRamps.ContainsKey(name)) originalRamps.Add(name, current);
                if (SetDeviceGammaRamp(dc, ramp)) applied++;
            }
            finally { DeleteDC(dc); }
        }
        if (applied == 0) throw new InvalidOperationException("Le pilote n'a accepté aucun réglage gamma.");
        if (amd != null) amd.SetAll(vibrance);
    }

    public bool Matches(double gamma, double brightness, double contrast, int vibrance)
    {
        var expected = BuildRamp(gamma, brightness, contrast);
        var found = 0;
        for (var n = 1; n <= 16; n++)
        {
            var dc = CreateDCW($@"\\.\DISPLAY{n}", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (dc == IntPtr.Zero) continue;
            try
            {
                var current = new ushort[768];
                if (!GetDeviceGammaRamp(dc, current)) continue;
                found++;
                for (var i = 0; i < current.Length; i++)
                    if (Math.Abs((int)current[i] - expected[i]) > 256) return false;
            }
            finally { DeleteDC(dc); }
        }
        if (found == 0) return true; // No usable SDR gamma ramp; avoid a write loop.
        var amdCurrent = amd?.ReadPrimary();
        return !amdCurrent.HasValue || amdCurrent.Value.Current == Math.Clamp(vibrance, amdCurrent.Value.Minimum, amdCurrent.Value.Maximum);
    }

    public void RestoreOriginal()
    {
        foreach (var item in originalRamps)
        {
            var dc = CreateDCW(item.Key, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (dc == IntPtr.Zero) continue;
            try { SetDeviceGammaRamp(dc, item.Value); }
            finally { DeleteDC(dc); }
        }
        if (amd != null) amd.RestoreOriginal();
    }

    public void Dispose() => amd?.Dispose();

    public static ushort[] BuildRamp(double gamma, double brightness, double contrast)
    {
        gamma = Math.Clamp(gamma, 0.30, 2.80);
        brightness = Math.Clamp(brightness, -0.50, 0.50);
        contrast = Math.Clamp(contrast, 0.50, 2.00);
        var ramp = new ushort[768];
        for (var i = 0; i < 256; i++)
        {
            var value = i / 255.0;
            value = (value - 0.5) * contrast + 0.5 + brightness;
            value = Math.Pow(Math.Clamp(value, 0, 1), 1.0 / gamma);
            var channel = (ushort)Math.Clamp(Math.Round(value * 65535.0), 0, 65535);
            ramp[i] = channel;
            ramp[256 + i] = channel;
            ramp[512 + i] = channel;
        }
        return ramp;
    }

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateDCW")]
    private static extern IntPtr CreateDCW(string driver, IntPtr device, IntPtr output, IntPtr initData);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetDeviceGammaRamp(IntPtr dc, [Out] ushort[] ramp);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetDeviceGammaRamp(IntPtr dc, ushort[] ramp);
}
