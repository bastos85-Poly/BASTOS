using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public static class OfficialIsoTransfer
{
    public static bool IsMicrosoftUri(Uri uri)=>uri.IsAbsoluteUri && uri.Scheme==Uri.UriSchemeHttps && uri.IsDefaultPort &&
        uri.UserInfo.Length==0 && (uri.IdnHost.Equals("microsoft.com",StringComparison.OrdinalIgnoreCase) || uri.IdnHost.EndsWith(".microsoft.com",StringComparison.OrdinalIgnoreCase));

    public static string GetFileName(Uri uri)
    {
        if(!IsMicrosoftUri(uri))throw new InvalidDataException("Adresse ISO Microsoft refusée.");
        string name=Uri.UnescapeDataString(Path.GetFileName(uri.AbsolutePath));
        if(!name.EndsWith(".iso",StringComparison.OrdinalIgnoreCase) || name.Length>180 || name.IndexOfAny(Path.GetInvalidFileNameChars())>=0 || name.Contains('/') || name.Contains('\\'))
            throw new InvalidDataException("Nom de fichier ISO Microsoft invalide.");
        return name;
    }

    public static async Task<(string Path,string Sha256)> DownloadAsync(Uri source,string directory,IProgress<IsoDownloadProgress>? progress,CancellationToken cancellationToken,
        HttpMessageHandler? testHandler=null)
    {
        string name=GetFileName(source);
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(directory);
        string root=Path.GetFullPath(directory);
        for(string? cursor=root;cursor!=null;cursor=Path.GetDirectoryName(cursor))
            if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)throw new IOException("Dossier lié refusé pour le téléchargement ISO.");
        string temporary=Path.Combine(root,".BASTOS-"+Guid.NewGuid().ToString("N")+".download");
        using var handler=testHandler??new HttpClientHandler{AllowAutoRedirect=false,AutomaticDecompression=DecompressionMethods.None};
        using var client=new HttpClient(handler){Timeout=TimeSpan.FromSeconds(90)};
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0 BASTOS/7.120.140");
        HttpResponseMessage? response=null;
        try
        {
            Uri current=source;
            for(int redirects=0;redirects<=5;redirects++)
            {
                if(!IsMicrosoftUri(current))throw new InvalidDataException("Redirection hors Microsoft refusée.");
                response=await client.GetAsync(current,HttpCompletionOption.ResponseHeadersRead,cancellationToken).ConfigureAwait(false);
                if((int)response.StatusCode is >=300 and <400)
                {
                    Uri? location=response.Headers.Location;
                    response.Dispose();response=null;
                    if(location==null || redirects==5)throw new InvalidDataException("Redirection ISO Microsoft invalide.");
                    current=location.IsAbsoluteUri?location:new Uri(current,location);
                    continue;
                }
                response.EnsureSuccessStatusCode();break;
            }
            if(response==null)throw new HttpRequestException("Réponse ISO Microsoft absente.");
            if(response.StatusCode!=HttpStatusCode.OK || response.Content.Headers.ContentRange!=null)
                throw new InvalidDataException("Réponse ISO Microsoft partielle refusée.");
            string type=response.Content.Headers.ContentType?.MediaType??"";
            if(type.Contains("html",StringComparison.OrdinalIgnoreCase) || type.StartsWith("text/",StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Microsoft a renvoyé une page au lieu du fichier ISO.");
            long total=response.Content.Headers.ContentLength??0;
            if(total>0 && total<1024*1024)throw new InvalidDataException("Fichier ISO Microsoft anormalement petit.");
            string? volume=Path.GetPathRoot(root);
            if(total>0 && volume!=null && total>new DriveInfo(volume).AvailableFreeSpace-64L*1024*1024)
                throw new IOException("Espace insuffisant dans la bibliothèque ISO.");
            using var digest=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            byte[] prefix=new byte[32768+6];int prefixLength=0;
            long received=0,previous=0;var clock=Stopwatch.StartNew();TimeSpan last=TimeSpan.Zero;
            await using(var input=await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false))
            await using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None,1024*1024,FileOptions.Asynchronous))
            {
                byte[] buffer=new byte[1024*1024];
                int count;
                while((count=await input.ReadAsync(buffer.AsMemory(),cancellationToken).AsTask().WaitAsync(TimeSpan.FromSeconds(90),cancellationToken).ConfigureAwait(false))>0)
                {
                    await output.WriteAsync(buffer.AsMemory(0,count),cancellationToken).ConfigureAwait(false);
                    digest.AppendData(buffer,0,count);
                    if(prefixLength<prefix.Length){int take=Math.Min(count,prefix.Length-prefixLength);Buffer.BlockCopy(buffer,0,prefix,prefixLength,take);prefixLength+=take;}
                    received+=count;
                    if(clock.Elapsed-last>TimeSpan.FromMilliseconds(200))
                    {
                        double speed=(received-previous)/Math.Max(.001,(clock.Elapsed-last).TotalSeconds);
                        progress?.Report(new("Downloading",received,total,total>0?100.0*received/total:0,speed,Path.Combine(root,name)));
                        previous=received;last=clock.Elapsed;
                    }
                }
                await output.FlushAsync(cancellationToken).ConfigureAwait(false);
            }
            cancellationToken.ThrowIfCancellationRequested();
            if(received<1024*1024 || (total>0 && received!=total))throw new InvalidDataException("Téléchargement ISO incomplet ; fichier partiel supprimé.");
            string magic=Encoding.ASCII.GetString(prefix,32769,5);
            if(magic is not ("CD001" or "BEA01" or "NSR02" or "NSR03"))throw new InvalidDataException("Le fichier reçu n’est pas une image ISO/UDF reconnue.");
            string hash=Convert.ToHexString(digest.GetHashAndReset());
            string path=Path.Combine(root,name);
            for(int suffix=0;;suffix++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                string candidate=suffix==0?path:Path.Combine(root,Path.GetFileNameWithoutExtension(name)+" ("+suffix+").iso");
                try{File.Move(temporary,candidate,false);path=candidate;break;}
                catch(IOException) when(File.Exists(candidate)){ }
            }
            progress?.Report(new("Completed",received,total>0?total:received,100,0,path));
            return(path,hash);
        }
        catch(OperationCanceledException) when(!cancellationToken.IsCancellationRequested)
        {
            throw new IOException("La connexion Microsoft a expiré. Réessaie le téléchargement.");
        }
        catch(TimeoutException)
        {
            throw new IOException("La connexion Microsoft a expiré. Réessaie le téléchargement.");
        }
        finally
        {
            response?.Dispose();
            if(File.Exists(temporary))File.Delete(temporary);
        }
    }
}
