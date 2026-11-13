using System;
using System.Collections.Generic;
using System.Linq;

namespace Bastos.Native.Services;

public static class RuntimeTimingService
{
    private static readonly Dictionary<string, (int Count, double Total, double Max)> timings = new();
    public static void Record(string name, TimeSpan elapsed)
    {
        lock(timings)
        {
            if (!timings.ContainsKey(name) && timings.Count >= 64) return;
            timings.TryGetValue(name, out var old);
            timings[name] = (old.Count + 1, old.Total + elapsed.TotalMilliseconds, Math.Max(old.Max, elapsed.TotalMilliseconds));
        }
    }
    public static string Summary()
    {
        lock(timings) return string.Join(Environment.NewLine, timings.OrderBy(p=>p.Key).Select(p=>
            $"{p.Key}: count={p.Value.Count}; meanMs={p.Value.Total/p.Value.Count:0.0}; maxMs={p.Value.Max:0.0}"));
    }
}
