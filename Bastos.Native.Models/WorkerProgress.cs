namespace Bastos.Native.Models;

public sealed record WorkerProgress(int Percent, string Phase, string Message, int Step = 0, int TotalSteps = 0);
