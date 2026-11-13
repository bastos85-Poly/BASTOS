namespace Bastos.Native.Models;

public sealed record DriverRecommendation(string Category, string Hardware, string Manufacturer, string CurrentVersion, string SourceName, string OfficialUrl, string Confidence, string Reason, string SearchTerm, string ResolutionStrategy, bool Sensitive);
