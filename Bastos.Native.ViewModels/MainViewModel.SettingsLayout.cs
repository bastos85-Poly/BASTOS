using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using Bastos.Native.Models;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.ViewModels;

public sealed record SettingsGroup(string Key, string Title, string Description,
    IReadOnlyList<StatusCard> Cards, IReadOnlyList<TroubleshootingToggle> Toggles,
    IReadOnlyList<TroubleshootingChoice> Choices, bool HasMouse = false)
{
    public bool IsExpanded { get; set; }
}

public sealed partial class MainViewModel
{
    public ObservableCollection<SettingsGroup> PersonalizationGroups { get; } = new();
    public ObservableCollection<SettingsGroup> AdvancedSettingsGroups { get; } = new();
    private readonly List<StatusCard> advancedPerformanceCards = new();

    private void AddInterruptAffinityCard(ICollection<StatusCard> destination, string profile, string title, string description)
    {
        StatusCard card = null!;
        card = new StatusCard(title,
            description + " Modifie l’affinité PCI des périphériques détectés et la base RSS du réseau. La connexion peut couper brièvement ; redémarrage requis.",
            "État à vérifier", StatusTone.Neutral,
            "Activer", new AsyncRelayCommand(() => SetInterruptAffinityAsync(card, profile, true)),
            "Désactiver", new AsyncRelayCommand(() => SetInterruptAffinityAsync(card, profile, false)),
            isChoiceCard: true);
        interruptAffinityCards[profile] = card;
        destination.Add(card);
    }

    private async System.Threading.Tasks.Task SetInterruptAffinityAsync(StatusCard card, string profile, bool enabled)
    {
        card.State = enabled ? "Application du profil…" : "Retour aux réglages Windows…";
        var (success, message) = await interruptAffinity.SetAsync(profile, enabled);
        card.State = message;
        card.Tone = success ? StatusTone.Success : StatusTone.Danger;
        if (success) await RefreshInterruptAffinityCardsAsync();
    }

    private async System.Threading.Tasks.Task RefreshInterruptAffinityCardsAsync()
    {
        foreach (var (profile, card) in interruptAffinityCards)
        {
            var (success, applied, message) = await interruptAffinity.ReadAsync(profile);
            card.State = message;
            card.Tone = success ? applied ? StatusTone.Success : StatusTone.Neutral : StatusTone.Warning;
            if (success) card.SelectChoice(applied);
            else card.ClearChoice();
        }
    }

