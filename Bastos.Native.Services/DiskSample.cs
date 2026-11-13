namespace Bastos.Native.Services;

public sealed record DiskSample(double Percent, double ReadBytesPerSecond, double WriteBytesPerSecond, long TotalBytes, long FreeBytes, bool IsActivity);
