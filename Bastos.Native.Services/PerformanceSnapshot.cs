using System;

namespace Bastos.Native.Services;

public sealed record PerformanceSnapshot(double CpuPercent, string CpuName, int LogicalProcessors, double MemoryPercent, ulong MemoryUsed, ulong MemoryTotal, GpuSample Gpu, NetworkSample Network, DiskSample Disk, DateTime CapturedAt);
