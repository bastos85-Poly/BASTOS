using System;
using System.Collections.Generic;

namespace Bastos.Native.Models;

public sealed record RecoveryPartitionPreview(int Number, string Guid, string Location, long SizeBytes, string Decision)
{
    public string SizeDisplay => $"{SizeBytes / 1073741824d:N2} Go";
}

public sealed record RecoveryDiskPreview(bool Success, string Message, string Target, string PartitionGuid,
    string DiskIdentity, string DiskSnapshot)
{
    public IReadOnlyList<RecoveryPartitionPreview> Partitions { get; init; } = Array.Empty<RecoveryPartitionPreview>();
    public long RecoverySizeBytes { get; init; }
    public long RecoveryFreeBytes { get; init; } = -1;
    public string DiskDescription { get; init; } = "Disque non confirmé";
    public bool CreateEfi { get; init; }
    public string CacheMode { get; init; } = "Full";
    public long CacheRequiredFreeBytes { get; init; }
    public string CacheIsoSha256 { get; init; } = "";
    public string CacheCleanupProfile { get; init; } = "";
}

public sealed record RecoveryPreflight(string IsoPath, string Edition, string Profile, string Cleanup,
    RecoveryDiskPreview Disk, long IsoBytes, IReadOnlyList<string> Blockers, bool Reinstall)
{
    public bool CanContinue => Blockers.Count == 0;
    public string Title => Reinstall ? "Bilan avant réinstallation" : "Bilan avant préparation Recovery";
    public string Result => CanContinue ? "Contrôles préalables réussis" : "Lancement bloqué";
    public string ActionLabel => Reinstall ? "Lancer la réinstallation" : "Préparer Recovery";
    public bool HasVerifiedCachePlan => Disk.CacheMode is "Reuse" or "Boot" &&
        Disk.CacheIsoSha256.Length == 64 && Disk.CacheRequiredFreeBytes >= 2147483648L;
    public long RequiredFreeBytes => HasVerifiedCachePlan ? Disk.CacheRequiredFreeBytes : IsoBytes + 2147483648L;
    public string CacheDescription => HasVerifiedCachePlan
        ? Disk.CacheMode == "Reuse" ? "Média vérifié : images Windows et démarrage réutilisables." : "Image Windows vérifiée : seul le démarrage sera reconstruit."
        : "Une copie complète du média doit être prévue.";
    public string Space => $"ISO : {IsoBytes / 1073741824d:N2} Go\nRecovery : {Disk.RecoverySizeBytes / 1073741824d:N2} Go au total — " +
        (Disk.RecoveryFreeBytes < 0 ? "espace libre inconnu" : $"{Disk.RecoveryFreeBytes / 1073741824d:N2} Go libres") +
        $"\n{CacheDescription}\nEspace libre demandé : {RequiredFreeBytes / 1073741824d:N2} Go (dont 2 Go de marge).";
    public string Consequences => Reinstall
        ? "Maintenant : préparation et remplacement des fichiers du média sur D:, puis vérification. Après validation, redémarrage dans 15 secondes. Dans Recovery : suppression des partitions marquées EFFACER, puis installation de Windows. Leurs fichiers seront perdus. Sauvegarde-les avant de continuer."
        : "Maintenant : préparation et remplacement des fichiers du média Recovery sur D:. Les partitions marquées EFFACER ne seront supprimées que lors d’une réinstallation ultérieure. Cette préparation ne demande aucun redémarrage.";
    public string PartitionCreation => Disk.CreateEfi ? "Lors de la réinstallation : EFI, MSR et Windows seront recréées." : "Lors de la réinstallation : EFI conservée ; MSR et Windows seront recréées.";
}
