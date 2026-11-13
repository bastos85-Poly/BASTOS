using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public static class AdkInstallationService
{
    public const string PatchedBase = "10.1.26100.2454";
    public const string CurrentRelease = "10.1.26100.9457";
    // Microsoft KB5101684 archive retrieved and verified on 2026-10-15.
    public const string PatchArchiveSha256 = "DC19725A2FB0CCE44C32AC14059A85A25257B9534BA21C93B479F4F09FB5AF38";

    public static string? ReadVersion()
    {
        Version? newest = null;
        foreach (var view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var uninstall = machine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
            foreach (string name in uninstall?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                using var entry = uninstall!.OpenSubKey(name);
                if (entry?.GetValue("DisplayName") as string == "Windows Deployment Tools" &&
                    Version.TryParse(entry.GetValue("DisplayVersion") as string, out var version) && (newest == null || version > newest)) newest = version;
            }
        }
        return newest?.ToString();
    }

    public static IReadOnlyList<string> OscdimgCandidates() => new[] {
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
    }.Where(root => !string.IsNullOrWhiteSpace(root)).SelectMany(root => new[] { "amd64", "x86" }.Select(arch =>
        Path.Combine(root, "Windows Kits", "10", "Assessment and Deployment Kit", "Deployment Tools", arch, "Oscdimg", "oscdimg.exe"))).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();

    public static int? ReadPatchState(string patchCode, string productCode)
    {
        if (!Guid.TryParseExact(patchCode, "B", out _) || !Guid.TryParseExact(productCode, "B", out _) || MsiQueryProductStateW(productCode) != 5) return null;
        uint size = 32;
        var value = new StringBuilder((int)size);
        return MsiGetPatchInfoExW(patchCode, productCode, null, 4, "State", value, ref size) == 0 && int.TryParse(value.ToString(), out int state) ? state : null;
    }

    [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MsiQueryProductStateW(string product);
    [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern uint MsiGetPatchInfoExW(string patch, string product, string? sid, uint context, string property, StringBuilder value, ref uint size);
}
