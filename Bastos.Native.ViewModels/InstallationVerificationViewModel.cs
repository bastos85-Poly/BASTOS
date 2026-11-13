using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class InstallationVerificationViewModel : ObservableObject
{
    private readonly InstallationVerificationService service;
    private readonly InstallationReviewDisplayState displayState;
    private const string MissingProfile = "Aucun profil de contrôle trouvé. Les médias préparés avec cette version de Bastos enregistreront les réglages demandés pour vérifier Windows après sa réinstallation.";
    private string summary = MissingProfile;
    private string date = "";
    private bool busy;
    private Task? active;
    public bool HasProfile => service.HasProfile;
    public bool ShouldShowAutomatically
    {
        get
        {
            try { return displayState.ShouldShow(); }
            catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or System.Security.SecurityException)
            { System.Diagnostics.Trace.TraceError(ex.ToString()); return HasProfile; }
        }
    }
    public Action PrepareMarkDisplayed()
    {
        try
        {
            var mark = displayState.PrepareMarkShown();
            return () =>
            {
                try { mark(); }
                catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or System.Security.SecurityException)
                { System.Diagnostics.Trace.TraceError(ex.ToString()); }
            };
        }
        catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { System.Diagnostics.Trace.TraceError(ex.ToString()); return () => { }; }
    }
    public bool IsBusy { get => busy; private set { SetProperty(ref busy, value); CheckCommand.RaiseCanExecuteChanged(); } }
    public string Summary { get => summary; private set => SetProperty(ref summary, value); }
    public string Date { get => date; private set => SetProperty(ref date, value); }
    public ObservableCollection<InstallationCheck> Checks { get; } = new();
    public AsyncRelayCommand CheckCommand { get; }
    public InstallationVerificationViewModel(AppPaths paths)
    {
        service = new(paths);
        displayState = new(paths.StateRoot, InstallationVerificationService.ProfilePath);
        CheckCommand = new(CheckAsync, () => !IsBusy, () => "Le bilan de l’installation est en cours. Attends sa fin.");
    }
    public Task CheckAsync()
    {
        if (active is { IsCompleted: false }) return active;
        return active = CheckCoreAsync();
    }
    private async Task CheckCoreAsync()
    {
        RaisePropertyChanged(nameof(HasProfile));
        if (!HasProfile) { Checks.Clear(); Date = ""; Summary = MissingProfile; return; }
        IsBusy = true;
        Checks.Clear(); Date = "";
        Summary = "Vérification des réglages réellement présents dans Windows…";
        try
        {
            var result = await service.CheckAsync();
            Display(result);
        }
        catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or System.Collections.Generic.KeyNotFoundException or FormatException)
        { Summary = "Bilan non confirmé : " + ex.Message + " Vérifie les fichiers du média et les rapports disponibles dans Journal, puis réessaie le contrôle."; }
        finally { IsBusy = false; }
    }
    internal void Display(InstallationReview result)
    {
        Checks.Clear();
        foreach (var check in result.Checks) Checks.Add(check);
        Summary = result.Summary;
        Date = $"Contrôle du {result.CheckedUtc.ToLocalTime():dd/MM/yyyy à HH:mm:ss} • Lecture seule • Rapport conservé dans Journal";
    }
}
