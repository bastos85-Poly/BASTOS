using System.Collections.Generic;
using System.Linq;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.ViewModels;

public sealed record OptimizationCategory(string Key, string Title, string Description, string IconData);

// Navigation only: choosing a category must never apply a system setting.
public sealed class OptimizationCategoriesViewModel : ObservableObject
{
    public IReadOnlyList<OptimizationCategory> Items { get; } = new[]
    {
        new OptimizationCategory("cpu", "Processeur", "Affinité des interruptions",
            "M12,3 L15,3 L15,6 L18,6 L18,9 L21,9 L21,15 L18,15 L18,18 L15,18 L15,21 L9,21 L9,18 L6,18 L6,15 L3,15 L3,9 L6,9 L6,6 L9,6 L9,3 Z M9,9 L15,9 L15,15 L9,15 Z"),
        new OptimizationCategory("network", "Carte réseau", "Ethernet et connectivité",
            "M5,3 L19,3 L19,14 L16,14 L16,18 L8,18 L8,14 L5,14 Z M8,6 L8,10 M11,6 L11,10 M14,6 L14,10 M17,6 L17,10 M12,18 L12,22 M8,22 L16,22"),
        new OptimizationCategory("graphics", "Carte graphique", "Réglages de performances GPU",
            "M3,5 L21,5 L21,18 L3,18 Z M3,8 L1,8 M3,15 L1,15 M6,18 L6,21 L17,21 L17,18 M16,8 L19,8 M16,11 L19,11 M16,14 L19,14 M14,11.5 A4,4 0 1 1 6,11.5 A4,4 0 1 1 14,11.5 M10,7.5 L10,15.5 M6,11.5 L14,11.5"),
        new OptimizationCategory("sound", "Son", "Audio compétitif et veille du codec",
            "M4,10 L8,10 L13,5 L13,21 L8,16 L4,16 Z M17,9 Q21,13 17,17 M20,6 Q26,13 20,20"),
        new OptimizationCategory("devices", "Périphériques", "Veille USB par périphérique",
            "M8,3 L16,3 L16,15 L8,15 Z M12,15 L12,21 M9,21 L15,21 M10,6 L14,6"),
        new OptimizationCategory("memory", "Mémoire vive", "Nettoyage de la liste standby",
            "M2,6 L22,6 L22,17 L2,17 Z M5,9 L9,9 L9,14 L5,14 Z M12,9 L16,9 L16,14 L12,14 Z M19,9 L19,14 M5,17 L5,20 M8,17 L8,20 M11,17 L11,20 M15,17 L15,20 M18,17 L18,20 M21,17 L21,20"),
        new OptimizationCategory("windows", "Jeux et performances", "Jeux, souris, timers et Steam",
            "M3,3 L10,3 L10,10 L3,10 Z M14,3 L21,3 L21,10 L14,10 Z M3,14 L10,14 L10,21 L3,21 Z M14,14 L21,14 L21,21 L14,21 Z"),
    };

    private OptimizationCategory selected;

    public OptimizationCategoriesViewModel()
    {
        selected = Items.First(item => item.Key == "windows");
    }

    public OptimizationCategory Selected
    {
        get => selected;
        set
        {
            if (value == null || !Items.Contains(value) || !SetProperty(ref selected, value)) return;
            RaisePropertyChanged(nameof(IsNetwork));
            RaisePropertyChanged(nameof(IsCpu));
            RaisePropertyChanged(nameof(IsSound));
            RaisePropertyChanged(nameof(IsDevices));
            RaisePropertyChanged(nameof(IsWindows));
            RaisePropertyChanged(nameof(IsGraphics));
            RaisePropertyChanged(nameof(IsMouse));
            RaisePropertyChanged(nameof(IsKeyboard));
            RaisePropertyChanged(nameof(IsMemory));
            RaisePropertyChanged(nameof(IsSecurity));
            RaisePropertyChanged(nameof(IsEmpty));
        }
    }

    public bool IsDevices => Selected.Key == "devices";
    public bool IsCpu => Selected.Key == "cpu";
    public bool IsSound => Selected.Key == "sound";
    public bool IsNetwork => Selected.Key == "network";
    public bool IsWindows => Selected.Key == "windows";
    public bool IsGraphics => Selected.Key == "graphics";
    public bool IsMouse => Selected.Key == "mouse";
    public bool IsKeyboard => Selected.Key == "keyboard";
    public bool IsMemory => Selected.Key == "memory";
    public bool IsSecurity => Selected.Key == "security";
    public bool IsEmpty => !IsCpu && !IsDevices && !IsSound && !IsNetwork && !IsWindows && !IsGraphics && !IsMouse && !IsKeyboard && !IsMemory && !IsSecurity;
}

