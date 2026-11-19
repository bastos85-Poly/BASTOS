using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public static class WindowsDownloadCatalog
{
    public const string Windows11Page="https://www.microsoft.com/fr-fr/software-download/windows11";
    public const string Windows10Page="https://www.microsoft.com/en-us/software-download/windows10ISO";
    public static readonly string[] Pages={Windows11Page,Windows10Page};
    private static readonly HttpClient Client=new(){Timeout=TimeSpan.FromSeconds(25)};
    public static IReadOnlyList<WindowsDownloadChoice> ReadBundled()
    {
        using var stream=typeof(WindowsDownloadCatalog).Assembly.GetManifestResourceStream("Bastos.WindowsDownloadCatalog.json");
        return stream==null?Array.Empty<WindowsDownloadChoice>():
            (JsonSerializer.Deserialize<WindowsDownloadChoice[]>(stream)??Array.Empty<WindowsDownloadChoice>()).Where(IsSupportedChoice).ToArray();
    }
    public static bool IsSupportedChoice(WindowsDownloadChoice item)=>
        item.Version.Contains(" Consumer ",StringComparison.Ordinal) && item.Url==item.SourcePage &&
        ((item.Family=="Windows 11" && item.SourcePage==Windows11Page && item.Architecture=="x64") ||
         (item.Family=="Windows 10" && item.SourcePage==Windows10Page && item.Architecture is "x64" or "x86"));
    public static async Task<(IReadOnlyList<WindowsDownloadChoice> Items,string Message)> RefreshAsync(IReadOnlyList<WindowsDownloadChoice> fallback,CancellationToken cancellationToken=default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var items=fallback.Where(IsSupportedChoice).ToArray();int reached=0;
        foreach(string page in Pages)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var request=new HttpRequestMessage(HttpMethod.Get,page);
                request.Headers.UserAgent.ParseAdd("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/138.0.0.0 Safari/537.36");
                using var response=await Client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancellationToken);
                if(response.IsSuccessStatusCode)reached++;
            }
            catch(Exception error) when(!cancellationToken.IsCancellationRequested && error is HttpRequestException or TaskCanceledException){ }
        }
        cancellationToken.ThrowIfCancellationRequested();
        return(items,reached>0?"Sources Microsoft actualisées. Un lien neuf sera généré pour chaque téléchargement.":
            "Microsoft est momentanément inaccessible. Les choix officiels sont conservés ; réessaie le téléchargement plus tard.");
    }
}
