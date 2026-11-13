using System;
using System.Globalization;

namespace Bastos.Native.Models;

public sealed record WindowsDownloadChoice(string Family, string Version, string Language, string Locale,
    string Architecture, string FileName, string Url, string SourcePage)
{
    public override string ToString() => FileName;
    public string LanguageDisplay
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Locale)) return Language;
            try { return CultureInfo.GetCultureInfo(Locale).NativeName + " — " + Locale; }
            catch (CultureNotFoundException) { return Language; }
        }
    }
}
