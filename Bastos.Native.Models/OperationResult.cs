using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Bastos.Native.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum OperationState { Running, Succeeded, Partial, Failed, Cancelled, TimedOut, Unconfirmed }
public sealed record OperationCheck(string Name, bool Passed, string Detail);
public sealed record OperationVerification(bool Valid, string Message, IReadOnlyList<OperationCheck> Checks, bool Partial = false);
public sealed record OperationResumeIntent(string Kind, string SourceIso = "", string ExpectedJson = "", string OptionsFile = "", string OptionsSha256 = "");
public sealed record OperationResult
{
    public int SchemaVersion { get; init; } = 1;
    public string OperationId { get; init; } = "";
    public string Name { get; init; } = "";
    public string ExecutionKind { get; init; } = "PowerShell";
    public OperationState State { get; init; }
    public string Phase { get; init; } = "Préparation";
    public string Message { get; init; } = "";
    public string ErrorCode { get; init; } = "";
    public string TechnicalDetail { get; init; } = "";
    public DateTime StartedUtc { get; init; }
    public DateTime? EndedUtc { get; init; }
    public int OwnerProcessId { get; init; }
    public DateTime? OwnerProcessStartedUtc { get; init; }
    public string BootStamp { get; init; } = "";
    public bool RestartRequired { get; init; }
    public string OperationKey { get; init; } = "";
    public int? WorkerExitCode { get; init; }
    public bool ProcessStopped { get; init; } = true;
    public bool ActionCompletionUnconfirmed { get; init; }
    // Null for older reports. True is saved before invoking the execution delegate:
    // execution may have started, but its effects are not inferred from this flag.
    public bool? ExecutionStarted { get; init; }
    public OperationResumeIntent? ResumeIntent { get; init; }
    public string WorkerReportPath { get; init; } = "";
    public string JournalPath { get; init; } = "";
    public IReadOnlyList<OperationCheck> Checks { get; init; } = Array.Empty<OperationCheck>();
    [JsonIgnore] public JsonElement? Payload { get; init; }
    [JsonIgnore] public bool Success => State is OperationState.Succeeded or OperationState.Partial;
    [JsonIgnore] public OperationGuidance Guidance => OperationGuidance.For(this);
    [JsonIgnore] public string UserMessage => State == OperationState.Succeeded ? Message :
        Guidance.Problem + "\nÉtat : " + Guidance.Effects + "\nÀ faire : " + Guidance.NextStep +
        (string.IsNullOrEmpty(OperationId) ? "" : $"\nRéférence : {OperationId}. Détails dans Journal.");
}

