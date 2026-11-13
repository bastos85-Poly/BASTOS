using System;
using System.Collections.Generic;
using System.Linq;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public static class RecoveryPreflightBuilder
{
    public static RecoveryPreflight Build(string isoPath, long isoBytes, RufusInstallOptions options,
        RecoveryDiskPreview disk, WindowsIsoEditionCatalog? catalog, string isoError, bool reinstall)
    {
        var blockers = new List<string>();
        if (options.WindowsEditionId is not ("Core" or "Education" or "Professional"))
            blockers.Add("Choisis Home, Education ou Pro dans Compte, clavier et partitions.");
        if(options.UseCleanBastosInstallation && !(options.WindowsEditionId.StartsWith("Professional", StringComparison.OrdinalIgnoreCase) || options.WindowsEditionId.StartsWith("Education", StringComparison.OrdinalIgnoreCase))) blockers.Add("Le profil propre avec trois épingles exige Windows Pro ou Éducation ; pour Home, décoche Installation propre personnalisée BASTOS.");
        if (!disk.Success) blockers.Add("Plan des disques non confirmé : " + disk.Message);
        if (string.IsNullOrWhiteSpace(options.DiskSafetySnapshot) || string.IsNullOrWhiteSpace(options.RecoveryPartitionGuid) ||
            string.IsNullOrWhiteSpace(options.WindowsDiskIdentity))
            blockers.Add("Vérifie et enregistre le plan dans Compte, nom du PC, nettoyage et partitions.");
        if (disk.Success && (disk.DiskSnapshot != options.DiskSafetySnapshot ||
            !SameGuid(disk.PartitionGuid, options.RecoveryPartitionGuid) || !SameGuid(disk.DiskIdentity, options.WindowsDiskIdentity)))
            blockers.Add("Le disque ou ses partitions ont changé depuis l’enregistrement. Revalide les options.");
        if (disk.Success && (disk.Partitions.Count == 0 || disk.Partitions.Any(p => p.SizeBytes <= 0 ||
            p.Number < 1 || !Guid.TryParse(p.Guid, out var partId) || partId == Guid.Empty ||
            p.Decision != "CONSERVER" && p.Decision != "EFFACER") ||
            disk.Partitions.Select(p => p.Number).Distinct().Count() != disk.Partitions.Count ||
            disk.Partitions.Select(p => p.Guid.Trim('{', '}').ToUpperInvariant()).Distinct().Count() != disk.Partitions.Count ||
            !disk.Partitions.Any(p => SameGuid(p.Guid, disk.PartitionGuid) && p.Decision == "CONSERVER")))
            blockers.Add("Le détail des partitions est incomplet. Aucun lancement autorisé.");
        if (isoBytes <= 0 || catalog == null) blockers.Add("ISO non vérifiée : " + (isoError.Length > 0 ? isoError : "fichier absent ou illisible."));
        else
        {
            var matches = catalog.Images.Where(e => e.ImageIndex == options.WindowsImageIndex).ToArray();
            var edition = matches.Length == 1 ? matches[0] : null;
            if (!string.Equals(catalog.IsoPath, isoPath, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(options.EditionIsoPath, isoPath, StringComparison.OrdinalIgnoreCase) ||
                options.EditionIsoSha256.Length != 64 || !string.Equals(catalog.IsoSha256, options.EditionIsoSha256, StringComparison.OrdinalIgnoreCase))
                blockers.Add("L’ISO ne correspond plus au fichier validé. Choisis à nouveau son édition dans les options.");
            if (edition == null || !string.Equals(edition.EditionId, options.WindowsEditionId, StringComparison.OrdinalIgnoreCase) ||
                edition.ImageName != options.WindowsImageName || string.IsNullOrWhiteSpace(options.WindowsUILanguage) ||
                !edition.Languages.Contains(options.WindowsUILanguage, StringComparer.OrdinalIgnoreCase))
                blockers.Add("L’édition ou la langue Windows enregistrée n’est pas disponible dans cette ISO. Revalide les options.");
        }
        if (disk.Success && disk.RecoveryFreeBytes < 0) blockers.Add("L’espace libre sur Recovery n’a pas pu être relu.");
        else if (disk.Success && (disk.RecoverySizeBytes <= 0 || disk.RecoveryFreeBytes > disk.RecoverySizeBytes))
            blockers.Add("Les mesures d’espace sur Recovery sont incohérentes. Relance le bilan.");
        else if (disk.Success && isoBytes > 0)
        {
            bool cache = disk.CacheMode is "Reuse" or "Boot" && catalog != null &&
                disk.CacheCleanupProfile == (options.UseCleanBastosInstallation ? "minimal-2" : "") &&
                disk.CacheIsoSha256.Length == 64 && string.Equals(disk.CacheIsoSha256, catalog.IsoSha256, StringComparison.OrdinalIgnoreCase) &&
                disk.CacheRequiredFreeBytes >= 2147483648L;
            if (!cache) disk = disk with { CacheMode = "Full", CacheRequiredFreeBytes = 0, CacheIsoSha256 = "" };
            long required = cache ? disk.CacheRequiredFreeBytes : isoBytes + 2147483648L;
            if (disk.RecoveryFreeBytes < required)
                blockers.Add("Espace insuffisant pour la préparation prévue et sa marge de sécurité. Libère de l’espace sur D: puis relance le bilan.");
        }
        if (string.IsNullOrWhiteSpace(options.UserName) || string.IsNullOrWhiteSpace(options.ComputerName) ||
            string.IsNullOrWhiteSpace(options.KeyboardLayout) || string.IsNullOrWhiteSpace(options.WindowsLocale))
            blockers.Add("Le compte, le nom du PC ou le clavier est incomplet. Revalide les options.");
        var cleanup = new List<string>();
        if(options.UseCleanBastosInstallation) cleanup.Add("Installation propre BASTOS : applications ciblées retirées, Copilot, OneDrive, Outlook et Teams traités, démarrage rapide désactivé, confidentialité renforcée ; composants essentiels conservés");
        cleanup.Add(options.PreserveDrivers ? "Pilotes tiers : sauvegarde sur D: et transmission à Windows Setup ; espace supplémentaire contrôlé pendant l’export" : "Pilotes actuels non sauvegardés pour cette réinstallation");
        if (options.BypassHardwareChecks) cleanup.Add("contournement des exigences matérielles activé");
        return new(isoPath, $"{options.WindowsImageName} — index {options.WindowsImageIndex}\nLangue Windows : {options.WindowsUILanguage}",
            $"Compte : {options.UserName} (sans mot de passe)\nPC : {options.ComputerName}\nClavier : {options.KeyboardLayout} — formats régionaux : {options.WindowsLocale}",
            cleanup.Count == 0 ? "Aucun nettoyage facultatif sélectionné." : string.Join(" · ", cleanup), disk, isoBytes, blockers, reinstall);
    }

    private static bool SameGuid(string first, string second) => Guid.TryParse(first, out var a) && a != Guid.Empty && Guid.TryParse(second, out var b) && a == b;
}
