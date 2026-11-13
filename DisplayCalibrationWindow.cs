using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Bastos.Native.Services;

namespace Bastos.Native;

// Test patches use exact, uncompressed 8-bit RGB values. The active color profile,
// driver and monitor still determine their physical appearance.
public sealed class DisplayCalibrationWindow : Window
{
    private readonly Grid root = new();
    private readonly Grid pattern = new();
    private readonly Border controls = new();
    private readonly TextBlock dialStatus = new();
    private TextBlock? whiteClippingInfo;
    private readonly DisplayCalibrationController? calibration;
    private int index;
    private int uniformityLevel = 1;

    public DisplayCalibrationWindow(int initialIndex, DisplayCalibrationController? calibration = null)
    {
        this.calibration = calibration;
        index = Math.Clamp(initialIndex, 0, 4);
        Title = "BASTOS — Mires écran";
        WindowStyle = WindowStyle.None;
        WindowState = WindowState.Maximized;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.Black;
        Focusable = true;
        KeyDown += OnKeyDown;
        root.Children.Add(pattern);
        controls.VerticalAlignment = VerticalAlignment.Bottom;
        controls.Background = new SolidColorBrush(Color.FromArgb(220, 15, 21, 32));
        controls.Padding = new Thickness(14, 10, 14, 10);
        controls.Child = BuildControls();
        root.Children.Add(controls);
        Content = root;
        RenderPattern();
        Loaded += (_, _) => Focus();
    }

    private UIElement BuildControls()
    {
        var bar = new DockPanel { LastChildFill = true };
        var exit = ControlButton("Quitter · Échap", (_, _) => Close());
        DockPanel.SetDock(exit, Dock.Right);
        bar.Children.Add(exit);
        var next = ControlButton("Suivant →", (_, _) => Move(1));
        DockPanel.SetDock(next, Dock.Right);
        bar.Children.Add(next);
        var previous = ControlButton("← Précédent", (_, _) => Move(-1));
        DockPanel.SetDock(previous, Dock.Left);
        bar.Children.Add(previous);
        var labels = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        labels.Children.Add(new TextBlock
        {
            Text = "BASTOS · Mires SDR     ←/→ naviguer · ↑/↓ régler · R restaurer · H masquer · Échap quitter",
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            FontSize = 15
        });
        dialStatus.Foreground = Brushes.White;
        dialStatus.TextAlignment = TextAlignment.Center;
        dialStatus.FontSize = 14;
        labels.Children.Add(dialStatus);
        bar.Children.Add(labels);
        return bar;
    }

