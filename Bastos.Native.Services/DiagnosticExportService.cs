using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record DiagnosticDocument(string Name, string Content)
{
    public int Bytes => Encoding.UTF8.GetByteCount(Content);
    public string Sha256 => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Content)));
    public string Description => $"{Name} • {Bytes:N0} octets";
}
public sealed class DiagnosticPackage
{
    internal DiagnosticPackage(DateTime createdUtc, IEnumerable<DiagnosticDocument> documents, int operations, int skipped, bool details)
    { CreatedUtc = createdUtc; Documents = Array.AsReadOnly(documents.ToArray()); Operations = operations; Skipped = skipped; Details = details; }
    public DateTime CreatedUtc { get; }
    public IReadOnlyList<DiagnosticDocument> Documents { get; }
    public int Operations { get; }
    public int Skipped { get; }
    public bool Details { get; }
    public string Preview => string.Join("\n\n", Documents.Select(d => $"===== {d.Name} =====\n{d.Content}"));
    public string Summary => $"{Operations} opération(s) • {Documents.Count} fichiers • {Documents.Sum(d => d.Bytes):N0} octets avant compression" +
        (Skipped > 0 ? $" • {Skipped} rapport(s) illisible(s) ignoré(s)" : "");
}

public sealed class DiagnosticExportService
{
    private readonly OperationHistoryService history;
    private readonly DiagnosticRedactor redactor;
    private readonly string version, windows;
    private static readonly JsonSerializerOptions jsonOptions = new() { WriteIndented = true, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };
    // Only recognized application codes enter the summary. Unknown strings and all
    // arbitrary report paths/fields are excluded rather than guessed to be harmless.
    private static readonly HashSet<string> knownCodes = new(StringComparer.Ordinal)
    {
        "ENGINE_FILE_MISSING", "ENGINE_FILE_CHANGED", "ENGINE_FILE_UNREADABLE", "ENGINE_FILE_UNLISTED", "ENGINE_LINK_REFUSED", "ENGINE_CATALOG_INVALID",
        "INSTALLATION_REVIEW_REQUIRED", "OPERATION_BUSY", "ADMIN_CANCELLED", "OPERATION_CANCELLED", "RECOVERY_CANCELLED",
        "CANCELLATION_CLEANUP_UNCONFIRMED", "JOURNAL_UNWRITABLE", "DISK_PLAN_MISSING", "DISK_PLAN_CHANGED", "RECOVERY_PROFILE_FAILED",
        "RECOVERY_PREPARATION_FAILED", "RECOVERY_BOOT_FAILED", "RECOVERY_DISARM_UNCONFIRMED", "RECOVERY_RESTART_FAILED",
        "ADK_RESTART_REQUIRED", "ADK_PATCH_UNCONFIRMED", "ADK_VERSION_UNSUPPORTED", "WEBVIEW2_LINK_REFUSED", "WEBVIEW2_SIGNATURE_INVALID",
        "WEBVIEW2_DOWNLOAD_FAILED", "WEBVIEW2_INSTALL_FAILED", "WEBVIEW2_NOT_DETECTED", "WEBVIEW2_DETECTION_FAILED",
        "REPORT_MISSING", "REPORT_INVALID", "REPORT_UNREADABLE", "REPORT_TOO_LARGE", "VERIFICATION_FAILED", "VERIFICATION_ERROR",
        "TIMEOUT_STOPPED", "TIMEOUT_UNCONFIRMED", "ACTION_COMPLETION_UNCONFIRMED", "WORKER_FAILED", "PROCESS_FAILED"
    };
    public DiagnosticExportService(string logRoot, string version, string windows, DiagnosticRedactor? redactor = null)
    {
        history = new(logRoot); this.redactor = redactor ?? new();
        this.version = NumericVersion(version); this.windows = NumericVersion(windows);
    }
    private static string NumericVersion(string value) => Regex.IsMatch(value ?? "", @"^\d{1,5}(?:\.\d{1,5}){1,3}$") ? value! : "Inconnue";
    private static string Category(OperationResult result) => result.ResumeIntent?.Kind switch
    {
        "RufusDownload" => "Téléchargement Rufus", "RecoveryPreparation" => "Préparation Recovery", "IsoBuild" => "Création ISO",
        "WebView2" => "WebView2", "Adk" => "Outils ADK", _ => result.OperationKey == "InstalledWindowsVerification" ? "Bilan Windows installé" : "Action Bastos"
    };
    private string CheckDetail(OperationCheck check) => Regex.IsMatch(check.Name ?? "", @"(?i)compte|account|user|utilisateur|nom.*pc|computer|machine|guid|sid|adress|address|chemin|path|serial|s[eé]rie|identit[eé]|ssid|password|mot de passe") ?
        "[Valeurs personnelles du contrôle retirées]" : redactor.Clean(check.Detail);
    public DiagnosticPackage Prepare(string? selectedId, bool recent, bool details)
    {
        if (!recent && !Guid.TryParseExact(selectedId, "N", out _)) throw new InvalidDataException("Sélectionne une opération dans Journal ou choisis les 20 dernières opérations.");
        for (string? cursor = history.DirectoryPath; cursor != null; cursor = Path.GetDirectoryName(cursor))
            if (Directory.Exists(cursor) && (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Le dossier des rapports est redirigé. Choisis les rapports locaux de Bastos.");
        var snapshot = history.Read(recent ? 20 : 200);
        var entries = recent ? snapshot.Entries.Take(20).ToArray() : snapshot.Entries.Where(e => e.Reference == selectedId).ToArray();
        if (entries.Length == 0) throw new InvalidDataException("Aucune opération disponible pour cet export. Actualise Journal puis réessaie.");
        var operations = entries.Select((entry, index) =>
        {
            var result = entry.Result;
            var checks = (result.Checks ?? Array.Empty<OperationCheck>()).Where(c => c != null).ToArray();
            return new
            {
                Reference = $"Operation-{index + 1:000}", Categorie = Category(result), DebutUtc = result.StartedUtc, FinUtc = result.EndedUtc,
                Etat = result.State.ToString(), Code = string.IsNullOrEmpty(result.ErrorCode) ? "AUCUN" : knownCodes.Contains(result.ErrorCode) ? result.ErrorCode : "CODE_NON_REPERTORIE",
                CodeSortie = result.WorkerExitCode, ProcessusArrete = result.ProcessStopped, FinActionNonConfirmee = result.ActionCompletionUnconfirmed,
                RedemarrageDemande = result.RestartRequired, ExecutionEngagee = result.ExecutionStarted,
                Controles = checks.Length, ControlesConformes = checks.Count(c => c.Passed),
                Details = details ? new
                {
                    Nom = redactor.Clean(result.Name), Phase = redactor.Clean(result.Phase), Message = redactor.Clean(result.Message), Technique = redactor.Clean(result.TechnicalDetail),
                    Controles = checks.Take(20).Select(c => new { Nom = redactor.Clean(c.Name), Conforme = c.Passed, Detail = CheckDetail(c) }).ToArray(),
                    ControlesDetaillesOmis = Math.Max(0, checks.Length - 20)
                } : null
            };
        }).ToArray();
        DateTime created = DateTime.UtcNow;
        string readme = "Diagnostic Bastos\n\n" +
            (details ? "Mode : détails avec masquage automatique. Relis les textes avant de partager : un texte libre peut contenir une information personnelle non reconnue.\n" :
                "Mode : résumé technique. Les textes libres, noms de comptes, noms de PC, chemins, identifiants de machine et adresses réseau ne sont pas inclus.\n") +
            "Les références Operation-001, etc. sont propres à cette archive.\n" +
            "Les dates, états, codes d’erreur reconnus et nombres de contrôles sont conservés.\n" +
            "Aucun fichier brut n’est joint : journaux, rapports workers, profils d’installation, fichiers de mots de passe, fichiers personnels, scripts et ISO sont exclus. Les identifiants GPT et les informations d’activation ne sont pas collectés.\n" +
            "L’archive est locale. Aucun envoi automatique.\n";
        var documents = new List<DiagnosticDocument>
        {
            new("LIRE-MOI.txt", readme),
            new("Diagnostic.json", JsonSerializer.Serialize(new { Schema = 1, Bastos = version, Windows = windows, CreeUtc = created, DetailsMasques = details, RapportsIllisiblesIgnores = snapshot.Skipped, Operations = operations }, jsonOptions))
        };
        documents.Add(new("Manifeste.json", JsonSerializer.Serialize(new { Schema = 1, Fichiers = documents.Select(d => new { Nom = d.Name, Octets = d.Bytes, SHA256 = d.Sha256 }).ToArray() }, jsonOptions)));
        if (documents.Sum(d => d.Bytes) > 2 * 1024 * 1024) throw new InvalidDataException("Cet aperçu est trop volumineux. Choisis une seule opération ou retire les détails.");
        return new(created, documents, entries.Length, snapshot.Skipped, details);
    }
    public void Export(DiagnosticPackage package, string destination)
    {
        string target = Path.GetFullPath(destination);
        if (!Regex.IsMatch(target, @"^[A-Za-z]:\\") || !target.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            throw new IOException("Choisis un fichier ZIP sur un disque local.");
        if (File.Exists(target) || Directory.Exists(target)) throw new IOException("Ce nom existe déjà. Choisis un autre nom pour conserver le fichier existant.");
        string parent = Path.GetDirectoryName(target)!;
        if (!Directory.Exists(parent)) throw new DirectoryNotFoundException("Le dossier de destination n’existe plus. Choisis un autre dossier.");
        for (string? cursor = parent; cursor != null; cursor = Path.GetDirectoryName(cursor))
            if ((File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0) throw new IOException("Choisis un dossier local sans redirection.");
        string temp = Path.Combine(parent, ".bastos-diagnostic-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
            using (var zip = new ZipArchive(stream, ZipArchiveMode.Create))
                foreach (var document in package.Documents)
                {
                    var entry = zip.CreateEntry(document.Name, CompressionLevel.Optimal);
                    entry.LastWriteTime = new DateTimeOffset(package.CreatedUtc);
                    using var output = entry.Open(); byte[] bytes = Encoding.UTF8.GetBytes(document.Content); output.Write(bytes);
                }
            // Verify the exact frozen preview, then publish without overwriting.
            using (var zip = ZipFile.OpenRead(temp))
            {
                if (zip.Entries.Count != package.Documents.Count) throw new InvalidDataException("L’archive produite est incomplète.");
                foreach (var document in package.Documents)
                {
                    using var input = zip.GetEntry(document.Name)!.Open();
                    if (Convert.ToHexString(SHA256.HashData(input)) != document.Sha256) throw new InvalidDataException("L’archive ne correspond pas à l’aperçu. Recrée l’export.");
                }
            }
            File.Move(temp, target, false);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