    private void RebuildSettingsGroups()
    {
        var expansion = PersonalizationGroups.Concat(AdvancedSettingsGroups).ToDictionary(g => g.Key + (PersonalizationGroups.Contains(g) ? "personal" : "advanced"), g => g.IsExpanded);
        StatusCard[] Privacy(params string[] ids) => ids.Select(id => securityCardsById[id]).ToArray();
        TroubleshootingToggle[] Basic(params string[] keys) => TroubleshootingToggles.Where(t => keys.Contains(t.Key)).ToArray();
        TroubleshootingToggle[] Risk(params string[] keys) => RiskyOptimizationToggles.Where(t => keys.Contains(t.Key)).ToArray();
        TroubleshootingToggle[] Advanced(params string[] keys) => TweakingToggles.Where(t => keys.Contains(t.Key)).ToArray();
        TroubleshootingChoice[] Values(params string[] keys) => TweakingChoices.Where(t => keys.Contains(t.Key)).ToArray();
        StatusCard[] Performance(params string[] titles) => advancedPerformanceCards.Where(c => titles.Contains(c.Title)).ToArray();
        PersonalizationGroups.Clear(); AdvancedSettingsGroups.Clear();
        PersonalizationGroups.Add(new("appearance", "Menu Démarrer et interface", "Présentation de Windows, assistants et applications affichées.",
            Privacy("news", "meet-now", "cortana", "copilot", "content-delivery"), Array.Empty<TroubleshootingToggle>(), Array.Empty<TroubleshootingChoice>()));
        PersonalizationGroups.Add(new("input", "Clavier et souris", "Répétition des touches, raccourcis d’accessibilité et comportement du pointeur.",
            KeyboardOptimizationCards.ToArray(), Array.Empty<TroubleshootingToggle>(), Array.Empty<TroubleshootingChoice>(), true));
        PersonalizationGroups.Add(new("privacy", "Confidentialité et données", "Collecte diagnostique, publicité, historique et localisation.",
            Privacy("telemetry", "error-reporting", "advertising", "activity-history", "location", "find-device"), Array.Empty<TroubleshootingToggle>(), Array.Empty<TroubleshootingChoice>()));
        PersonalizationGroups.Add(new("security", "Sécurité et avertissements", "Contrôle de compte utilisateur et avertissements lors des téléchargements.",
            Array.Empty<StatusCard>(), Basic("Lua").Concat(Risk("RiskUnsafeDownloads")).ToArray(), Array.Empty<TroubleshootingChoice>()));
        PersonalizationGroups.Add(new("updates", "Mises à jour et pilotes", "Choix des pilotes proposés par Windows Update et du partage des téléchargements.",
            Privacy("delivery-optimization"), Basic("WindowsUpdateDrivers"), Array.Empty<TroubleshootingChoice>()));
        AdvancedSettingsGroups.Add(new("cpu", "Processeur et planification", "MMCSS, énergie, interruptions et priorité des composants Windows.",
            Performance("Optimiser MMCSS pour le jeu"), Advanced("NoLazyMode", "DisablePowerThrottling", "ThreadDpc", "DisableInterruptSteering", "CpuIdle"), Values("LazyModeTimeout", "SystemResponsiveness", "CsrssPriority")));
        AdvancedSettingsGroups.Add(new("memory", "Mémoire et entrées-sorties", "Pagination, combinaison de pages et paramètres d’E/S.",
            Array.Empty<StatusCard>(), Advanced("DisablePageCombining", "DisablePagingExecutive"), Values("IoLatencyCap", "IoPageLockLimit")));
        AdvancedSettingsGroups.Add(new("graphics", "Affichage et présentation des images", "MPO, modes Flip et file de présentation graphique.",
            Array.Empty<StatusCard>(), Advanced("DisableMpo", "ForceDirectFlip", "ForceIndependentFlip", "ForceFlipTrueImmediate").Append(NvidiaPStateToggle).ToArray(), Values("QueuedPresentLimit")));
        AdvancedSettingsGroups.Add(new("network", "Réseau et transferts", "TCP, tampons des cartes réseau et limite des transferts WebDAV.",
            Performance("Lever la limite de taille WebDAV"), Advanced("DisableNagle"), Values("ReceiveBuffers", "TransmitBuffers")));
        AdvancedSettingsGroups.Add(new("timers", "Horloges et minuteries", "Paramètres de diagnostic du démarrage et de synchronisation temporelle.",
            Array.Empty<StatusCard>(), Array.Empty<TroubleshootingToggle>(), Values("TscSyncPolicy", "UsePlatformTick", "DisableDynamicTick", "UsePlatformClock")));
        AdvancedSettingsGroups.Add(new("maintenance", "Services, diagnostics et entretien", "Fonctionnement des services, traces diagnostiques et nettoyage temporaire.",
            Performance("Regrouper les hôtes de services", "Nettoyage temporaire").Concat(Privacy("autologger")).ToArray(), Risk("RiskDisableBackgroundMaintenance"), Array.Empty<TroubleshootingChoice>()));
        foreach (var group in PersonalizationGroups) group.IsExpanded = expansion.GetValueOrDefault(group.Key + "personal");
        foreach (var group in AdvancedSettingsGroups) group.IsExpanded = expansion.GetValueOrDefault(group.Key + "advanced");
    }
}
