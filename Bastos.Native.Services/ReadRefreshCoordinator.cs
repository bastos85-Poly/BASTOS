using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

// Used only for read-only UI refreshes. Apply/restore commands never pass here.
public sealed class ReadRefreshCoordinator
{
    private readonly Dictionary<string, Task> pending = new();
    private readonly Dictionary<string, long> completed = new();
    private readonly TimeSpan lifetime;
    public ReadRefreshCoordinator(TimeSpan lifetime) { this.lifetime = lifetime; }
    public Task RunAsync(string key, Func<Task> read, bool force = false)
    {
        lock (pending)
        {
            if (pending.TryGetValue(key, out var active)) return active;
            if (!force && completed.TryGetValue(key, out long stamp) && Stopwatch.GetElapsedTime(stamp) < lifetime)
                return Task.CompletedTask;
            var task = ExecuteAsync(key, read);
            pending[key] = task;
            return task;
        }
    }
    private async Task ExecuteAsync(string key, Func<Task> read)
    {
        await Task.Yield(); // Let navigation paint before starting the read.
        long started = Stopwatch.GetTimestamp();
        try
        {
            await read();
            lock (pending) completed[key] = Stopwatch.GetTimestamp();
        }
        finally
        {
            RuntimeTimingService.Record("read:" + key, Stopwatch.GetElapsedTime(started));
            lock (pending) pending.Remove(key);
        }
    }
}
