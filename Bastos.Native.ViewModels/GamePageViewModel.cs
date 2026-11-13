using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Windows.Input;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class GamePageViewModel : ObservableObject
{
    private readonly AppPaths paths;
    private readonly BastosGameService game;
    private bool autoDetect, background, observe, auxiliary;
    private string priority = "High", headline = "Lecture de l’état…", detail = "", activity = "", message = "", accent = "#8FA8C7";
    public bool AutoDetect { get => autoDetect; set => SetProperty(ref autoDetect, value); }
    public bool Background { get => background; set => SetProperty(ref background, value); }
    public bool Observe { get => observe; set => SetProperty(ref observe, value); }
    public bool Auxiliary { get => auxiliary; set => SetProperty(ref auxiliary, value); }
    public string Priority { get => priority; set => SetProperty(ref priority, value); }
    public string Headline { get => headline; private set => SetProperty(ref headline, value); }
    public string Detail { get => detail; private set => SetProperty(ref detail, value); }
    public string Activity { get => activity; private set => SetProperty(ref activity, value); }
    public string Accent { get => accent; private set => SetProperty(ref accent, value); }
    public string Message { get => message; private set => SetProperty(ref message, value); }
    public ICommand ApplyCommand { get; }
    public ICommand ReloadCommand { get; }
    public GamePageViewModel(AppPaths paths, BastosGameService game)
    {
        this.paths = paths; this.game = game;
        ApplyCommand = new AsyncRelayCommand(ApplyAsync);
        ReloadCommand = new RelayCommand(Reload);
        Reload();
    }
    private string ProfilesPath => Path.Combine(paths.GameRoot, "Profiles.json");
    private JsonObject ReadProfiles() => File.Exists(ProfilesPath)
        ? JsonNode.Parse(File.ReadAllText(ProfilesPath)) as JsonObject ?? throw new InvalidDataException("Profils illisibles.")
        : new JsonObject();
    public void Reload()
    {
        try
        {
            var config = game.Load(); var profiles = ReadProfiles();
            AutoDetect = config.AutoDetect; Background = config.OptimizeBackground;
            Observe = profiles["ObserveOnly"]?.GetValue<bool>() ?? false;
            Auxiliary = profiles["OptimizeAuxiliary"]?.GetValue<bool>() ?? true;
            Priority = profiles["DefaultPriority"]?.GetValue<string>() ?? "High";
            Message = "Vos réglages actuels. Cliquez sur « Appliquer mes réglages » pour enregistrer vos changements.";
        }
        catch (Exception ex) { Message = "Lecture impossible : " + ex.Message; }
        RefreshStatus();
    }
    private async Task ApplyAsync()
    {
        try
        {
            if (Priority != "Normal" && Priority != "AboveNormal" && Priority != "High")
                throw new InvalidOperationException("Choisissez une priorité dans la liste.");
            // Re-read both files at save time: retain the latest lists and per-game profiles.
            var config = JsonNode.Parse(File.ReadAllText(paths.GameConfig)) as JsonObject
                ?? throw new InvalidDataException("Configuration illisible.");
            var profiles = ReadProfiles();
            config["AutoDetect"] = AutoDetect; config["OptimizeBackground"] = Background;
            profiles["ObserveOnly"] = Observe; profiles["OptimizeAuxiliary"] = Auxiliary;
            profiles["DefaultPriority"] = Priority; profiles["Version"] = 3;
            AtomicWrite(ProfilesPath, profiles);
            AtomicWrite(paths.GameConfig, config);
            Message = "Réglages enregistrés. Le moteur les relit automatiquement ; s’il est arrêté, cliquez sur Démarrer.";
            await Task.Delay(1200);
            RefreshStatus();
        }
        catch (Exception ex) { Message = "Enregistrement incomplet : " + ex.Message + " Rechargez les réglages avant de réessayer."; }
    }
    private static void AtomicWrite(string path, JsonObject data)
    {
        string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temp, data.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public void RefreshStatus()
    {
        try
        {
            var config = game.Load();
            var profiles = ReadProfiles();
            bool observation = profiles["ObserveOnly"]?.GetValue<bool>() ?? false;
            if (!config.Enabled)
            {
                Headline = "Bastos Game est arrêté"; Accent = "#A6B4C8";
                Detail = "Démarrez le moteur, puis lancez votre jeu comme d’habitude.";
                Activity = "L’arrêt demande la restauration des réglages appliqués. Le journal détaille les éventuels échecs.";
                return;
            }
            var status = JsonNode.Parse(File.ReadAllText(paths.GameStatus)) as JsonObject
                ?? throw new InvalidDataException();
            var age = DateTimeOffset.UtcNow - DateTimeOffset.Parse(status["UpdatedUtc"]!.GetValue<string>());
            if (age.TotalSeconds < -5 || age.TotalSeconds > 10 || status["State"]?.GetValue<string>() != "Ready")
                throw new InvalidDataException();
            var games = status["ActiveGames"] as JsonArray ?? new JsonArray();
            Accent = observation ? "#E7B761" : "#55D6B0";
            Headline = observation ? "Observation seule activée" : games.Count > 0 ? "Votre session de jeu est détectée" : "Prêt pour votre prochaine partie";
            Detail = observation
                ? "Le moteur repère les jeux, sans appliquer d’optimisation aux processus. Les anciennes modifications sont restaurées."
                : games.Count > 0 ? "Bastos adapte les processus autorisés. Les actions réellement appliquées sont détaillées dans le journal."
                : "Lancez un jeu : Bastos le détectera automatiquement, ou utilisez la liste de jeux ajoutés.";
            string names = string.Join(", ", games.Select(g => g?["Name"]?.GetValue<string>() ?? "Jeu"));
            Activity = games.Count == 0 ? "Aucun jeu détecté pour le moment" : "Jeux détectés : " + names;
            Activity += "  •  Moteur " + (status["EngineVersion"]?.GetValue<string>() ?? "actif");
            if (!observation && games.Count > 0)
                Activity += "  •  Arrière-plan : " + (status["OptimizedBackground"]?.ToString() ?? "0") + " processus";
        }
        catch
        {
            Headline = "Le moteur ne confirme pas son activité"; Accent = "#E7B761";
            Detail = "Son état est absent, trop ancien ou en erreur. Cliquez sur Démarrer, puis consultez le journal si cela persiste.";
            Activity = "Aucune optimisation confirmée par cette page.";
        }
    }
}
