using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Threading;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class GamePage : UserControl
{
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    public GamePage()
    {
        InitializeComponent();
        Loaded += (_, _) => Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(PageScroll.ScrollToTop));
        timer.Tick += (_, _) => (DataContext as MainViewModel)?.GameSettings.RefreshStatus();
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible) { (DataContext as MainViewModel)?.GameSettings.RefreshStatus(); timer.Start(); }
            else timer.Stop();
        };
        Unloaded += (_, _) => timer.Stop();
    }
}
