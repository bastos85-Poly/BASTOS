namespace Bastos.Native.Services;

public sealed record CommandResult(bool Success, int ExitCode, string Output, string Error)
{
    public bool ProcessStopped { get; init; } = true;
    public bool ExecutionBlocked { get; init; }
    public string ErrorCode { get; init; } = "";
}
