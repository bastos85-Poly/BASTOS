namespace Bastos.Native.Services;

public sealed record NativeActionResult(bool Success, string Message, int ExitCode = 0);
