namespace Bastos.Native.Services;

public sealed record SoftwarePackage(string Category, string Name, string Id, string? Source = null, string? ChocolateyId = null, string? CustomAction = null, string? Description = null, string? UninstallWarning = null);
