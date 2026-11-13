using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;
using Bastos.Native.Models;

public sealed class NetworkCapability
{
    public string Key { get; set; } = "";
    public string Label { get; set; } = "";
    public bool Supported { get; set; }
    public string Current { get; set; } = "";
    public string Target { get; set; } = "";
    public bool LowOnly { get; set; }
}

public sealed class NetworkAdapterProfile
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string Driver { get; set; } = "";
    public string Status { get; set; } = "";
    public string State { get; set; } = "";
    public bool CanApply { get; set; }
    public bool CanRestore { get; set; }
    public NetworkCapability[] Capabilities { get; set; } = Array.Empty<NetworkCapability>();
    public string DisplayName => Name + " — " + Description;
    public override string ToString() => DisplayName;
}

public sealed class NetworkOptimizationViewModel : ObservableObject
{
    private readonly AppPaths paths;
    private readonly PowerShellWorkerService workers;
    private readonly OperationLogService log;
    private NetworkAdapterProfile? selectedAdapter;
    private string selectedProfile = "Stable";
    private string status = "Détection des cartes Ethernet…";
    private bool busy;
    private IpModeSnapshot ipModes = new();
    private string ipStatus = "Lecture des modes IP…";

    public ObservableCollection<NetworkAdapterProfile> Adapters { get; } = new();
    public string[] Profiles { get; } = { "Stable", "Faible latence (expérimental)" };
    public AsyncRelayCommand RefreshCommand { get; }
    public AsyncRelayCommand ApplyCommand { get; }
    public AsyncRelayCommand RestoreCommand { get; }
    public AsyncRelayCommand PreferApplyCommand { get; }
    public AsyncRelayCommand PreferRestoreCommand { get; }
    public AsyncRelayCommand OnlyApplyCommand { get; }
    public AsyncRelayCommand OnlyRestoreCommand { get; }
    public SettingSwitchModel ProfileSwitch {get;}
    public SettingSwitchModel PreferSwitch {get;}
    public SettingSwitchModel OnlySwitch {get;}
    public string IpStatus { get => ipStatus; private set => SetProperty(ref ipStatus, value); }
    public string PreferState => ipModes.PreferState;
    private IpAdapterMode? SelectedIpAdapter => ipModes.Adapters.FirstOrDefault(a => a.Id == SelectedAdapter?.Id);
    public string OnlyState => SelectedIpAdapter?.State ?? "Sélectionne une carte Ethernet détectée.";
    public string OnlyTarget => SelectedAdapter == null ? "Aucune carte Ethernet sélectionnée" : "Carte concernée : " + SelectedAdapter.DisplayName;
    public string OnlyDetails => string.Join(Environment.NewLine, (SelectedIpAdapter?.Bindings ?? Array.Empty<IpBindingState>()).Select(b =>
        "• " + b.DisplayName + " (" + b.ComponentID + ") : " + (b.Enabled ? "activé" : "désactivé") + " → " + (b.ComponentID == "ms_tcpip" ? "activé" : "désactivé")));
    public bool IsAvailable => !busy;
    public string Status { get => status; private set => SetProperty(ref status, value); }
    public NetworkAdapterProfile? SelectedAdapter
    {
        get => selectedAdapter;
        set { if (SetProperty(ref selectedAdapter, value)) UpdateSelection(); }
    }
    public string SelectedProfile
    {
        get => selectedProfile;
        set { if (SetProperty(ref selectedProfile, value)) UpdateSelection(); }
    }
    private bool LowLatency => SelectedProfile != "Stable";
    public string AdapterState => SelectedAdapter == null ? "Aucune carte sélectionnée" :
        SelectedAdapter.State + " — pilote " + SelectedAdapter.Driver;
    public string Details => SelectedAdapter == null ? "Aucune carte Ethernet physique détectée. Le Wi-Fi et les cartes virtuelles sont exclus." :
        string.Join(Environment.NewLine, SelectedAdapter.Capabilities.Select(c =>
            !c.Supported ? "• " + c.Label + " : ignoré (prise en charge non vérifiable)" :
            c.LowOnly && !LowLatency ? "• " + c.Label + " : conservée, ou restaurée après Faible latence" :
            "• " + c.Label + " : " + DescribeValue(c.Current) + " → " + DescribeValue(c.Target)));
    private static string DescribeValue(string value) => value switch
    {
        "0" or "Disabled" => "désactivé", "1" or "Enabled" => "activé", _ => value
    };
    private bool CanApply() => !busy && SelectedAdapter?.CanApply == true &&
        SelectedAdapter.Status != "Disabled" &&
        SelectedAdapter.Capabilities.Any(c => c.Supported && (!c.LowOnly || LowLatency)) &&
        (!LowLatency || SelectedAdapter.Capabilities.Any(c => c.Key == "*InterruptModeration" && c.Supported));

