using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;
namespace Bastos.Native.Services;
public sealed partial class ReinstallService
{
    public IReadOnlyList<OperationCheck> ObserveResumeFiles(OperationResumeIntent intent)
    {
        var checks=new List<OperationCheck>();
        void Observe(string name,string file){SafeLocalFile(file);checks.Add(new(name,File.Exists(file),"Présence uniquement ; aucun contenu validé par cette observation."));}
        if(intent.Kind=="RecoveryPreparation")
        {
            Observe("Média de démarrage",@"D:\sources\boot.wim");Observe("État du média",@"D:\BASTOS-MEDIA-STATE.json");Observe("Application Recovery",@"D:\Application\VERSION.txt");
        }
        else if(intent.Kind=="RufusDownload")Observe("Fichier Rufus",Path.Combine(paths.DataRoot,"Tools","Rufus","rufus.exe"));
        else if(intent.Kind=="IsoBuild")
        {
            var expected=JsonSerializer.Deserialize<IsoBuildExpectation>(intent.ExpectedJson)??throw new JsonException();
            string library=Directory.Exists(@"D:\")?@"D:\ISO":Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Downloads","BASTOS-ISO");
            if(!SameFile(Path.GetDirectoryName(expected.Output)!,library)||Path.GetExtension(expected.Output)!=".iso")throw new IOException("Cible ISO inconnue.");
            Observe("ISO de sortie",expected.Output);
        }
        return checks;
    }
    public async Task<OperationVerification> VerifyResumeAsync(OperationResumeIntent intent,JsonElement report)
    {
        switch(intent.Kind)
        {
            case "RufusDownload":return await OperationVerifiers.RufusAsync(Path.Combine(paths.DataRoot,"Tools","Rufus","rufus.exe"),report);
            case "WebView2":return await OperationVerifiers.WebView2Async(Path.Combine(paths.DataRoot,"Tools","WebView2"),ReadWebView2Version,report);
            case "Adk":return await DeploymentOperationVerifiers.AdkAsync(report,AdkInstallationService.ReadVersion,AdkInstallationService.ReadPatchState,
                AdkInstallationService.OscdimgCandidates(),Path.Combine(paths.DataRoot,"Prerequisites","WindowsADK","Windows_ADK_10.1.26100.2454_Update_KB5101684.zip"));
            case "IsoBuild":
            {
                var expected=JsonSerializer.Deserialize<IsoBuildExpectation>(intent.ExpectedJson)??throw new JsonException();
                SafeLocalFile(expected.Source);SafeLocalFile(expected.Output);
                string library=Directory.Exists(@"D:\")?@"D:\ISO":Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Downloads","BASTOS-ISO");
                if(!Path.GetExtension(expected.Source).Equals(".iso",StringComparison.OrdinalIgnoreCase)||!SameFile(expected.Source,intent.SourceIso)||!SameFile(Path.GetDirectoryName(expected.Output)!,library)||
                    !Path.GetFileName(expected.Output).StartsWith("BASTOS-Windows11_",StringComparison.Ordinal)||Path.GetExtension(expected.Output)!=".iso")
                    throw new IOException("Cible ISO enregistrée non reconnue.");
                return await DeploymentOperationVerifiers.IsoAsync(expected,report);
            }
            case "RecoveryPreparation":
            {
                var expected=JsonSerializer.Deserialize<RecoveryExpectation>(intent.ExpectedJson)??throw new JsonException();
                SafeLocalFile(expected.SourceIso);SafeLocalFile(intent.OptionsFile);
                string name=Path.GetFileNameWithoutExtension(intent.OptionsFile);
                if(!Path.GetExtension(expected.SourceIso).Equals(".iso",StringComparison.OrdinalIgnoreCase)||!SameFile(expected.SourceIso,intent.SourceIso)||!SameFile(expected.Root??"",@"D:\")||expected.Mode!="WindowsOnly"||
                    !SameFile(Path.GetDirectoryName(intent.OptionsFile)!,paths.LogRoot)||!name.StartsWith("Recovery-Options-",StringComparison.Ordinal)||
                    Path.GetExtension(intent.OptionsFile)!=".json"||!Guid.TryParseExact(name["Recovery-Options-".Length..],"N",out _))throw new IOException("Profil de reprise non reconnu.");
                await using var options=File.OpenRead(intent.OptionsFile);
                if(Convert.ToHexString(await SHA256.HashDataAsync(options))!=intent.OptionsSha256)throw new IOException("Le profil enregistré a changé depuis cette tentative.");
                return await VerifyRecoveryAsync(expected,report,intent.OptionsFile,false,resuming:true);
            }
            default:throw new InvalidOperationException("Type de contrôle de reprise non autorisé.");
        }
    }
    private static bool SameFile(string a,string b)=>string.Equals(Path.GetFullPath(a).TrimEnd(Path.DirectorySeparatorChar),Path.GetFullPath(b).TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase);
    private static void SafeLocalFile(string file)
    {
        if(!Path.IsPathFullyQualified(file)||file.StartsWith(@"\\",StringComparison.Ordinal))throw new IOException("Chemin local absolu requis.");
        for(FileSystemInfo? info=new FileInfo(file);info!=null;info=info is FileInfo f?f.Directory:((DirectoryInfo)info).Parent)
            if(info.Exists&&(info.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Chemin de reprise redirigé.");
    }
}
