namespace Bastos.Native.Models;

public sealed record IsoBuildProgress(double Percent, string Phase, string Message, int Step, int TotalSteps, bool IsIndeterminate = false);
