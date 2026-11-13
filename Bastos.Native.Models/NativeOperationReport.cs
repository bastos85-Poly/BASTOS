using System.Collections.Generic;

namespace Bastos.Native.Models;

// Data is persisted before verification; the engine owns the protocol envelope.
public sealed record NativeOperationReport(bool Success, string Message,
    IReadOnlyDictionary<string, object?> Data, string ErrorCode = "", string TechnicalDetail = "");
