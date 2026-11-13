using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;

namespace Bastos.Native.Services;

public enum DisplayDial { Brightness, Contrast, Gamma, Vibrance }

public sealed class DisplayCalibrationController : INotifyPropertyChanged, IDisposable
{
    private readonly DisplayColorService colors = new();
    private readonly string exfilExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EXFIL", "exfil-v2.exe");
    private readonly string presetsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "exfil-v2", "presets.json");
    private readonly string nativePresetPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "DisplayCalibration.json");
    private string? originalPresets;
    private string? bastosSlot;
    private bool ownsDisplay;
    private bool hasApplied;
    private bool hasPendingChanges;
    private double savedGamma;
    private double savedBrightness;
    private double savedContrast;
    private int savedVibrance;
    private bool disposed;
    private EventWaitHandle? editingEvent;
    private string status = "Prêt";
    private double gamma = 1.0;
    private double brightness;
    private double contrast = 1.0;
    private int vibrance;

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? ValuesChanged;

    public double Gamma => gamma;
    public double Brightness => brightness;
    public double Contrast => contrast;
    public int Vibrance => vibrance;
    public int VibranceMinimum { get; private set; }
    public int VibranceMaximum { get; private set; } = 200;
    public int VibranceDefault { get; private set; } = 100;
    public bool VibranceAvailable { get; private set; }
    public bool OwnsDisplay => ownsDisplay;
    public bool HasPendingChanges => hasPendingChanges;
    public string Status { get => status; private set { status = value; Notify(nameof(Status)); } }

    public DisplayCalibrationController()
    {
        var info = colors.Vibrance;
        if (info.HasValue)
        {
            VibranceAvailable = true;
            VibranceMinimum = info.Value.Minimum;
            VibranceMaximum = info.Value.Maximum;
            VibranceDefault = info.Value.Default;
            vibrance = info.Value.Current;
        }
        LoadCurrentExfilPreset();
        if (!File.Exists(exfilExe) && !Environment.GetCommandLineArgs().Contains("--smoke-test")) LoadNativePreset();
        RememberSavedValues();
        Status = File.Exists(exfilExe)
            ? "EXFIL est installé. Les essais restent provisoires jusqu'à Enregistrer ; fermer BASTOS restaure le dernier profil enregistré."
            : "Les essais restent provisoires jusqu'à Enregistrer. Le profil enregistré est conservé après la fermeture de BASTOS.";
    }

    private void LoadCurrentExfilPreset()
    {
        if (!File.Exists(presetsPath)) return;
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(presetsPath)) as JsonObject;
            var active = root?["active"]?.GetValue<string>();
            var preset = (root?["presets"] as JsonArray)?.OfType<JsonObject>()
                .FirstOrDefault(item => item["slot"]?.GetValue<string>() == active);
            if (preset?["dials"] is not JsonObject dials || active == "Normal") return;
            gamma = Math.Clamp(dials["gamma"]?.GetValue<double>() ?? gamma, 0.30, 2.80);
            brightness = Math.Clamp(dials["brightness"]?.GetValue<double>() ?? brightness, -0.50, 0.50);
            contrast = Math.Clamp(dials["contrast"]?.GetValue<double>() ?? contrast, 0.50, 2.00);
            if (VibranceAvailable)
                vibrance = Math.Clamp(preset["vibrance"]?.GetValue<int>() ?? vibrance, VibranceMinimum, VibranceMaximum);
        }
        catch { /* Current values remain neutral if EXFIL's file is malformed. */ }
    }

    private void LoadNativePreset()
    {
        if (!File.Exists(nativePresetPath)) return;
        try
        {
            var preset = JsonSerializer.Deserialize<NativeDisplayPreset>(File.ReadAllText(nativePresetPath));
            if (preset == null || !double.IsFinite(preset.Gamma) || !double.IsFinite(preset.Brightness) || !double.IsFinite(preset.Contrast)) return;
            gamma = Math.Clamp(preset.Gamma, 0.30, 2.80);
            brightness = Math.Clamp(preset.Brightness, -0.50, 0.50);
            contrast = Math.Clamp(preset.Contrast, 0.50, 2.00);
            if (VibranceAvailable) vibrance = Math.Clamp(preset.Vibrance, VibranceMinimum, VibranceMaximum);
            colors.Apply(gamma, brightness, contrast, vibrance);
            hasApplied = true;
        }
        catch { /* Invalid or unsupported saved profiles do not block the screen page. */ }
    }

    public bool Adjust(DisplayDial dial, int direction)
    {
        var nextGamma = gamma;
        var nextBrightness = brightness;
        var nextContrast = contrast;
        var nextVibrance = vibrance;
        switch (dial)
        {
            case DisplayDial.Gamma: nextGamma = Math.Round(Math.Clamp(gamma + direction * 0.01, 0.30, 2.80), 2); break;
            case DisplayDial.Brightness: nextBrightness = Math.Round(Math.Clamp(brightness + direction * 0.01, -0.50, 0.50), 2); break;
            case DisplayDial.Contrast: nextContrast = Math.Round(Math.Clamp(contrast + direction * 0.01, 0.50, 2.00), 2); break;
            case DisplayDial.Vibrance:
                if (!VibranceAvailable) { Status = "Le pilote de cet écran ne fournit pas de réglage de vibrance."; return false; }
                nextVibrance = Math.Clamp(vibrance + direction * 1, VibranceMinimum, VibranceMaximum);
                break;
        }
        return Set(nextGamma, nextBrightness, nextContrast, nextVibrance);
    }

    public bool ResetNeutral() => Set(1.0, 0.0, 1.0, VibranceDefault);

    public bool Set(double nextGamma, double nextBrightness, double nextContrast, int nextVibrance)
    {
        if (disposed) return false;
        nextGamma = Math.Clamp(Math.Round(nextGamma, 2), 0.30, 2.80);
        nextBrightness = Math.Clamp(Math.Round(nextBrightness, 2), -0.50, 0.50);
        nextContrast = Math.Clamp(Math.Round(nextContrast, 2), 0.50, 2.00);
        nextVibrance = Math.Clamp(nextVibrance, VibranceMinimum, VibranceMaximum);
        var oldGamma = gamma;
        var oldBrightness = brightness;
        var oldContrast = contrast;
        var oldVibrance = vibrance;
        try
        {
            TakeControl();
            colors.Apply(nextGamma, nextBrightness, nextContrast, nextVibrance);
            gamma = nextGamma;
            brightness = nextBrightness;
            contrast = nextContrast;
            vibrance = nextVibrance;
            hasApplied = true;
            hasPendingChanges = gamma != savedGamma || brightness != savedBrightness || contrast != savedContrast || vibrance != savedVibrance;
            Status = hasPendingChanges
                ? $"Essai provisoire · gamma {gamma:F2} · luminosité {brightness:+0.00;-0.00;0.00} · contraste {contrast:F2} · vibrance {vibrance}. Vérifie le bureau avant d'enregistrer."
                : "Valeurs du dernier profil enregistré (essai non enregistré).";
            ValuesChanged?.Invoke(this, EventArgs.Empty);
            return true;
        }
        catch (Exception error)
        {
            gamma = oldGamma;
            brightness = oldBrightness;
            contrast = oldContrast;
            vibrance = oldVibrance;
            try
            {
                if (hasApplied) colors.Apply(gamma, brightness, contrast, vibrance);
                else
                {
                    colors.RestoreOriginal();
                    if (originalPresets != null) WritePresets(originalPresets);
                    ownsDisplay = false;
                    StartExfil();
                }
            }
            catch { }
            Status = "Réglage non appliqué : " + error.Message;
            return false;
        }
    }

    public void RestorePrevious()
    {
        if (!ownsDisplay) return;
        try
        {
            if (!File.Exists(exfilExe) && File.Exists(nativePresetPath))
            {
                gamma = savedGamma;
                brightness = savedBrightness;
                contrast = savedContrast;
                vibrance = savedVibrance;
                colors.Apply(gamma, brightness, contrast, vibrance);
                hasPendingChanges = false;
                hasApplied = true;
                editingEvent?.Reset();
                ValuesChanged?.Invoke(this, EventArgs.Empty);
                Status = "Dernier profil enregistré restauré.";
                return;
            }
            colors.RestoreOriginal();
            if (originalPresets != null) WritePresets(originalPresets);
            ownsDisplay = false;
            hasApplied = false;
            hasPendingChanges = false;
            StartExfil();
            gamma = 1.0;
            brightness = 0.0;
            contrast = 1.0;
            vibrance = colors.Vibrance?.Default ?? vibrance;
            LoadCurrentExfilPreset();
            RememberSavedValues();
            ValuesChanged?.Invoke(this, EventArgs.Empty);
            Status = "Dernier profil enregistré restauré.";
        }
        catch (Exception error) { Status = "Restauration incomplète : " + error.Message; }
    }

    public bool SaveCurrent()
    {
        if (disposed || !ownsDisplay || !hasApplied)
        {
            Status = "Aucun essai à enregistrer.";
            return false;
        }
        try
        {
            if (File.Exists(exfilExe)) SaveBastosPreset();
            else
            {
                SaveNativePreset();
                DisplayProfileAgent.RegisterAndStart();
            }
            originalPresets = File.Exists(presetsPath) ? File.ReadAllText(presetsPath) : null;
            RememberSavedValues();
            hasPendingChanges = false;
            editingEvent?.Reset();
            Status = File.Exists(exfilExe)
                ? "Réglages enregistrés. EXFIL les reprendra à la fermeture de BASTOS."
                : "Réglages enregistrés. Ils resteront actifs à la fermeture de BASTOS.";
            return true;
        }
        catch (Exception error)
        {
            Status = "Enregistrement impossible : " + error.Message;
            return false;
        }
    }

    private void SaveNativePreset()
    {
        var directory = Path.GetDirectoryName(nativePresetPath) ?? throw new InvalidOperationException("Dossier du profil introuvable.");
        Directory.CreateDirectory(directory);
        var temp = nativePresetPath + ".tmp";
        var json = JsonSerializer.Serialize(new NativeDisplayPreset(gamma, brightness, contrast, vibrance));
        File.WriteAllText(temp, json);
        File.Move(temp, nativePresetPath, true);
    }

    private sealed record NativeDisplayPreset(double Gamma, double Brightness, double Contrast, int Vibrance);

    private void RememberSavedValues()
    {
        savedGamma = gamma;
        savedBrightness = brightness;
        savedContrast = contrast;
        savedVibrance = vibrance;
    }

    private void TakeControl()
    {
        editingEvent ??= new EventWaitHandle(false, EventResetMode.ManualReset, DisplayProfileAgent.EditingEvent);
        editingEvent.Set();
        if (ownsDisplay)
        {
            StopExfil();
            return;
        }
        if (File.Exists(presetsPath))
        {
            originalPresets = File.ReadAllText(presetsPath);
            var backupDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "Backups");
            Directory.CreateDirectory(backupDirectory);
            var backup = Path.Combine(backupDirectory, "EXFIL-presets-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture) + ".json");
            File.WriteAllText(backup, originalPresets);
        }
        StopExfil();
        ownsDisplay = true;
    }

    private void StopExfil()
    {
        foreach (var process in Process.GetProcessesByName("exfil-v2"))
        {
            using (process)
            {
                var path = process.MainModule?.FileName;
                if (!string.Equals(path, exfilExe, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Une autre instance EXFIL est active ; ferme-la avant le réglage.");
                process.Kill();
                if (!process.WaitForExit(5000)) throw new InvalidOperationException("EXFIL n'a pas pu être mis en pause.");
            }
        }
    }

    private void SaveBastosPreset()
    {
        if (!File.Exists(exfilExe) || !File.Exists(presetsPath)) return;
        var root = JsonNode.Parse(File.ReadAllText(presetsPath)) as JsonObject
            ?? throw new InvalidOperationException("Fichier de profils EXFIL illisible.");
        var presets = root["presets"] as JsonArray ?? throw new InvalidOperationException("Liste de profils EXFIL absente.");
        var preset = presets.OfType<JsonObject>().FirstOrDefault(item => item["slot"]?.GetValue<string>() == bastosSlot)
            ?? presets.OfType<JsonObject>().FirstOrDefault(item => item["name"]?.GetValue<string>() == "BASTOS Écran" && item["exe"] == null);
        if (preset == null)
        {
            var id = root["next_id"]?.GetValue<int>() ?? 1;
            bastosSlot = "p" + id.ToString(CultureInfo.InvariantCulture);
            root["next_id"] = id + 1;
            preset = new JsonObject { ["slot"] = bastosSlot, ["name"] = "BASTOS Écran", ["exe"] = null };
            presets.Add(preset);
        }
        bastosSlot = preset["slot"]?.GetValue<string>();
        preset["dials"] = new JsonObject { ["gamma"] = gamma, ["brightness"] = brightness, ["contrast"] = contrast };
        preset["vibrance"] = vibrance;
        root["active"] = bastosSlot;
        WritePresets(root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private void WritePresets(string json)
    {
        var directory = Path.GetDirectoryName(presetsPath) ?? throw new InvalidOperationException("Dossier EXFIL introuvable.");
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, "presets.bastos.tmp");
        File.WriteAllText(temp, json);
        if (File.Exists(presetsPath)) File.Replace(temp, presetsPath, null);
        else File.Move(temp, presetsPath);
    }

    private void StartExfil()
    {
        if (!File.Exists(exfilExe) || Process.GetProcessesByName("exfil-v2").Length > 0) return;
        Process.Start(new ProcessStartInfo(exfilExe, "--hidden") { UseShellExecute = true,
            WorkingDirectory = Path.GetDirectoryName(exfilExe) ?? string.Empty });
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (ownsDisplay)
        {
            try
            {
                if (File.Exists(exfilExe))
                {
                    colors.RestoreOriginal();
                    if (originalPresets != null) WritePresets(originalPresets);
                    StartExfil();
                }
                else if (hasPendingChanges)
                {
                    if (File.Exists(nativePresetPath)) colors.Apply(savedGamma, savedBrightness, savedContrast, savedVibrance);
                    else colors.RestoreOriginal();
                }
            }
            catch { colors.RestoreOriginal(); }
        }
        colors.Dispose();
        editingEvent?.Reset();
        editingEvent?.Dispose();
    }

    private void Notify(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
