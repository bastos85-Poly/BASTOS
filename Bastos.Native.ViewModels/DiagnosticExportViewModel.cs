using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class DiagnosticExportViewModel : ObservableObject
{
    private readonly DiagnosticExportService service;
    private readonly string? selectedId;
    private bool details, busy;
    private string scope, preview = "", summary = "", status = "";
    private DiagnosticPackage? package;
    private int revision;
    public const string SelectedScope = "Opération sélectionnée";
    public const string RecentScope = "20 dernières opérations";
    public string[] Scopes { get; }
    public ObservableCollection<string> Files { get; } = new();
    public bool IsBusy { get => busy; private set { SetProperty(ref busy, value); RaisePropertyChanged(nameof(CanExport)); RaisePropertyChanged(nameof(ExportDisabledReason)); RaisePropertyChanged(nameof(CanEdit)); RefreshCommand.RaiseCanExecuteChanged(); } }
    public string ExportDisabledReason => IsBusy ? "La préparation ou l’export est en cours. Attends sa fin." : package == null ? "Génère l’aperçu avant d’enregistrer le ZIP." : "";
    public bool CanExport => !IsBusy && package != null;
    public bool CanEdit => !IsBusy;
    public string Scope { get => scope; set { if (SetProperty(ref scope, value)) Invalidate(); } }
    public bool IncludeDetails { get => details; set { if (SetProperty(ref details, value)) { RaisePropertyChanged(nameof(PrivacyNotice)); Invalidate(); } } }
    public string PrivacyNotice => IncludeDetails ?
        "Détails avec masquage automatique. Relis les textes : une information personnelle dans un texte libre peut ne pas être reconnue. Tu peux revenir au résumé technique." :
        "Résumé technique : aucun texte libre, nom de compte, nom de PC, chemin, identifiant de machine ou adresse réseau n’est inclus.";
    public string Preview { get => preview; private set => SetProperty(ref preview, value); }
    public string Summary { get => summary; private set => SetProperty(ref summary, value); }
    public string Status { get => status; private set => SetProperty(ref status, value); }
    public AsyncRelayCommand RefreshCommand { get; }
    public DiagnosticExportViewModel(DiagnosticExportService service, string? selectedId)
    {
        this.service = service; this.selectedId = selectedId;
        Scopes = selectedId == null ? new[] { RecentScope } : new[] { SelectedScope, RecentScope };
        scope = Scopes[0];
        RefreshCommand = new(PrepareAsync, () => !IsBusy, () => "La préparation ou l’export est en cours. Attends sa fin.");
    }
    private void Invalidate()
    {
        revision++; package = null; Files.Clear(); Preview = ""; Summary = "";
        Status = "Les options ont changé. Génère l’aperçu pour vérifier le nouveau contenu.";
        RaisePropertyChanged(nameof(CanExport)); RaisePropertyChanged(nameof(ExportDisabledReason));
    }
    public async Task PrepareAsync()
    {
        if (IsBusy) return;
        int expectedRevision = revision;
        bool recent = Scope == RecentScope, withDetails = IncludeDetails;
        package = null; Files.Clear(); Preview = ""; Summary = ""; IsBusy = true; Status = "Préparation de l’aperçu…";
        try
        {
            var prepared = await Task.Run(() => service.Prepare(selectedId, recent, withDetails));
            if (revision != expectedRevision) { Status = "Les options ont changé. Génère à nouveau l’aperçu."; return; }
            package = prepared; Preview = prepared.Preview; Summary = prepared.Summary;
            foreach (var document in prepared.Documents) Files.Add(document.Description);
            Status = "Aperçu prêt. Seuls les trois fichiers affichés seront placés dans le ZIP. Aucun envoi automatique.";
        }
        catch (Exception ex) when (Handled(ex)) { Status = "Aperçu indisponible : " + ex.Message; }
        finally { IsBusy = false; }
    }
    public async Task ExportAsync(string destination)
    {
        var frozen = package; if (!CanExport || frozen == null) return;
        IsBusy = true; Status = "Création et vérification du ZIP…";
        try
        {
            await Task.Run(() => service.Export(frozen, destination));
            Status = "Archive créée et vérifiée : " + destination + ". Elle contient exactement l’aperçu affiché. Aucun fichier envoyé.";
        }
        catch (Exception ex) when (Handled(ex)) { Status = "Export non créé : " + ex.Message; }
        finally { IsBusy = false; }
    }
    private static bool Handled(Exception ex) => ex is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException or System.Text.Json.JsonException or System.Text.RegularExpressions.RegexMatchTimeoutException or NotSupportedException;
}
