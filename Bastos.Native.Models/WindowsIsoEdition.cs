using System;
using System.Collections.Generic;

namespace Bastos.Native.Models;

public sealed record WindowsIsoEdition(int ImageIndex, string ImageName, string EditionId)
{
    public IReadOnlyList<string> Languages { get; init; } = Array.Empty<string>();
    public string DefaultUILanguage { get; init; } = "";
    public string Display => $"{ImageName} — index {ImageIndex}";
    public string InstallOptionDisplay => EditionId switch
    {
        "Core" => "Home",
        "Education" => "Éducation",
        "Professional" => "Pro",
        _ => ImageName
    };
    public override string ToString() => InstallOptionDisplay;
}

public sealed record WindowsIsoEditionCatalog(string IsoPath, string IsoSha256, IReadOnlyList<WindowsIsoEdition> Images);
