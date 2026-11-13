namespace Bastos.Native.Models;

public sealed record HardwareInventoryItem(string Category, string Name, string Details, StatusTone Tone = StatusTone.Neutral);
