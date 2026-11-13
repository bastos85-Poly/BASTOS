using System;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public static class WebView2RuntimeService
{
    public const string ClientKey = @"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";

    public static bool IsInstalledVersion(string? text) => Version.TryParse(text, out var version) && version > new Version(0, 0, 0, 0);

    public static string? ReadVersion()
    {
        Version? newest = null;
        foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
        foreach (var view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            try
            {
                using var root = RegistryKey.OpenBaseKey(hive, view);
                using var key = root.OpenSubKey(ClientKey);
                string? text = key?.GetValue("pv") as string;
                if (IsInstalledVersion(text) && Version.TryParse(text, out var version) && (newest == null || version > newest)) newest = version;
            }
            catch (Exception error) when (error is System.Security.SecurityException or UnauthorizedAccessException or System.IO.IOException) { }
        }
        return newest?.ToString();
    }
}
