using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace Bastos.Native.Services;

internal static class DisplayProfileAgent
{
    internal const string EditingEvent = @"Local\BASTOS-DisplayCalibration-Editing";
    private const string AgentMutex = @"Local\BASTOS-DisplayProfile-Agent";
    private static readonly string ProfilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "DisplayCalibration.json");

    internal static void RegisterAndStart()
    {
        var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Chemin de Bastos introuvable.");
        using (var run = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true)
            ?? throw new InvalidOperationException("Démarrage de session Windows indisponible."))
            run.SetValue("BASTOS Display Profile", $"\"{executable}\" --display-profile-agent", RegistryValueKind.String);
        Process.Start(new ProcessStartInfo(executable, "--display-profile-agent") { UseShellExecute = false, CreateNoWindow = true });
    }

    internal static async Task RunAsync()
    {
        using var singleton = new Mutex(false, AgentMutex);
        if (!singleton.WaitOne(0)) return;
        try
        {
            using var colors = new DisplayColorService();
            while (true)
            {
                try
                {
                    if (File.Exists(ProfilePath) && !IsEditing())
                    {
                        var profile = JsonSerializer.Deserialize<Profile>(File.ReadAllText(ProfilePath));
                        if (profile != null && Valid(profile) && !colors.Matches(profile.Gamma, profile.Brightness, profile.Contrast, profile.Vibrance))
                            colors.Apply(profile.Gamma, profile.Brightness, profile.Contrast, profile.Vibrance);
                    }
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                catch (JsonException) { }
                catch (InvalidOperationException) { }
                await Task.Delay(TimeSpan.FromSeconds(3));
            }
        }
        finally { singleton.ReleaseMutex(); }
    }

    private static bool IsEditing()
    {
        try
        {
            using var editing = EventWaitHandle.OpenExisting(EditingEvent);
            return editing.WaitOne(0);
        }
        catch (WaitHandleCannotBeOpenedException) { return false; }
    }

    private static bool Valid(Profile p) => double.IsFinite(p.Gamma) && p.Gamma is >= 0.30 and <= 2.80 &&
        double.IsFinite(p.Brightness) && p.Brightness is >= -0.50 and <= 0.50 &&
        double.IsFinite(p.Contrast) && p.Contrast is >= 0.50 and <= 2.00 && p.Vibrance is >= 0 and <= 200;

    private sealed record Profile(double Gamma, double Brightness, double Contrast, int Vibrance);
}
