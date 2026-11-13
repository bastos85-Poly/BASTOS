using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class DisplayCalibrationPage : UserControl
{
    private readonly DisplayCalibrationController controller;
    private readonly DispatcherTimer applyTimer;
    private bool updating;

    public DisplayCalibrationPage()
    {
        InitializeComponent();
        controller = new DisplayCalibrationController();
        applyTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
        applyTimer.Tick += (_, _) => { applyTimer.Stop(); ApplySliders(); };
        controller.ValuesChanged += (_, _) => SyncSliders();
        controller.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(controller.Status)) ColorStatus.Text = controller.Status; };
        VibranceSlider.Minimum = controller.VibranceMinimum;
        VibranceSlider.Maximum = controller.VibranceMaximum;
        VibranceSlider.IsEnabled = controller.VibranceAvailable;
        SyncSliders();
    }

    private void OpenPattern(object sender, RoutedEventArgs e)
    {
        var index = int.TryParse((sender as Button)?.Tag?.ToString(), out var value) ? value : 0;
        applyTimer.Stop();
        var window = new DisplayCalibrationWindow(index, controller) { Owner = Window.GetWindow(this) };
        window.ShowDialog();
        SyncSliders();
    }

    private void OnSliderChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (updating || applyTimer == null) return;
        applyTimer.Stop();
        applyTimer.Start();
        UpdateValues();
    }

    private void ApplySliders()
    {
        if (!controller.Set(GammaSlider.Value, BrightnessSlider.Value, ContrastSlider.Value, (int)Math.Round(VibranceSlider.Value)))
            SyncSliders();
    }

    private void SyncSliders()
    {
        updating = true;
        GammaSlider.Value = controller.Gamma;
        BrightnessSlider.Value = controller.Brightness;
        ContrastSlider.Value = controller.Contrast;
        VibranceSlider.Value = controller.Vibrance;
        updating = false;
        UpdateValues();
        ColorStatus.Text = controller.Status;
    }

    private void UpdateValues()
    {
        GammaValue.Text = GammaSlider.Value.ToString("F2");
        BrightnessValue.Text = BrightnessSlider.Value.ToString("+0.00;-0.00;0.00");
        ContrastValue.Text = ContrastSlider.Value.ToString("F2");
        VibranceValue.Text = controller.VibranceAvailable ? ((int)Math.Round(VibranceSlider.Value)).ToString() : "Indispo.";
        CalibrationGuidance.Text = BrightnessSlider.Value <= -0.04
            ? "Image sombre : la luminosité logicielle négative coupe les premiers détails. Reviens à 0,00 avant de toucher au gamma."
            : ContrastSlider.Value >= 1.08
                ? "Contraste élevé : plusieurs blancs peuvent devenir identiques. Reviens vers 1,00 avant de juger la mire."
                : Math.Abs(GammaSlider.Value - 1.0) >= 0.12
                    ? "Gamma éloigné du neutre : compare avec 1,00. Ce curseur modifie les tons moyens, pas le gamma mesuré de l’écran."
                    : "Base conseillée sans sonde : gamma 1,00 · luminosité logicielle 0,00 · contraste 1,00. Ajuste la lumière de la dalle dans le menu de l’écran.";
    }

    private void RestorePrevious(object sender, RoutedEventArgs e)
    {
        applyTimer.Stop();
        controller.RestorePrevious();
        SyncSliders();
    }

    private void SaveCurrent(object sender, RoutedEventArgs e)
    {
        var awaitingApply = applyTimer.IsEnabled;
        applyTimer.Stop();
        if (awaitingApply) ApplySliders();
        controller.SaveCurrent();
    }

    private void ShowDesktop(object sender, RoutedEventArgs e)
    {
        var awaitingApply = applyTimer.IsEnabled;
        applyTimer.Stop();
        if (awaitingApply) ApplySliders();
        var window = Window.GetWindow(this);
        if (window != null) window.WindowState = WindowState.Minimized;
    }

    private void ResetNeutral(object sender, RoutedEventArgs e)
    {
        applyTimer.Stop();
        if (!controller.ResetNeutral()) SyncSliders();
    }

    public void ReleaseControl()
    {
        applyTimer.Stop();
        controller.Dispose();
    }
}
