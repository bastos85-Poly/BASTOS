using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows.Data;
using System.Windows.Markup;

namespace Bastos.Native;

// UI-only preview: never changes OS culture, scripts or persisted action identifiers.
public sealed class InterfaceLanguage : INotifyPropertyChanged
{
    public static InterfaceLanguage Instance { get; } = new();
    internal static string PreferencePath => Path.Combine(
        Array.IndexOf(Environment.GetCommandLineArgs(), "--language-smoke-test") >= 0
            ? Environment.GetEnvironmentVariable("BASTOS_LANGUAGE_TEST_DATA") ?? throw new InvalidOperationException("Isolated language test directory required.")
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS"), "InterfaceLanguage.txt");
    private string language = "fr";
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Language
    {
        get => language;
        set
        {
            if (value != "fr" && value != "en" || language == value) return;
            // Save before changing the UI so a failed save cannot silently lose the choice.
            Directory.CreateDirectory(Path.GetDirectoryName(PreferencePath)!);
            File.WriteAllText(PreferencePath, value);
            language = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Language)));
        }
    }
    private InterfaceLanguage()
    {
        try { if (File.Exists(PreferencePath) && File.ReadAllText(PreferencePath).Trim() == "en") language = "en"; }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    private static readonly Dictionary<string, string> English = new()
    {
        ["Accueil"] = "Home", ["Bastos Game"] = "Bastos Game",
        ["Tableau de bord"] = "Dashboard",
        ["Les performances essentielles de ce PC, actualisées en direct"] = "Essential PC performance, updated live",
        ["Surveillance en direct • matériel mémorisé sur ce PC"] = "Live monitoring • hardware saved on this PC",
        ["Surveillance en direct • matériel chargé depuis la mémoire locale"] = "Live monitoring • hardware loaded from local storage",
        ["Matériel détecté et mémorisé • surveillance en direct"] = "Hardware detected and saved • live monitoring",
        ["Première détection du matériel… ce résultat sera mémorisé"] = "Detecting hardware for the first time… results will be saved",
        ["Réinstallation facile Windows"] = "Easy Windows reinstall",
        ["Explorateur Internet"] = "Web browsers", ["Mise à jour matériel"] = "Hardware updates",
        ["Logiciels"] = "Software", ["Optimisations"] = "Optimizations",
        ["Personnalisation"] = "Personalization", ["Réglages avancés"] = "Advanced settings",
        ["Nettoyeur"] = "Cleaner", ["Réparation"] = "Repair", ["Journal"] = "Activity log",
        ["Votre PC, vos réglages."] = "Your PC, your settings.",
        ["VUE MATÉRIELLE"] = "HARDWARE OVERVIEW",
        ["Composants détectés une fois • utilisation en direct"] = "Detected components • live usage",
        ["PROCESSEUR"] = "PROCESSOR", ["MÉMOIRE VIVE"] = "MEMORY",
        ["CARTE GRAPHIQUE"] = "GRAPHICS CARD", ["DISQUE SYSTÈME"] = "SYSTEM DRIVE",
        ["CARTE RÉSEAU"] = "NETWORK ADAPTER", ["Actualiser"] = "Refresh",
        ["Aperçu de traduction : les autres pages et messages restent en français."] = "Translation preview: other pages and messages remain in French."
    };
    private static readonly Dictionary<string, string> Catalog = LoadCatalog();
    private static readonly (System.Text.RegularExpressions.Regex Pattern, string English)[] Templates = BuildTemplates();
    private static (System.Text.RegularExpressions.Regex, string)[] BuildTemplates()
    {
        var result = new List<(System.Text.RegularExpressions.Regex, string)>();
        foreach (var item in System.Linq.Enumerable.OrderByDescending(Catalog, entry => entry.Key.Length))
        {
            if (!item.Key.Contains("{0}")) continue;
            var pattern = System.Text.RegularExpressions.Regex.Escape(item.Key);
            for(int i=0;i<10;i++) pattern = pattern.Replace("\\{" + i + "}", "(?<v" + i + ">.+?)");
            result.Add((new System.Text.RegularExpressions.Regex("\\A"+pattern+"\\z", System.Text.RegularExpressions.RegexOptions.CultureInvariant | System.Text.RegularExpressions.RegexOptions.NonBacktracking,
                TimeSpan.FromMilliseconds(30)), item.Value));
        }
        return result.ToArray();
    }
    internal static readonly System.Collections.Generic.HashSet<string> Untranslated = new(StringComparer.Ordinal);
    private static Dictionary<string, string> LoadCatalog()
    {
        using var stream = typeof(InterfaceLanguage).Assembly.GetManifestResourceStream("Bastos.Interface.en.json")
            ?? throw new InvalidOperationException("English interface catalog missing.");
        return System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(stream)!;
    }
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string,string> Cache = new(StringComparer.Ordinal);
    public string Translate(string text)
    {
        if (Language != "en" || string.IsNullOrEmpty(text)) return text;
        if (Cache.TryGetValue(text, out var cached)) return cached;
        var translated = TranslateCore(text, 0);
        if (Cache.Count >= 4096) Cache.Clear();
        Cache.TryAdd(text, translated);
        return translated;
    }
    private string TranslateCore(string text, int depth)
    {
        if (Language != "en" || string.IsNullOrEmpty(text)) return text;
        if (Catalog.TryGetValue(text, out var translated) || English.TryGetValue(text, out translated)) return translated;
        var trimmed = text.Trim();
        if (trimmed != text && (Catalog.TryGetValue(trimmed, out translated) || English.TryGetValue(trimmed, out translated)))
            return text.Substring(0, text.IndexOf(trimmed, StringComparison.Ordinal)) + translated + text.Substring(text.IndexOf(trimmed, StringComparison.Ordinal) + trimmed.Length);
        if (depth < 3)
        {
            foreach (var template in Templates)
            {
                var match = template.Pattern.Match(text);
                if (!match.Success) continue;
                return System.Text.RegularExpressions.Regex.Replace(template.English, @"\{([0-9])\}", placeholder =>
                    TranslateCore(match.Groups["v" + placeholder.Groups[1].Value].Value, depth + 1));
            }
            if (text.Contains('\n'))
                return string.Join("\n", System.Linq.Enumerable.Select(text.Split('\n'), line => TranslateCore(line, depth + 1)));
        }
        if (Array.IndexOf(Environment.GetCommandLineArgs(), "--language-smoke-test") >= 0) Untranslated.Add(text);
        return text;
    }
}

public sealed class TranslateExtension : MarkupExtension
{
    public string? Text { get; set; }
    public string? Path { get; set; }
    public override object ProvideValue(IServiceProvider serviceProvider)
    {
        var binding = new MultiBinding { Mode = BindingMode.OneWay, Converter = new TranslationConverter() };
        binding.Bindings.Add(Path != null ? new Binding(Path) : new Binding { Source = Text ?? "" });
        binding.Bindings.Add(new Binding(nameof(InterfaceLanguage.Language)) { Source = InterfaceLanguage.Instance });
        return binding.ProvideValue(serviceProvider);
    }
    private sealed class TranslationConverter : IMultiValueConverter
    {
        public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) =>
            InterfaceLanguage.Instance.Translate(values[0] as string ?? "");
        public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
    }
}