    private static Button ControlButton(string text, RoutedEventHandler handler)
    {
        var button = new Button { Content = text, MinWidth = 112, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(5, 0, 5, 0),
            Background = new SolidColorBrush(Color.FromRgb(39, 53, 79)), Foreground = Brushes.White,
            BorderBrush = new SolidColorBrush(Color.FromRgb(78, 102, 141)) };
        button.Click += handler;
        return button;
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape: Close(); break;
            case Key.Right: case Key.PageDown: Move(1); break;
            case Key.Left: case Key.PageUp: Move(-1); break;
            case Key.H:
                var hide = controls.Visibility == Visibility.Visible;
                controls.Visibility = hide ? Visibility.Collapsed : Visibility.Visible;
                if (index == 4 && pattern.Children.Count > 0)
                    pattern.Children[0].Visibility = hide ? Visibility.Collapsed : Visibility.Visible;
                break;
            case Key.Up: Adjust(1); break;
            case Key.Down: Adjust(-1); break;
            case Key.R:
                calibration?.RestorePrevious();
                UpdateDialStatus();
                break;
            case Key.D1: case Key.NumPad1: if (index == 4) { uniformityLevel = 0; RenderPattern(); } break;
            case Key.D2: case Key.NumPad2: if (index == 4) { uniformityLevel = 1; RenderPattern(); } break;
            case Key.D3: case Key.NumPad3: if (index == 4) { uniformityLevel = 2; RenderPattern(); } break;
        }
    }

    private void Move(int delta)
    {
        index = (index + delta + 5) % 5;
        RenderPattern();
        Focus();
    }

    private void RenderPattern()
    {
        pattern.Children.Clear();
        whiteClippingInfo = null;
        switch (index)
        {
            case 0: DrawBlack(); break;
            case 1: DrawWhite(); break;
            case 2: DrawGamma(); break;
            case 3: DrawColors(); break;
            case 4: DrawUniformity(); break;
        }
        UpdateDialStatus();
    }

    private void Adjust(int direction)
    {
        if (calibration == null || index == 4) return;
        var dial = index switch
        {
            0 => DisplayDial.Brightness,
            1 => DisplayDial.Contrast,
            2 => DisplayDial.Gamma,
            _ => DisplayDial.Vibrance
        };
        calibration.Adjust(dial, direction);
        UpdateDialStatus();
    }

    private void UpdateDialStatus()
    {
        if (calibration == null) { dialStatus.Text = string.Empty; return; }
        var value = index switch
        {
            0 => $"Luminosité {calibration.Brightness:+0.00;-0.00;0.00}",
            1 => $"Contraste {calibration.Contrast:F2}",
            2 => $"Gamma {calibration.Gamma:F2}",
            3 => calibration.VibranceAvailable ? $"Vibrance {calibration.Vibrance}" : "Vibrance indisponible",
            _ => "Uniformité · touches 1, 2, 3"
        };
        dialStatus.Text = $"{value}     {calibration.Status}";
        if (whiteClippingInfo != null)
        {
            var ramp = DisplayColorService.BuildRamp(calibration.Gamma, calibration.Brightness, calibration.Contrast);
            var firstClipped = -1;
            for (var level = 192; level <= 255; level++)
                if (ramp[level] == ushort.MaxValue) { firstClipped = level; break; }
            whiteClippingInfo.Text = firstClipped < 0
                ? "La courbe logicielle ne coupe aucun niveau clair. Les différences 253–255 peuvent malgré tout rester imperceptibles à l’œil."
                : $"Avec ces valeurs, la courbe logicielle rend les niveaux {firstClipped} à 255 identiques (blanc écrêté). Réduis le contraste jusqu’à revoir 240, 248 et 255 distincts.";
        }
    }

    private static TextBlock Text(string value, double size, Brush color, bool bold = false)
        => new() { Text = value, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
            Foreground = color, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Stretch, Margin = new Thickness(12, 5, 12, 5) };

    private static StackPanel CenteredPanel()
        => new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(24, 0, 24, 80) };

    private static Border Swatch(Brush fill, double height)
        => new() { Background = fill, Height = height, Margin = new Thickness(2), SnapsToDevicePixels = true };

    private void DrawBlack()
    {
        pattern.Background = Brushes.Black;
        var body = CenteredPanel();
        body.Children.Add(Text("1 · Réglage des noirs", 38, Brushes.White, true));
        body.Children.Add(Text("Commence par les grands repères : 0 doit rester noir ; 16, 32 et 64 doivent former une progression. Ensuite seulement, observe les petits écarts de 0 à 15.", 20, Brushes.White));
        var guide = new UniformGrid { Columns = 8, Margin = new Thickness(0, 34, 0, 8) };
        foreach (var value in new byte[] { 0, 8, 16, 24, 32, 48, 64, 96 })
        {
            var cell = new StackPanel();
            cell.Children.Add(Swatch(new SolidColorBrush(Color.FromRgb(value, value, value)), 70));
            cell.Children.Add(Text(value.ToString(), 16, Brushes.White));
            guide.Children.Add(cell);
        }
        body.Children.Add(guide);
        body.Children.Add(Text("Détail des ombres · niveaux RVB exacts 0 à 15", 19, Brushes.White, true));
        var row = new UniformGrid { Columns = 16, Margin = new Thickness(0, 16, 0, 0) };
        for (var value = 0; value < 16; value++)
        {
            var cell = new StackPanel();
            var gray = (byte)value;
            cell.Children.Add(Swatch(new SolidColorBrush(Color.FromRgb(gray, gray, gray)), 90));
            cell.Children.Add(Text(value.ToString(), 16, Brushes.White));
            row.Children.Add(cell);
        }
        body.Children.Add(row);
        body.Children.Add(Text("Les cases 1 à 5 peuvent rester presque invisibles. Si 16 et 24 se confondent aussi avec 0, monte d’un seul pas avec ↑ et compare. Si le fond 0 devient gris, redescends avec ↓ : n’éclaircis pas le noir pour forcer la visibilité de 1.", 18, Brushes.White));
        pattern.Children.Add(body);
    }

    private void DrawWhite()
    {
        pattern.Background = Brushes.White;
        var body = CenteredPanel();
        body.Children.Add(Text("2 · Réglage des blancs et du contraste", 38, Brushes.Black, true));
        body.Children.Add(Text("Commence par les grands repères 192, 208, 224, 240, 248 et 255. Leurs nuances doivent progresser vers le blanc, sans devenir toutes identiques.", 20, Brushes.Black));
        var guide = new UniformGrid { Columns = 6, Margin = new Thickness(0, 34, 0, 8) };
        foreach (var value in new byte[] { 192, 208, 224, 240, 248, 255 })
        {
            var cell = new StackPanel();
            var gray = new SolidColorBrush(Color.FromRgb(value, value, value));
            cell.Children.Add(new Border { Background = gray, BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1), Height = 75, Margin = new Thickness(3) });
            cell.Children.Add(Text(value.ToString(), 16, Brushes.Black));
            guide.Children.Add(cell);
        }
        body.Children.Add(guide);
        body.Children.Add(Text("Détail des hautes lumières · niveaux RVB exacts 240 à 255", 19, Brushes.Black, true));
        var row = new UniformGrid { Columns = 16, Margin = new Thickness(0, 16, 0, 0) };
        for (var value = 240; value <= 255; value++)
        {
            var cell = new StackPanel();
            var gray = (byte)value;
            cell.Children.Add(new Border { Background = new SolidColorBrush(Color.FromRgb(gray, gray, gray)),
                BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1), Height = 90, Margin = new Thickness(2) });
            cell.Children.Add(Text(value.ToString(), 16, Brushes.Black));
            row.Children.Add(cell);
        }
        body.Children.Add(row);
        whiteClippingInfo = Text(string.Empty, 19, Brushes.DarkRed, true);
        body.Children.Add(whiteClippingInfo);
        body.Children.Add(Text("Ne cherche pas à séparer 253, 254 et 255 coûte que coûte : ces écarts d’un seul niveau peuvent être invisibles même sans écrêtage.", 18, Brushes.Black));
        pattern.Children.Add(body);
    }

    private void DrawGamma()
    {
        pattern.Background = Brushes.Black;
        var body = CenteredPanel();
        body.Children.Add(Text("3 · Gamma : les tons moyens", 38, Brushes.White, true));
        body.Children.Add(Text("Dans BASTOS, 1,00 = aucune correction. ↑ au-dessus de 1,00 éclaircit les gris moyens ; ↓ en dessous de 1,00 les assombrit. Ne cherche pas à mettre 2,20 dans ce curseur : 2,2 désigne une cible possible du moniteur, pas le réglage EXFIL.", 20, Brushes.White));
        var reference = new UniformGrid { Columns = 5, Margin = new Thickness(0, 28, 0, 18) };
        foreach (var level in new byte[] { 0, 64, 128, 192, 255 })
        {
            var cell = new StackPanel();
            cell.Children.Add(new Border { Background = new SolidColorBrush(Color.FromRgb(level, level, level)),
                BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1), Height = 90, Margin = new Thickness(3) });
            cell.Children.Add(Text(level.ToString(), 16, Brushes.White));
            reference.Children.Add(cell);
        }
        body.Children.Add(reference);
        body.Children.Add(Text("Observe surtout 64 et 128 : ils doivent rester distincts de 0 et de 255, sans image globalement bouchée ou délavée.", 18, Brushes.White));
        var gradient = new LinearGradientBrush(Colors.Black, Colors.White, 0);
        body.Children.Add(new Border { Height = 115, Background = gradient, Margin = new Thickness(0, 20, 0, 20) });
        var steps = new UniformGrid { Columns = 32 };
        for (var i = 0; i < 32; i++)
        {
            var gray = (byte)Math.Round(i * 255.0 / 31);
            steps.Children.Add(Swatch(new SolidColorBrush(Color.FromRgb(gray, gray, gray)), 64));
        }
        body.Children.Add(steps);
        body.Children.Add(Text("Ce dégradé vérifie la continuité et l’absence de dominante colorée ; il ne mesure pas le gamma physique. Si tu ne peux pas trancher à l’œil, garde 1,00.", 18, Brushes.White));
        pattern.Children.Add(body);
    }

    private void DrawColors()
    {
        pattern.Background = Brushes.Black;
        var body = CenteredPanel();
        body.Children.Add(Text("4 · Couleurs et saturation", 38, Brushes.White, true));
        body.Children.Add(Text("Primaires et secondaires RVB numériques à 100 %. Les gris doivent rester neutres ; les teintes de peau ci-dessous sont seulement des exemples visuels, pas une référence de calibration.", 20, Brushes.White));
        var names = new[] { "Rouge", "Vert", "Bleu", "Cyan", "Magenta", "Jaune" };
        var colors = new[] { Colors.Red, Colors.Lime, Colors.Blue, Colors.Cyan, Colors.Magenta, Colors.Yellow };
        var primary = new UniformGrid { Columns = 6, Margin = new Thickness(0, 35, 0, 10) };
        for (var i = 0; i < names.Length; i++)
        {
            var cell = new StackPanel();
            cell.Children.Add(Swatch(new SolidColorBrush(colors[i]), 95));
            cell.Children.Add(Text(names[i], 16, Brushes.White));
            primary.Children.Add(cell);
        }
        body.Children.Add(primary);
        var neutral = new UniformGrid { Columns = 8, Margin = new Thickness(0, 12, 0, 22) };
        var neutralColors = new[] { Color.FromRgb(0,0,0), Color.FromRgb(64,64,64), Color.FromRgb(128,128,128), Color.FromRgb(192,192,192), Colors.White,
            Color.FromRgb(249,205,177), Color.FromRgb(216,160,126), Color.FromRgb(142,91,68) };
        foreach (var color in neutralColors) neutral.Children.Add(Swatch(new SolidColorBrush(color), 75));
        body.Children.Add(neutral);
        foreach (var color in new[] { Colors.Red, Colors.Lime, Colors.Blue })
            body.Children.Add(new Border { Height = 47, Background = new LinearGradientBrush(Colors.Black, color, 0), Margin = new Thickness(0, 5, 0, 5) });
        body.Children.Add(Text("Si les visages paraissent artificiels ou les couleurs criardes, réduis un peu la saturation.", 18, Brushes.White));
        pattern.Children.Add(body);
    }

    private void DrawUniformity()
    {
        var gray = uniformityLevel == 0 ? (byte)0 : uniformityLevel == 1 ? (byte)128 : (byte)255;
        pattern.Background = new SolidColorBrush(Color.FromRgb(gray, gray, gray));
        var color = gray == 255 ? Brushes.Black : Brushes.White;
        var body = CenteredPanel();
        body.Children.Add(Text("5 · Uniformité de la dalle", 38, color, true));
        body.Children.Add(Text("1 : noir · 2 : gris moyen · 3 : blanc. Cherche les taches, bandes et dominantes de couleur. Appuie sur H pour masquer les commandes.", 20, color));
        body.Children.Add(Text("Garde chaque fond affiché brièvement, surtout sur OLED.", 17, color));
        pattern.Children.Add(body);
    }
}
