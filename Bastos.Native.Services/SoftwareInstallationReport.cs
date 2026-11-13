using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace Bastos.Native.Services;

public sealed record SoftwareInstallationSummary(bool Success, string Message, string Detail);

public static class SoftwareInstallationReport
{
    public static SoftwareInstallationSummary Read(byte[] json, IReadOnlyCollection<string> expectedIds, bool processSucceeded, string? expectedUserSid = null)
    {
        string detail=Encoding.UTF8.GetString(json);
        try
        {
            if(expectedIds.Count==0)return new(false,"Aucun logiciel demandé.",detail);
            using var document=JsonDocument.Parse(json);
            var root=document.RootElement;
            if(expectedUserSid != null && root.GetProperty("UserSid").GetString()!=expectedUserSid)return new(false,"Le rapport ne correspond pas au compte Windows actif.",detail);
            if(root.TryGetProperty("Error",out var error))return new(false,"Installation interrompue : "+error.GetString(),detail);
            var items=root.GetProperty("Items").EnumerateArray().ToArray();
            if(root.GetProperty("Schema").GetInt32()!=2 || root.GetProperty("Requested").GetInt32()!=expectedIds.Count || items.Length!=expectedIds.Count ||
                items.Select(i=>i.GetProperty("Id").GetString()!).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=items.Length ||
                !items.Select(i=>i.GetProperty("Id").GetString()!).OrderBy(i=>i,StringComparer.OrdinalIgnoreCase).SequenceEqual(expectedIds.OrderBy(i=>i,StringComparer.OrdinalIgnoreCase),StringComparer.OrdinalIgnoreCase))
                return new(false,"Le rapport ne correspond pas aux logiciels demandés. Consulte les détails avant de relancer.",detail);
            bool verified=items.All(i=>i.GetProperty("Success").GetBoolean() && i.GetProperty("Verified").GetBoolean() && i.GetProperty("Status").GetString() is "Installed" or "AlreadyPresent");
            if(processSucceeded && root.GetProperty("Success").GetBoolean() && verified)
            {
                bool restart=items.Any(i=>i.TryGetProperty("RestartRequired",out var value)&&value.GetBoolean());
                return new(true,$"{items.Length} logiciel(s) installé(s) ou déjà présent(s), présence vérifiée."+(restart?" Un redémarrage est demandé.":""),detail);
            }
            var failures=items.Where(i=>!i.GetProperty("Success").GetBoolean() || !i.GetProperty("Verified").GetBoolean()).Select(i=>
            {
                string name=i.GetProperty("Name").GetString()??i.GetProperty("Id").GetString()!;
                string code=i.TryGetProperty("ErrorCode",out var e)?e.GetString()??"":"";
                string explanation=code switch {
                    "ADMIN_CANCELLED"=>"autorisation administrateur annulée. Relance Installer et accepte la demande Windows.",
                    "ADMIN_START_FAILED"=>"demande administrateur impossible. Consulte les détails.",
                    "INSTALLATION_UNCONFIRMED"=>"l’installateur peut encore travailler. Vérifie son état avant de relancer.",
                    _=>i.TryGetProperty("ExitCode",out var exit)?$"installation non confirmée (code {exit}). Ouvre les détails pour lire le journal.":"installation non confirmée. Consulte les détails."
                };
                return name+" : "+explanation;
            }).ToArray();
            return new(false,failures.Length>0?string.Join(" | ",failures):"Le processus et le rapport ne confirment pas la même réussite. Consulte les détails.",detail);
        }
        catch(Exception ex) when(ex is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        {return new(false,"Rapport d’installation illisible ou incomplet. Consulte les détails avant de relancer.",detail+Environment.NewLine+ex.Message);}
    }
}
