using System;

namespace Bastos.Native.Models;

public sealed class HardwareProfile
{
    public int Version { get; set; } = 1;
    public DateTime DetectedUtc { get; set; } = DateTime.UtcNow;
    public string CpuName { get; set; } = "Processeur";
    public string MemoryName { get; set; } = "Mémoire vive";
    public string GpuName { get; set; } = "Carte graphique";
    // null : ancien cache ou inventaire indisponible ; vide : aucun GPU reconnu.
    public string[]? GpuDeviceIds { get; set; }
    public string DiskName { get; set; } = "Disque système";
    public string NetworkName { get; set; } = "Carte réseau";
}
