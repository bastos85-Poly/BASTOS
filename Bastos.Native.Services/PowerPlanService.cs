using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace Bastos.Native.Services;

public sealed record PowerPlan(Guid Id, string Name)
{
    public override string ToString() => Name;
    public string Description => Id.ToString() switch
    {
        "381b4222-f694-41f0-9685-ff5bb260df2e" => "Utilisation normale : Windows adapte performances et consommation à votre activité.",
        "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" => "Haute performance : privilégie la réactivité, avec une consommation potentiellement plus élevée.",
        "a1841308-3541-4fab-bc81-f71556f20b4a" => "Économie d’énergie : réduit la consommation en limitant les performances lorsque c’est possible.",
        _ => PowerPlanService.IsZoicAmd(this)
            ? "Profil de performances Zoic pour processeurs AMD, disponible directement dans Bastos."
            : Id == PowerPlanService.BastosAmdId
            ? "Plan AMD téléchargé depuis le projet synez-os/power-synez lors de la première activation. Connexion Internet requise."
            : Name.Contains("9800X3D", StringComparison.OrdinalIgnoreCase)
            ? "Profil Bastos pour le Ryzen 7 9800X3D. Active le plan existant en conservant ses paramètres personnalisés."
            : "Plan personnalisé installé dans Windows. Ses paramètres existants seront conservés."
    };
}

public static class PowerPlanService
{
    public static readonly Guid BalancedId = new("381b4222-f694-41f0-9685-ff5bb260df2e");
    public static readonly Guid PerformanceId = new("8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c");
    public static readonly Guid ZoicAmdId = new("01001011-0100-1111-0101-001188888884");
    public static readonly Guid BastosAmdId = new("22222222-2222-2222-2222-222222222222");
    private const string ZoicName = "Zoic Ultimate Performance (AMD)";
    private const string BastosName = "Bastos Power Plan (AMD)";
    private const string BastosSource = "https://raw.githubusercontent.com/synez-os/power-synez/17171d6445d0a13164edd5063dbe2d393b4b6098/Synez_Public_Power.pow";
    private const string BastosSha256 = "1002321C1A8413BFC6AB26A6608D123FAA028531EA46C40447638954AA10AC44";

    public static bool IsZoicAmd(PowerPlan plan) => plan.Id == ZoicAmdId ||
        plan.Name.Replace(" ", "").Equals("zoic'sultimateperformance(amd)", StringComparison.OrdinalIgnoreCase) ||
        plan.Name.Replace(" ", "").Equals("zoicultimateperformance(amd)", StringComparison.OrdinalIgnoreCase);

