using System;
using System.Collections.Generic;
using System.Net.NetworkInformation;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record NetworkProbeReply(string Status, long? RoundtripMs, string Error = "");

public sealed class NetworkDiagnosticsService(Func<string, int, Task<NetworkProbeReply>>? probe = null)
{
    public const string Target = "1.1.1.1";
    public const int Attempts = 8;
    public const int TimeoutMs = 1000;

    public static async Task<NetworkProbeReply> SendAsync(string target, int timeoutMs)
    {
        using var ping = new Ping();
        var reply = await ping.SendPingAsync(target, timeoutMs);
        return new(reply.Status.ToString(), reply.Status == IPStatus.Success ? reply.RoundtripTime : null);
    }

    public async Task<NativeOperationReport> ExecuteAsync(IProgress<WorkerProgress> progress)
    {
        var replies = new List<object>();
        int errors = 0;
        for (int index = 1; index <= Attempts; index++)
        {
            progress.Report(new((index - 1) * 100 / Attempts, "Mesure réseau", $"Essai {index}/{Attempts} vers {Target}…"));
            NetworkProbeReply reply;
            try { reply = await (probe ?? SendAsync)(Target, TimeoutMs); }
            catch (Exception error) when (error is PingException or System.Net.Sockets.SocketException or UnauthorizedAccessException or InvalidOperationException)
            { errors++; reply = new("Error", null, error.ToString()); }
            replies.Add(new { Sequence = index, reply.Status, reply.RoundtripMs, reply.Error });
        }
        var data = new Dictionary<string, object?> { ["Target"] = Target, ["Attempts"] = Attempts, ["TimeoutMs"] = TimeoutMs, ["Replies"] = replies };
        return errors == Attempts
            ? new(false, "Windows n’a pas pu effectuer les mesures ICMP. Vérifie la connexion et les autorisations réseau puis réessaie.", data, "ICMP_UNAVAILABLE")
            : new(true, "Mesures ICMP terminées.", data);
    }
}
