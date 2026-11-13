using System;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

// A single owner for native counters: initialize, read and dispose off the UI thread.
public sealed class BackgroundSampler<TSource, TValue> : IDisposable where TSource : IDisposable
{
    private readonly object gate = new();
    private readonly Func<TSource> create;
    private readonly Func<TSource, TValue> read;
    private TSource? source;
    private bool hasSource, stopped;
    private Task<TValue>? active;
    public BackgroundSampler(Func<TSource> create, Func<TSource, TValue> read) { this.create=create; this.read=read; }
    public Task<TValue> ReadAsync()
    {
        lock(gate)
        {
            ObjectDisposedException.ThrowIf(stopped, this);
            if(active is { IsCompleted:false }) return active;
            return active=Task.Run(()=> {
                    if(!hasSource) { source=create(); hasSource=true; }
                    return read(source!);
            });
        }
    }
    public void Dispose()
    {
        // Never block window closing on a slow native counter read.
        lock(gate)
        {
            if(stopped)return; stopped=true;
            Task? pending=active;
            _=Task.Run(async()=> { try { if(pending!=null)await pending; } catch { } finally { if(hasSource)source!.Dispose(); } });
        }
    }
}
