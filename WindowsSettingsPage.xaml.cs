using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class WindowsSettingsPage : UserControl
{
    public WindowsSettingsPage()
    {
        InitializeComponent();
        Loaded += (_, _) => ScrollToTop();
        IsVisibleChanged += (_, _) => { if (IsVisible && DataContext is MainViewModel vm) { vm.PowerPlans.Refresh(); ScrollToTop(); } };
    }
    private void ScrollToTop() => Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(() =>
    {
        if (IsVisible) (Window.GetWindow(this)?.FindName("OptimizationCategoryContent") as ScrollViewer)?.ScrollToTop();
    }));
}
