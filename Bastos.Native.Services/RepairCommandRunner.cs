using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed record RepairProgress(string Message, double? Percent);

public static class RepairCommandRunner
{
    private static readonly Regex Percentage = new(@"(?<![\d.])(?<n>\d{1,3}(?:[.,]\d+)?)\s*%", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static async Task<NativeActionResult> RunAsync(string executable, string[] arguments, bool unicodeOutput, string? progressPath)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var encoding = unicodeOutput ? Encoding.Unicode : Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = encoding, StandardErrorEncoding = encoding };
        foreach (var arg in arguments) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("La commande Windows n’a pas démarré.");
        Publish(progressPath, new RepairProgress("Commande Windows démarrée…", null));
        var stdout = ReadOutputAsync(process.StandardOutput, progressPath);
        var stderr = ReadOutputAsync(process.StandardError, null);
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(110));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException) { return new(false, "Délai dépassé : la commande Windows peut encore être en cours. Vérifie avant de la relancer.", -2); }
        var output = (await stdout + "\n" + await stderr).Trim();
        var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Replace("\0", "").Trim()).Where(s => s.Length > 0 && !Percentage.IsMatch(s)).ToArray();
        var summary = lines.Length > 0 ? string.Join(" ", lines.TakeLast(4)) : (process.ExitCode == 0 ? "Commande terminée." : "La commande a échoué.");
        if (summary.Length > 4000) summary = summary[^4000..];
        return new NativeActionResult(process.ExitCode == 0, summary, process.ExitCode);
    }

    private static async Task<string> ReadOutputAsync(StreamReader reader, string? progressPath)
    {
        var buffer = new char[512];
        var tail = new StringBuilder();
        var progressBuffer = "";
        var lastReported = "";
        int count;
        while ((count = await reader.ReadAsync(buffer, 0, buffer.Length)) > 0)
        {
            var chunk = new string(buffer, 0, count).Replace("\0", "");
            tail.Append(chunk);
            if (tail.Length > 32000) tail.Remove(0, tail.Length - 32000);
            if (progressPath == null) continue;
            progressBuffer += chunk;
            if (progressBuffer.Length > 2048) progressBuffer = progressBuffer[^2048..];
            var matches = Percentage.Matches(progressBuffer);
            if (matches.Count > 0)
            {
                var number = matches[^1].Groups["n"].Value.Replace(',', '.');
                if (number != lastReported && double.TryParse(number, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var percent) && percent is >= 0 and <= 100)
                {
                    lastReported = number;
                    Publish(progressPath, new RepairProgress($"En cours : {number} % (étape indiquée par Windows).", percent));
                }
            }
        }
        return tail.ToString();
    }

    private static void Publish(string? path, RepairProgress progress)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(progress), new UTF8Encoding(false));
            File.Move(temporary, path, true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