    private string NetworkWaitingReason => "Une opération réseau est en cours. Attends sa fin.";
    private string ApplyDisabledReason => busy ? NetworkWaitingReason : SelectedAdapter == null ? "Détecte puis choisis une carte Ethernet physique."
        : SelectedAdapter.Status == "Disabled" ? "Cette carte est désactivée dans Windows. Active-la puis actualise la détection."
        : LowLatency && !SelectedAdapter.Capabilities.Any(c => c.Key == "*InterruptModeration" && c.Supported) ? "Le pilote ne confirme pas la prise en charge de ce profil. Choisis Stable."
        : "Le pilote ne confirme aucun réglage applicable pour ce choix. Actualise la détection ou choisis une autre carte.";
    public NetworkOptimizationViewModel(AppPaths paths, PowerShellWorkerService workers, OperationLogService log)
    {
        this.paths = paths; this.workers = workers; this.log = log;
        RefreshCommand = new AsyncRelayCommand(RefreshAsync, () => !busy, () => NetworkWaitingReason);
        ApplyCommand = new AsyncRelayCommand(() => ChangeAsync(false), CanApply, () => ApplyDisabledReason);
        RestoreCommand = new AsyncRelayCommand(() => ChangeAsync(true), () => !busy && SelectedAdapter?.CanRestore == true, () => busy ? NetworkWaitingReason : SelectedAdapter == null ? "Choisis une carte Ethernet." : "Aucune sauvegarde de profil à restaurer pour cette carte.");
        PreferApplyCommand = new AsyncRelayCommand(() => ChangeIpAsync("PreferApply"), () => !busy && ipModes.CanPreferApply, () => busy ? NetworkWaitingReason : "Ce mode est déjà actif ou incompatible avec l’état IP actuel. Consulte l’état ci-dessus et restaure le mode actif avant de changer.");
        PreferRestoreCommand = new AsyncRelayCommand(() => ChangeIpAsync("PreferRestore"), () => !busy && ipModes.CanPreferRestore, () => busy ? NetworkWaitingReason : "Aucune sauvegarde du mode de préférence IP à restaurer.");
        OnlyApplyCommand = new AsyncRelayCommand(() => ChangeIpAsync("OnlyApply"), () => !busy && SelectedIpAdapter?.CanApply == true, () => busy ? NetworkWaitingReason : SelectedAdapter == null ? "Choisis une carte Ethernet." : "Ce mode est déjà actif ou non applicable à cette carte. Consulte son état et restaure le mode actif avant de changer.");
        OnlyRestoreCommand = new AsyncRelayCommand(() => ChangeIpAsync("OnlyRestore"), () => !busy && SelectedIpAdapter?.CanRestore == true, () => busy ? NetworkWaitingReason : SelectedAdapter == null ? "Choisis une carte Ethernet." : "Aucune sauvegarde des liaisons IP à restaurer pour cette carte.");
        ProfileSwitch=new("Profil Ethernet",ApplyCommand,RestoreCommand,()=>SelectedAdapter==null?null:SelectedAdapter.CanRestore);
        PreferSwitch=new("Préférer IPv4",PreferApplyCommand,PreferRestoreCommand,()=>ipModes.CanPreferRestore?true:ipModes.CanPreferApply?false:null);
        OnlySwitch=new("IPv4 uniquement",OnlyApplyCommand,OnlyRestoreCommand,()=>SelectedIpAdapter==null?null:SelectedIpAdapter.CanRestore?true:SelectedIpAdapter.CanApply?false:null);
    }
    private void UpdateSelection()
    {
        RaisePropertyChanged(nameof(AdapterState)); RaisePropertyChanged(nameof(Details));
        ApplyCommand.RaiseCanExecuteChanged(); RestoreCommand.RaiseCanExecuteChanged();
        RaisePropertyChanged(nameof(PreferState)); RaisePropertyChanged(nameof(OnlyState)); RaisePropertyChanged(nameof(OnlyTarget)); RaisePropertyChanged(nameof(OnlyDetails));
        PreferApplyCommand.RaiseCanExecuteChanged(); PreferRestoreCommand.RaiseCanExecuteChanged();
        OnlyApplyCommand.RaiseCanExecuteChanged(); OnlyRestoreCommand.RaiseCanExecuteChanged();
        ProfileSwitch?.Refresh();PreferSwitch?.Refresh();OnlySwitch?.Refresh();
    }
    private void SetBusy(bool value)
    {
        busy = value; RaisePropertyChanged(nameof(IsAvailable)); UpdateSelection(); RefreshCommand.RaiseCanExecuteChanged();
    }
    public async Task RefreshAsync()
    {
        if (busy) return;
        SetBusy(true); Status = "Lecture des capacités, sans modification…";
        try { await ReadAdaptersAsync(); }
        catch (Exception ex) { Adapters.Clear(); SelectedAdapter = null; LoadIpState(new()); Status = "Détection impossible : " + ex.Message; }
        finally { SetBusy(false); }
    }
    private async Task ReadAdaptersAsync()
    {
        using JsonDocument result = await RunAsync("Get", null, null);
        if (!result.RootElement.GetProperty("Success").GetBoolean()) throw new InvalidOperationException(result.RootElement.GetProperty("Message").GetString());
        string? previous = SelectedAdapter?.Id;
        var found = JsonSerializer.Deserialize<NetworkAdapterProfile[]>(result.RootElement.GetProperty("Adapters").GetRawText()) ?? Array.Empty<NetworkAdapterProfile>();
        Adapters.Clear(); foreach (var item in found) Adapters.Add(item);
        SelectedAdapter = Adapters.FirstOrDefault(a => a.Id == previous) ?? Adapters.FirstOrDefault(a => a.Status == "Up") ?? Adapters.FirstOrDefault();
        Status = Adapters.Count == 0 ? "Aucune carte Ethernet physique détectée." : "Détection terminée. Rien n’est activé automatiquement.";
        try
        {
            using var ip = await RunAsync("Get", null, null, "Manage-BASTOS-IPModes.ps1");
            if (!ip.RootElement.GetProperty("Success").GetBoolean()) throw new InvalidOperationException(ip.RootElement.GetProperty("Message").GetString());
            LoadIpState(JsonSerializer.Deserialize<IpModeSnapshot>(ip.RootElement.GetProperty("State").GetRawText()) ?? new());
            IpStatus = "Modes séparés : restaure le mode actif avant d’activer l’autre. Les profils Stable / Faible latence restent indépendants.";
        }
        catch (Exception ex) { LoadIpState(new()); IpStatus = "Lecture IP impossible : " + ex.Message; }
    }
    private async Task ChangeAsync(bool restore)
    {
        var adapter = SelectedAdapter;
        if (adapter == null || busy) return;
        string profile = LowLatency ? "LowLatency" : "Stable";
        string warning = restore ? "Restaurer les valeurs sauvegardées par Bastos pour cette carte ?" :
            "Activer le profil « " + SelectedProfile + " » sur cette carte uniquement ?\n\n" + Details +
            "\n\nLes économies d’énergie désactivées peuvent augmenter la consommation." +
            (LowLatency ? " La désactivation de la modération des interruptions peut augmenter la charge CPU, sans gain de latence garanti." : "");
        if (MessageBox.Show(adapter.DisplayName + "\n\n" + warning +
            "\n\nLa carte pourra redémarrer et couper la connexion quelques instants. Évite cette opération pendant une session distante ou un téléchargement important.",
            "Profil Ethernet Bastos", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        SetBusy(true); Status = restore ? "Restauration des valeurs initiales…" : "Sauvegarde et activation…";
        string outcome;
        try
        {
            using JsonDocument result = await RunAsync(restore ? "Restore" : "Apply", adapter.Id, profile);
            bool success = result.RootElement.GetProperty("Success").GetBoolean();
            outcome = (success ? "" : "Échec — ") + result.RootElement.GetProperty("Message").GetString();
            log.Write("Ethernet", adapter.Description + " : " + outcome, !success);
        }
        catch (Exception ex) { outcome = "Échec — " + ex.Message; log.Write("Ethernet", outcome, true); }
        try { await ReadAdaptersAsync(); }
        catch (Exception ex) { Adapters.Clear(); SelectedAdapter = null; LoadIpState(new()); outcome += " — Actualisation impossible : " + ex.Message; }
        Status = outcome; SetBusy(false);
    }
    public void LoadIpState(IpModeSnapshot snapshot) { ipModes = snapshot; UpdateSelection(); }

    private async Task ChangeIpAsync(string action)
    {
        if (busy) return;
        bool only = action.StartsWith("Only", StringComparison.Ordinal);
        bool restore = action.EndsWith("Restore", StringComparison.Ordinal);
        string? adapterId = only ? SelectedAdapter?.Id : null;
        if (only && adapterId == null) return;
        string title = only ? "IPv4 uniquement — avancé" : "Préférer IPv4";
        string warning = restore ? "Restaurer les valeurs sauvegardées avant l’activation de ce mode ? Les autres réglages ne seront pas remis à zéro." :
            only ? "Sur la carte sélectionnée uniquement : activer IPv4 et désactiver IPv6, le client et le partage Microsoft, la découverte LLTD, LLDP, le planificateur QoS et le protocole de multiplexage, si présents.\n\nCela peut perturber les partages, les imprimantes réseau, certains VPN ou fonctions Windows. Ce mode ne garantit pas de meilleures performances.\n\n" + OnlyDetails :
            "Donner la priorité à IPv4 dans Windows en conservant IPv6 et toutes les liaisons réseau. Ce réglage est global, pas limité à la carte sélectionnée.";
        warning += only ? "\n\n" + OnlyTarget + "\n\nCoupure temporaire du réseau possible. Ne pas lancer pendant une session distante ou un transfert important." :
            "\n\nUn redémarrage de Windows sera nécessaire si la préférence est modifiée. Bastos ne redémarrera pas le PC automatiquement.";
        if (MessageBox.Show(warning, title, MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        SetBusy(true); IpStatus = restore ? "Restauration des réglages IP…" : "Sauvegarde et activation du mode IP…";
        string outcome;
        try
        {
            using var result = await RunAsync(action, adapterId, null, "Manage-BASTOS-IPModes.ps1");
            bool success = result.RootElement.GetProperty("Success").GetBoolean();
            outcome = (success ? "" : "Échec — ") + result.RootElement.GetProperty("Message").GetString();
            log.Write("Modes IP", title + " : " + outcome, !success);
        }
        catch (Exception ex) { outcome = "Échec — " + ex.Message; log.Write("Modes IP", outcome, true); }
        try { await ReadAdaptersAsync(); }
        catch (Exception ex) { Adapters.Clear(); SelectedAdapter = null; LoadIpState(new()); outcome += " — Actualisation impossible : " + ex.Message; }
        IpStatus = outcome; SetBusy(false);
    }

    private async Task<JsonDocument> RunAsync(string action, string? id, string? profile, string worker = "Manage-BASTOS-Network.ps1")
    {
        Directory.CreateDirectory(paths.LogRoot);
        string resultPath = Path.Combine(paths.LogRoot, $"Ethernet-{Guid.NewGuid():N}.json");
        try
        {
            var args = new List<string> { "-Action", action, "-ResultPath", resultPath };
            if (id != null) { args.Add("-AdapterId"); args.Add(id); }
            if (profile != null) { args.Add("-Profile"); args.Add(profile); }
            var command = await workers.RunAsync(worker, args, elevate: action != "Get", timeoutMinutes: 5);
            if (!File.Exists(resultPath)) throw new InvalidOperationException(string.IsNullOrWhiteSpace(command.Error) ? "Le worker réseau n’a pas retourné de résultat." : command.Error);
            return JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
        }
        finally { try { File.Delete(resultPath); } catch { } }
    }
}

public sealed class IpModeSnapshot
{
    public string PreferState { get; set; } = "État non disponible";
    public bool CanPreferApply { get; set; }
    public bool CanPreferRestore { get; set; }
    public bool RestartRequired { get; set; }
    public IpAdapterMode[] Adapters { get; set; } = Array.Empty<IpAdapterMode>();
}
public sealed class IpAdapterMode
{
    public string Id { get; set; } = "";
    public string State { get; set; } = "";
    public bool CanApply { get; set; }
    public bool CanRestore { get; set; }
    public IpBindingState[] Bindings { get; set; } = Array.Empty<IpBindingState>();
}
public sealed class IpBindingState
{
    public string ComponentID { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public bool Enabled { get; set; }
}
