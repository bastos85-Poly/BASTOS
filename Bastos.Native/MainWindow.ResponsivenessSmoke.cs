using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

namespace Bastos.Native;
public partial class MainWindow
{
    private sealed class CounterFixture : IDisposable
    {
        public int Reads, Disposals;
        public void Dispose() => Interlocked.Increment(ref Disposals);
    }
    private async Task RunResponsivenessSmokeAsync()
    {
        int checks=0;
        void Check(bool ok,string message){checks++;if(!ok)throw new InvalidOperationException(message);}
        int calls=0;
        var release=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var started=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var refresh=new ReadRefreshCoordinator(TimeSpan.FromMilliseconds(150));
        async Task SlowRead(){calls++;started.TrySetResult();await release.Task;}
        var first=refresh.RunAsync("network",SlowRead);
        await started.Task;
        var duplicates=Enumerable.Range(0,20).Select(_=>refresh.RunAsync("network",SlowRead)).ToArray();
        Check(duplicates.All(t=>ReferenceEquals(t,first)),"Lectures concurrentes dupliquees.");
        release.SetResult();await Task.WhenAll(duplicates);
        await refresh.RunAsync("network",SlowRead);Check(calls==1,"Lecture recente relancee.");
        await refresh.RunAsync("network",SlowRead,true);Check(calls==2,"Actualiser ne force pas la lecture.");
        await Task.Delay(180);await refresh.RunAsync("network",SlowRead);Check(calls==3,"Expiration ignoree.");
        int failures=0;
        for(int i=0;i<2;i++)try{await refresh.RunAsync("failed",()=>{failures++;throw new IOException("fixture");});}catch(IOException){}
        Check(failures==2,"Echec mis en cache.");
        var fixture=new CounterFixture();int uiThread=Environment.CurrentManagedThreadId,createThread=uiThread;
        using var blocked=new ManualResetEventSlim();
        using var entered=new ManualResetEventSlim();
        var sampler=new BackgroundSampler<CounterFixture,int>(()=>{createThread=Environment.CurrentManagedThreadId;return fixture;},c=>{Interlocked.Increment(ref c.Reads);entered.Set();blocked.Wait(TimeSpan.FromSeconds(5));return 42;});
        int ticks=0,acknowledgements=0;long maxUiLatency=0;
        var timer=new DispatcherTimer(TimeSpan.FromMilliseconds(20),DispatcherPriority.Normal,(_,_)=>ticks++,Dispatcher);timer.Start();
        try{
            var sample=sampler.ReadAsync();
            await Task.Run(()=>entered.Wait(TimeSpan.FromSeconds(3)));
            var second=sampler.ReadAsync();Check(ReferenceEquals(sample,second),"Mesures superposees.");
            // DispatcherTimer ticks can be coalesced for occluded windows.
            // Require two explicit UI acknowledgements while the sampler is
            // still blocked, and measure their actual queue latency instead.
            for(int pulse=0;pulse<2;pulse++)
            {
                var acknowledgement=new TaskCompletionSource<long>(TaskCreationOptions.RunContinuationsAsynchronously);
                var queued=Stopwatch.StartNew();
                Dispatcher.BeginInvoke(DispatcherPriority.Normal,new Action(()=>acknowledgement.TrySetResult(queued.ElapsedMilliseconds)));
                var completed=await Task.WhenAny(acknowledgement.Task,Task.Delay(1000));
                Check(completed==acknowledgement.Task && acknowledgement.Task.Result<1000,"Interface bloquee pendant la mesure lente : acquittement UI absent ou tardif.");
                maxUiLatency=Math.Max(maxUiLatency,acknowledgement.Task.Result);acknowledgements++;
            }
            Check(!sample.IsCompleted,"La mesure lente doit rester en attente pendant les acquittements UI.");
            Check(createThread!=uiThread,"Initialisation des compteurs sur le fil UI.");
            var closing=Stopwatch.StartNew();sampler.Dispose();closing.Stop();Check(closing.ElapsedMilliseconds<100,"Fermeture bloquante.");
            blocked.Set();Check(await sample==42,"Mesure incomplete.");
            for(int i=0;i<100&&fixture.Disposals==0;i++)await Task.Delay(10);
            Check(fixture.Reads==1&&fixture.Disposals==1,"Compteurs non liberes une seule fois.");
            try{sampler.ReadAsync();throw new InvalidOperationException("Mesure apres fermeture.");}catch(ObjectDisposedException){checks++;}
        }finally{blocked.Set();sampler.Dispose();timer.Stop();}
        int detections=0;
        var hardwareRelease=new TaskCompletionSource<HardwareProfile>(TaskCreationOptions.RunContinuationsAsynchronously);
        var hardware=new HardwareProfileService(Path.Combine(Path.GetTempPath(),"Responsiveness-"+Guid.NewGuid().ToString("N"),"hardware.json"),()=>{Interlocked.Increment(ref detections);return hardwareRelease.Task;});
        var requests=Enumerable.Range(0,20).Select(_=>hardware.GetOrDetectAsync()).ToArray();
        hardwareRelease.SetResult(new HardwareProfile{GpuName="AMD fixture",GpuDeviceIds=new[]{@"PCI\VEN_1002&DEV_1234"}});
        await Task.WhenAll(requests);Check(detections==1,"Detection materielle simultanee dupliquee.");
        var model=(MainViewModel)DataContext;
        model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="optimizations");
        model.OptimizationCategories.Selected=model.OptimizationCategories.Items.First(c=>c.Key=="graphics");
        var navigation=Stopwatch.StartNew();await model.RefreshAllConfigurationStatesAsync();navigation.Stop();
        Check(model.CurrentPage!=null,"Navigation indisponible.");
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Responsiveness-SmokeTest.txt"),
            $"OK : {checks} controles ; lectures concurrentes fusionnees, cache court, actualisation forcee, expiration, nouvel essai apres echec ; compteurs hors UI, {acknowledgements} acquittements UI pendant lecture bloquee, latence maximale {maxUiLatency} ms ({ticks} ticks de minuteur observes), fermeture sans attente et liberation ; 20 demandes materiel = 1 detection ; navigation GPU {navigation.ElapsedMilliseconds} ms.\n"+RuntimeTimingService.Summary());
    }
}
