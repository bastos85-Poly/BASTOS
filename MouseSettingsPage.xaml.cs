using System;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class MouseSettingsPage : UserControl
{
    private readonly MouseSettingsViewModel viewModel;
    private Window owner;

    public MouseSettingsPage()
    {
        InitializeComponent();
        var log = new OperationLogService(new AppPaths());
        DataContext = viewModel = new MouseSettingsViewModel(new MouseAccelerationService(), text => log.Write("MouseAcceleration", text));
        Loaded += (_, _) =>
        {
            owner = Window.GetWindow(this);
            if (owner != null) owner.Activated += OnActivated;
            SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
            if(IsVisible)viewModel.SynchronizeCurveSelection();
        };
        Unloaded += (_, _) =>
        {
            if (owner != null) owner.Activated -= OnActivated;
            SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
            owner = null;
        };
        IsVisibleChanged += (_, _) => {if(IsVisible)viewModel.SynchronizeCurveSelection();};
    }

    private void RefreshIfVisible() { if (IsVisible) viewModel.Refresh(); }
    private void OnActivated(object sender, EventArgs args) => RefreshIfVisible();
    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs args)
    {
        if (!Dispatcher.HasShutdownStarted)
            Dispatcher.BeginInvoke(new Action(RefreshIfVisible));
    }
}