public sealed record OperationGuidance(string Problem, string Effects, string NextStep)
{
    // User guidance is derived from stable codes and recorded evidence. Never infer
    // rollback, successful writes or process termination from a phase name.
    public static OperationGuidance For(OperationResult result)
    {
        var (problem, next) = result.ErrorCode switch
        {
            "ENGINE_FILE_MISSING" or "ENGINE_FILE_CHANGED" or "ENGINE_FILE_UNREADABLE" or "ENGINE_FILE_UNLISTED" or "ENGINE_LINK_REFUSED" or "ENGINE_CATALOG_INVALID" =>
                ("Le contrôle des fichiers a bloqué le lancement.", "Réinstalle la même version de Bastos avant de réessayer. Le fichier concerné figure dans les détails du Journal."),
            "INSTALLATION_REVIEW_REQUIRED" => ("Des réglages restent à vérifier après la réinstallation.", "Ouvre Journal → Bilan après réinstallation. Attends la fin de la finalisation, puis recontrôle les réglages signalés."),
            "OPERATION_BUSY" => ("Cette action est déjà en cours ou sa fin reste incertaine.", "Vérifie la fin de la tentative précédente dans Journal avant de relancer."),
            "ADMIN_CANCELLED" => ("La demande administrateur a été annulée.", "Pour continuer, relance l’action et accepte la demande Windows."),
            "OPERATION_CANCELLED" => ("La création de l’ISO a été annulée.", "Pour reprendre, vérifie l’espace libre puis relance la création."),
            "RECOVERY_CANCELLED" => ("La préparation Recovery a été annulée avant les écritures sur la partition.", "Rouvre le bilan si tu souhaites préparer Recovery. Aucun redémarrage n’a été demandé pour cette tentative."),
            "CANCELLATION_CLEANUP_UNCONFIRMED" => ("L’annulation a été demandée, mais son nettoyage n’est pas entièrement confirmé.", "Dans Journal, vérifie les montages d’images et les fichiers de travail de cette tentative avant toute relance. Ne les supprime pas pendant qu’un outil travaille."),
            "JOURNAL_UNWRITABLE" => ("Bastos ne peut pas enregistrer le résultat dans son journal.", "Dans Journal → Dossier des rapports, vérifie l’espace libre et les droits du dossier. Vérifie l’état de l’outil avant de relancer."),
            "DISK_PLAN_MISSING" or "DISK_PLAN_CHANGED" => ("Le plan des partitions est absent ou a changé.", "Ouvre Réinstallation facile Windows → Compte, nom du PC, nettoyage et partitions. Vérifie les partitions, enregistre les options puis rouvre le bilan."),
            "RECOVERY_PROFILE_FAILED" => ("Le profil d’installation Windows n’a pas pu être créé.", "Resélectionne l’ISO et l’édition. Enregistre le compte et le clavier, puis rouvre le bilan."),
            "RECOVERY_PREPARATION_FAILED" => ("La préparation Recovery a échoué.", "Vérifie les contrôles dans Journal, puis le média et les partitions dans le bilan avant de réessayer."),
            "RECOVERY_BOOT_FAILED" or "RECOVERY_DISARM_UNCONFIRMED" or "RECOVERY_RESTART_FAILED" => ("Le démarrage vers Recovery n’est pas entièrement confirmé.", "Ne redémarre pas manuellement vers Recovery. Vérifie sa neutralisation dans Journal avant de poursuivre."),
            "ADK_RESTART_REQUIRED" => ("Les outils ADK demandent un redémarrage de Windows.", "Enregistre ton travail et redémarre Windows. Revérifie l’ADK dans Bastos avant de recréer l’ISO."),
            "ADK_PATCH_UNCONFIRMED" => ("Le correctif ADK n’est pas confirmé par Windows Installer.", "Consulte les détails MSI, puis répare le correctif ADK depuis Microsoft avant de recréer l’ISO."),
            "ADK_VERSION_UNSUPPORTED" => ("La version ADK détectée n’est pas validée par Bastos.", "Installe la version ADK indiquée dans le module ISO depuis Microsoft, puis revérifie."),
            "WEBVIEW2_LINK_REFUSED" or "WEBVIEW2_SIGNATURE_INVALID" => ("L’installateur WebView2 a été refusé par les contrôles.", "Ne lance pas ce fichier manuellement. Répare Bastos, puis retélécharge WebView2 depuis le module."),
            "WEBVIEW2_DOWNLOAD_FAILED" => ("Le téléchargement de WebView2 n’est pas validé.", "Vérifie Internet et l’espace libre, puis retélécharge WebView2."),
            "WEBVIEW2_INSTALL_FAILED" => ("L’installation de WebView2 a signalé une erreur.", "Redétecte WebView2. S’il reste absent, consulte les détails de l’installateur avant de réessayer."),
            "WEBVIEW2_NOT_DETECTED" or "WEBVIEW2_DETECTION_FAILED" => ("La présence de WebView2 n’est pas confirmée.", "Dans Réinstallation facile Windows, revérifie WebView2. Installe-le depuis ce module s’il reste absent."),
            "REPORT_MISSING" or "REPORT_INVALID" or "REPORT_UNREADABLE" or "REPORT_TOO_LARGE" => ("Le rapport de l’outil ne permet pas de confirmer le résultat.", "Vérifie l’outil et les fichiers attendus avant de relancer. Le rapport concerné figure dans les détails du Journal."),
            "VERIFICATION_FAILED" => (string.IsNullOrWhiteSpace(result.Message) ? "Les contrôles n’ont pas confirmé le résultat annoncé." : result.Message,
                "Consulte les contrôles en échec dans Journal. Recontrôle le résultat dans le module avant de relancer."),
            "VERIFICATION_ERROR" => ("La vérification du résultat a été interrompue.", "Consulte le contrôle interrompu dans Journal. Recontrôle le résultat dans le module avant de relancer."),
            "TIMEOUT_STOPPED" => ("Le délai maximal est dépassé ; le processus suivi est arrêté.", "Vérifie les fichiers et les contrôles dans Journal avant de réessayer. L’arrêt ne rétablit pas l’état précédent."),
            "TIMEOUT_UNCONFIRMED" or "ACTION_COMPLETION_UNCONFIRMED" => ("La fin de l’outil n’est pas confirmée.", "Vérifie l’outil dans Windows, puis actualise Journal. Ne relance pas tant que sa fin reste incertaine."),
            _ => (string.IsNullOrWhiteSpace(result.Message) ? "Cette opération n’a pas de résultat confirmé." : result.Message,
                "Vérifie le résultat dans le module et les détails dans Journal avant de réessayer.")
        };
        string phase = string.IsNullOrWhiteSpace(result.Phase) ? "non renseignée" : result.Phase;
        string effects = result.ExecutionStarted == false ? "Aucune action lancée pour cette tentative."
            : result.ErrorCode == "ADMIN_CANCELLED" ? "L’outil nécessitant l’autorisation n’a pas été lancé pour cette tentative."
            : result.ErrorCode == "OPERATION_CANCELLED" ? "Aucun fichier ISO de sortie validé. Des fichiers temporaires peuvent subsister."
            : result.ErrorCode == "RECOVERY_CANCELLED" ? "Aucune écriture sur la partition Recovery pour cette tentative. Des fichiers de profil locaux peuvent subsister."
            : "Phase : « " + phase + " ». Effets non confirmés ; aucun retour arrière attesté.";
        if (result.State == OperationState.Succeeded || result.State == OperationState.Partial)
            effects = result.Message;
        if (result.State == OperationState.Partial)
            problem = "L’opération n’est que partiellement terminée.";
        if (result.State == OperationState.Running || !result.ProcessStopped || result.ActionCompletionUnconfirmed)
        {
            effects = "Phase : « " + phase + " ». L’outil peut encore travailler ; fin et effets à vérifier.";
            next = "Vérifie l’outil dans Windows, puis actualise Journal. Ne lance pas une seconde tentative avant la confirmation de sa fin.";
        }
        else if (result.RestartRequired && result.ErrorCode != "ADK_RESTART_REQUIRED" &&
            result.ErrorCode is not ("RECOVERY_BOOT_FAILED" or "RECOVERY_DISARM_UNCONFIRMED" or "RECOVERY_RESTART_FAILED" or
                "WEBVIEW2_LINK_REFUSED" or "WEBVIEW2_SIGNATURE_INVALID" or "CANCELLATION_CLEANUP_UNCONFIRMED"))
            next = "Enregistre ton travail et redémarre Windows. Revérifie le résultat dans le module avant de poursuivre.";
        return new(problem, effects, next);
    }
}
