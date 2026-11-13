using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using Bastos.Native.Models;

namespace Bastos.Native;

// Shared presentation for result messages. No command or execution behavior.
public sealed class OperationMessageView : UserControl
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(nameof(Text), typeof(string), typeof(OperationMessageView), new PropertyMetadata("", Changed));
    public static readonly DependencyProperty DetailProperty = DependencyProperty.Register(nameof(Detail), typeof(string), typeof(OperationMessageView), new PropertyMetadata("", Changed));
    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public string Detail { get => (string)GetValue(DetailProperty); set => SetValue(DetailProperty, value); }
    private readonly StackPanel panel = new();
    private readonly TextBlock summary = new() { TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock next = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0, 6, 0, 0), FontWeight = FontWeights.Normal };
    private readonly TextBlock effects = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0, 6, 0, 0), FontWeight = FontWeights.Normal };
    private readonly TextBox details = new() { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Background = System.Windows.Media.Brushes.Transparent,
        BorderThickness = new(0), Margin = new(0, 8, 0, 0), FontWeight = FontWeights.Normal };
    private readonly Expander expander = new() { Header = "Détails", Margin = new(0, 8, 0, 0), FontWeight = FontWeights.Normal };
    public OperationMessageView()
    {
        foreach (var block in new[] { summary, next })
            block.SetBinding(TextBlock.ForegroundProperty, new Binding(nameof(Foreground)) { Source = this });
        effects.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        expander.SetResourceReference(ForegroundProperty, "MutedBrush");
        details.SetResourceReference(ForegroundProperty, "MutedBrush");
        expander.Content = details;
        panel.Children.Add(summary); panel.Children.Add(next); panel.Children.Add(effects); panel.Children.Add(expander);
        Content = panel;
        Refresh();
    }
    private static void Changed(DependencyObject source, DependencyPropertyChangedEventArgs args) => ((OperationMessageView)source).Refresh();
    private void Refresh()
    {
        var value = MessagePresentation.From(Text, Detail);
        summary.Text = value.Summary;
        next.Text = value.NextStep;
        effects.Text = value.Effects;
        details.Text = value.Details;
        next.Visibility = value.NextStep.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        effects.Visibility = value.Effects.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        expander.Visibility = value.Details.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        expander.IsExpanded = false;
    }
}
