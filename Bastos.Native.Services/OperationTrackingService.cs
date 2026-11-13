using System;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record OperationTracking(string Status, string Guidance, bool Interrupted = false,
    bool RestartPending = false, bool RestartObserved = false, bool Unknown = false, bool ExternalUnconfirmed = false);

public static class OperationTrackingService
{
    private static readonly Lazy<Task<string?>> boot = new(() => Task.Run(ReadWindowsBootStamp));
    public static string BootReadError { get; private set; } = "";
    public static string? CurrentBootStamp => boot.Value.IsCompletedSuccessfully ? boot.Value.Result : null;

    // A failed/slow WMI provider must not prevent the UI or an operation from starting.
    public static async Task<string?> ReadBootAsync()
    {
        var probe = boot.Value;
        return await Task.WhenAny(probe, Task.Delay(2000)) == probe ? await probe : null;
    }

    public static DateTime? ProcessStartedUtc()
    {
        try { using var process = Process.GetCurrentProcess(); return process.StartTime.ToUniversalTime(); }
        catch { return null; }
    }

    public static OperationTracking Evaluate(OperationResult result, string? currentBoot,
        Func<int, DateTime, bool?>? ownerAlive = null)
    {
        if (result.State == OperationState.Running)
        {
            if (result.OwnerProcessId <= 0 || result.OwnerProcessStartedUtc == null)
                return new("Fin non enregistrée", "Ce rapport ancien ne permet pas d’identifier le processus de lancement. Vérifiez l’état de l’outil avant de relancer l’action.", Unknown: true);
            bool? alive = (ownerAlive ?? IsOwnerAlive)(result.OwnerProcessId, result.OwnerProcessStartedUtc.Value);
            if (alive == true)
                return new("En cours", "Le processus Bastos qui suit cette opération est toujours présent. Attendez sa fin puis actualisez le journal.");
            if (alive == false)
                return new("Suivi interrompu", "Le processus Bastos qui suivait cette opération n’est plus présent. Son résultat final n’a pas été enregistré. Un outil externe peut encore travailler : vérifiez son état et les fichiers produits avant toute nouvelle tentative.", Interrupted: true);
            return new("État à vérifier", "Windows ne permet pas de confirmer si le processus Bastos d’origine est encore actif. Ne relancez pas l’action avant de vérifier l’état de l’outil.", Unknown: true);
        }
        if (result.RestartRequired || result.ErrorCode == "ADK_RESTART_REQUIRED")
        {
            if (string.IsNullOrEmpty(result.BootStamp) || string.IsNullOrEmpty(currentBoot))
                return new("Redémarrage à vérifier", "Cette opération a demandé un redémarrage. Le dernier démarrage Windows ne peut pas être comparé au lancement. Vérifiez que Windows a bien redémarré puis relancez la vérification de l’outil.", RestartPending: true);
            if (result.BootStamp == currentBoot)
                return new("Redémarrage nécessaire", "Enregistrez votre travail puis redémarrez Windows depuis le menu Démarrer. Relancez ensuite la vérification de l’outil dans Bastos avant de poursuivre.", RestartPending: true);
            return new("Redémarrage effectué · à vérifier", "Un nouveau démarrage Windows est constaté depuis cette opération. Le résultat de l’installation reste à vérifier dans le module concerné ; aucun succès n’a été déduit du redémarrage.", RestartObserved: true);
        }
        if (result.ActionCompletionUnconfirmed || !result.ProcessStopped)
        {
            if (!string.IsNullOrEmpty(result.BootStamp) && !string.IsNullOrEmpty(currentBoot) && result.BootStamp != currentBoot)
                return new("Après redémarrage · à vérifier", "Windows a redémarré depuis l’arrêt non confirmé de cet outil. Vérifiez le résultat dans le module concerné avant de continuer.", RestartObserved: true);
            return new("Fin de l’outil à vérifier", "Le rapport ne confirme pas l’arrêt de l’outil externe. Il peut encore travailler même si Bastos a été fermé. Vérifiez son état avant toute nouvelle tentative.", ExternalUnconfirmed: true);
        }
        return new("", "");
    }

    private static bool? IsOwnerAlive(int id, DateTime started)
    {
        try
        {
            using var process = Process.GetProcessById(id);
            return !process.HasExited && process.StartTime.ToUniversalTime() == started.ToUniversalTime();
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch { return null; }
    }

    // Local, read-only WMI scripting API; no PowerShell worker or system changes.
    private static string? ReadWindowsBootStamp()
    {
        object? locator = null, services = null, rows = null;
        try
        {
            var type = Type.GetTypeFromProgID("WbemScripting.SWbemLocator");
            if (type == null) return null;
            locator = Activator.CreateInstance(type);
            services = ((dynamic)locator!).ConnectServer(".", @"root\cimv2");
            rows = ((dynamic)services).ExecQuery("SELECT LastBootUpTime FROM Win32_OperatingSystem", "WQL", 0);
            if (((dynamic)rows).Count > 0)
            {
                object row = ((dynamic)rows).ItemIndex(0);
                object? properties = null, property = null;
                try
                {
                    properties = ((dynamic)row).Properties_;
                    property = ((dynamic)properties).Item("LastBootUpTime");
                    string value = Convert.ToString(((dynamic)property).Value) ?? "";
                    // Preserve WMI's boot timestamp; do not estimate it from the current clock/uptime.
                    if (value.Length != 25 || value.Contains('*') || value[21] is not ('+' or '-')) return null;
                    var local = DateTime.ParseExact(value[..21], "yyyyMMddHHmmss.ffffff", CultureInfo.InvariantCulture);
                    int offset = int.Parse(value[22..], CultureInfo.InvariantCulture) * (value[21] == '-' ? -1 : 1);
                    return new DateTimeOffset(local, TimeSpan.FromMinutes(offset)).UtcDateTime.Ticks.ToString(CultureInfo.InvariantCulture);
                }
                finally { Release(property); Release(properties); Release(row); }
            }
        }
        catch (Exception error) { BootReadError = error.ToString(); }
        finally { Release(rows); Release(services); Release(locator); }
        return null;
    }

    private static void Release(object? value)
    {
        try { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
        catch (Exception error) { BootReadError = error.Message; }
    }
}
