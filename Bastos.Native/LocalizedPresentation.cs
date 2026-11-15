using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;

namespace Bastos.Native;

// Translate rendered text only: commands, selection values, model strings, scripts,
// user input and raw diagnostic text are never rewritten.
internal static class LocalizedPresentation
{
    private static readonly List<WeakReference<TextState>> states = new();
    private static readonly DependencyProperty WatchedProperty = DependencyProperty.RegisterAttached("Watched", typeof(bool), typeof(LocalizedPresentation));
    private static readonly DependencyProperty StateProperty = DependencyProperty.RegisterAttached(
        "State", typeof(TextState), typeof(LocalizedPresentation));
    internal static void Initialize()
    {
        EventManager.RegisterClassHandler(typeof(ToolTip), ToolTip.OpenedEvent,
            new RoutedEventHandler((sender, _) => ((ToolTip)sender).Dispatcher.BeginInvoke(new Action(() => AttachTree((ToolTip)sender)))));
        EventManager.RegisterClassHandler(typeof(ContextMenu), ContextMenu.OpenedEvent,
            new RoutedEventHandler((sender, _) => ((ContextMenu)sender).Dispatcher.BeginInvoke(new Action(() => AttachTree((ContextMenu)sender)))));
        EventManager.RegisterClassHandler(typeof(TextBlock), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, _) => AttachBlock((TextBlock)sender)));
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, _) => Watch((Window)sender)));
        InterfaceLanguage.Instance.PropertyChanged += (_, _) =>
        {
            foreach (Window window in Application.Current.Windows) { Watch(window); AttachTree(window); }
            for (int i = states.Count - 1; i >= 0; i--)
                if (states[i].TryGetTarget(out var state)) state.Apply(); else states.RemoveAt(i);
        };
    }
    internal static void Watch(Window window)
    {
        if ((bool)window.GetValue(WatchedProperty)) return;
        window.SetValue(WatchedProperty, true);
        Attach(window, Window.TitleProperty, window);
        window.LayoutUpdated += (_, _) => AttachTree(window);
        AttachTree(window);
    }
    private static void AttachTree(DependencyObject node)
    {
        if (node is ComboBox combo && !(bool)combo.GetValue(WatchedProperty))
        {
            combo.SetValue(WatchedProperty, true);
            combo.DropDownOpened += (_, _) => combo.Dispatcher.BeginInvoke(new Action(() =>
            {
                if (combo.Template.FindName("PART_Popup", combo) is System.Windows.Controls.Primitives.Popup popup && popup.Child != null) AttachTree(popup.Child);
            }));
        }
        if (node is TextBlock block) AttachBlock(block);
        for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(node); i++)
            AttachTree(System.Windows.Media.VisualTreeHelper.GetChild(node, i));
    }
    private static void AttachBlock(TextBlock block)
    {
        if (block.GetValue(StateProperty) != null) return;
        // Read-only diagnostic text and editable controls must remain exact.
        for (DependencyObject? parent = block; parent != null; parent = System.Windows.Media.VisualTreeHelper.GetParent(parent))
            if (parent is TextBox || parent is PasswordBox) return;
        if (block.Inlines.Count > 1)
        {
            foreach (var inline in block.Inlines) AttachInline(inline, block);
        }
        else Attach(block, TextBlock.TextProperty, block);
    }
    private static void AttachInline(Inline inline, TextBlock owner)
    {
        if (inline is Run run) Attach(run, Run.TextProperty, owner);
        if (inline is Span span) foreach (var child in span.Inlines) AttachInline(child, owner);
    }
    private static void Attach(DependencyObject target, DependencyProperty property, FrameworkElement lifetime)
    {
        if (target.GetValue(StateProperty) != null) return;
        var state = new TextState(target, property, lifetime);
        target.SetValue(StateProperty, state);
        states.Add(new WeakReference<TextState>(state));
        state.Apply();
    }
    private sealed class TextState
    {
        private readonly DependencyObject target;
        private readonly DependencyProperty property;
        private string original;
        private bool applying;
        private readonly DependencyPropertyDescriptor descriptor;
        private bool listening;
        public TextState(DependencyObject target, DependencyProperty property, FrameworkElement lifetime)
        {
            this.target = target; this.property = property;
            original = target.GetValue(property) as string ?? "";
            descriptor = DependencyPropertyDescriptor.FromProperty(property, target.GetType());
            Enable();
            lifetime.Unloaded += (_, _) => { descriptor.RemoveValueChanged(target, Changed); listening = false; };
            lifetime.Loaded += (_, _) => { Enable(); Apply(); };
        }
        private void Enable() { if (!listening) { descriptor.AddValueChanged(target, Changed); listening = true; } }
        private void Changed(object? sender, EventArgs e)
        {
            if (applying) return;
            original = target.GetValue(property) as string ?? "";
            Apply();
        }
        public void Apply()
        {
            applying = true;
            try { var translated = InterfaceLanguage.Instance.Translate(original); if (!Equals(target.GetValue(property), translated)) target.SetCurrentValue(property, translated); }
            finally { applying = false; }
        }
    }
}
