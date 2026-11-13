using System.Collections.Generic;

namespace Bastos.Native.Models;

public sealed record HardwareAnalysisResult(bool Success, string Message, IReadOnlyList<HardwareInventoryItem> Inventory, IReadOnlyList<DriverRecommendation> Recommendations, int DetectedDevices, int ProblemCount, string ReportPath)
{
    public OperationResult? Operation { get; init; }
}