    public static Guid ActiveId()
    {
        Check(PowerGetActiveScheme(IntPtr.Zero, out var pointer));
        try { return Marshal.PtrToStructure<Guid>(pointer); }
        finally { LocalFree(pointer); }
    }
    public static IReadOnlyList<PowerPlan> List()
    {
        var plans = Installed().Select(p => p.Id == BalancedId ? p with { Name = "Normal (équilibré)" } :
            p.Id == PerformanceId ? p with { Name = "Performances élevées" } :
            IsZoicAmd(p) ? p with { Name = ZoicName } :
            p.Id == BastosAmdId ? p with { Name = BastosName } : p).ToList();
        if (!plans.Any(p => p.Id == BalancedId)) plans.Add(new PowerPlan(BalancedId, "Normal (équilibré)"));
        if (!plans.Any(p => p.Id == PerformanceId)) plans.Add(new PowerPlan(PerformanceId, "Performances élevées"));
        if (!plans.Any(IsZoicAmd)) plans.Add(new PowerPlan(ZoicAmdId, ZoicName));
        if (!plans.Any(p => p.Id == BastosAmdId)) plans.Add(new PowerPlan(BastosAmdId, BastosName));
        return plans.OrderBy(p => IsZoicAmd(p) ? 2 : p.Id == BastosAmdId ? 3 : Rank(p.Id)).ThenBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    private static IReadOnlyList<PowerPlan> Installed()
    {
        var plans = new List<PowerPlan>();
        for (uint index = 0; ; index++)
        {
            var bytes = new byte[16]; uint size = 16;
            uint code = PowerEnumerate(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 16, index, bytes, ref size);
            if (code == 259) break; // ERROR_NO_MORE_ITEMS
            Check(code);
            var id = new Guid(bytes);
            plans.Add(new PowerPlan(id, ReadName(id)));
        }
        return plans.OrderBy(p => Rank(p.Id)).ThenBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }
    private static int Rank(Guid id) => id.ToString() switch
    {
        "381b4222-f694-41f0-9685-ff5bb260df2e" => 0,
        "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" => 1,
        "a1841308-3541-4fab-bc81-f71556f20b4a" => 3,
        _ => 4
    };
    private static string ReadName(Guid id)
    {
        uint size = 0;
        uint code = PowerReadFriendlyName(IntPtr.Zero, ref id, IntPtr.Zero, IntPtr.Zero, null, ref size);
        if (code != 0 && code != 234) Check(code);
        if (size == 0) return id.ToString();
        var bytes = new byte[size];
        Check(PowerReadFriendlyName(IntPtr.Zero, ref id, IntPtr.Zero, IntPtr.Zero, bytes, ref size));
        return Encoding.Unicode.GetString(bytes).TrimEnd('\0');
    }
    public static NativeActionResult Activate(string value)
    {
        if (!Guid.TryParseExact(value, "D", out var id))
            return new NativeActionResult(false, "Identifiant de plan invalide.", 2);
        var plan = List().FirstOrDefault(p => p.Id == id);
        if (plan == null) return new NativeActionResult(false, "Ce plan n’existe plus. Actualisez la liste.", 2);
        EnsureInstalled(id);
        if (id == BastosAmdId) RenameBastosPlan();
        Check(PowerSetActiveScheme(IntPtr.Zero, ref id));
        return ActiveId() == id
            ? new NativeActionResult(true, "Plan actif : " + plan.Name)
            : new NativeActionResult(false, "Windows ne confirme pas l’activation du plan.", 1);
    }

    // Called by setup without changing the user's current plan. The choices are
    // also created on demand when applying a plan on a fresh Windows installation.
    public static NativeActionResult InstallBundledPlans()
    {
        var before = ActiveId();
        EnsureInstalled(BalancedId);
        EnsureInstalled(PerformanceId);
        if (!Installed().Any(IsZoicAmd)) EnsureInstalled(ZoicAmdId);
        if (ActiveId() != before) throw new InvalidOperationException("Le plan actif a changé pendant l’installation des plans.");
        return new NativeActionResult(true, "Plans Normal, Performances élevées et Zoic AMD installés et vérifiés. Plan actif conservé.");
    }

    private static void EnsureInstalled(Guid id)
    {
        if (Installed().Any(p => p.Id == id)) return;
        if (id != BalancedId && id != PerformanceId && id != ZoicAmdId && id != BastosAmdId)
            throw new InvalidOperationException("Ce plan n’existe plus. Actualisez la liste.");

        var allocated = Marshal.AllocHGlobal(16);
        string? temporary = null;
        try
        {
            Marshal.StructureToPtr(id, allocated, false);
            var destination = allocated;
            uint code;
            if (id == ZoicAmdId || id == BastosAmdId)
            {
                temporary = Path.Combine(Path.GetTempPath(), "BASTOS-Power-" + Guid.NewGuid().ToString("N") + ".pow");
                if (id == BastosAmdId)
                {
                    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
                    var bytes = client.GetByteArrayAsync(BastosSource).GetAwaiter().GetResult();
                    if (!Convert.ToHexString(SHA256.HashData(bytes)).Equals(BastosSha256, StringComparison.Ordinal))
                        throw new InvalidOperationException("Le fichier du plan AMD ne correspond pas à la version vérifiée.");
                    File.WriteAllBytes(temporary, bytes);
                }
                else
                {
                    using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Bastos.PowerPlans.ZoicAMD.pow")
                        ?? throw new InvalidOperationException("Le profil AMD intégré est absent de cette version de Bastos.");
                    using var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                    resource.CopyTo(file);
                }
                code = PowerImportPowerScheme(IntPtr.Zero, temporary, ref destination);
            }
            else
            {
                // Deleted Windows plans are restored individually, preserving
                // every other scheme and its customized settings.
                code = PowerRestoreIndividualDefaultPowerScheme(ref id);
            }
            // A concurrent installer may have created the same fixed identifier.
            if (code != 0 && !Installed().Any(p => p.Id == id)) Check(code);
            if (!Installed().Any(p => p.Id == id)) throw new InvalidOperationException("Windows ne confirme pas l’installation du plan.");
            if (id == BastosAmdId) RenameBastosPlan();
        }
        finally
        {
            Marshal.FreeHGlobal(allocated);
            if (temporary != null) File.Delete(temporary);
        }
    }
    private static void RenameBastosPlan()
    {
        var id = BastosAmdId;
        var bytes = Encoding.Unicode.GetBytes(BastosName + "\0");
        Check(PowerWriteFriendlyName(IntPtr.Zero, ref id, IntPtr.Zero, IntPtr.Zero, bytes, (uint)bytes.Length));
    }
    private static void Check(uint code) { if (code != 0) throw new Win32Exception((int)code); }
    [DllImport("powrprof.dll")] private static extern uint PowerEnumerate(IntPtr root, IntPtr scheme, IntPtr subgroup, uint accessor, uint index, byte[] buffer, ref uint size);
    [DllImport("powrprof.dll")] private static extern uint PowerReadFriendlyName(IntPtr root, ref Guid scheme, IntPtr subgroup, IntPtr setting, byte[]? buffer, ref uint size);
    [DllImport("powrprof.dll")] private static extern uint PowerWriteFriendlyName(IntPtr root, ref Guid scheme, IntPtr subgroup, IntPtr setting, byte[] buffer, uint size);
    [DllImport("powrprof.dll")] private static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
    [DllImport("powrprof.dll")] private static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
    [DllImport("powrprof.dll")] private static extern uint PowerRestoreIndividualDefaultPowerScheme(ref Guid scheme);
    [DllImport("powrprof.dll", CharSet = CharSet.Unicode)] private static extern uint PowerImportPowerScheme(IntPtr root, string path, ref IntPtr destination);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr pointer);
}
