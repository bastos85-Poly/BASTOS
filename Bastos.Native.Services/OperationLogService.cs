using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Security.Cryptography;
using System.Threading;
using System.Globalization;

namespace Bastos.Native.Services;

public sealed class OperationLogService(AppPaths paths)
{
	private readonly object gate = new object();

	public void Write(string area, string message, bool error = false)
	{
		Directory.CreateDirectory(paths.LogRoot);
		string value = message.Replace('\r', ' ').Replace('\n', ' ').Trim();
		string contents = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\t{(error ? "ERROR" : "INFO")}\t{area}\t{value}{Environment.NewLine}";
		lock (gate)
		{
            using var mutex = new Mutex(false, "Local\\Bastos.Log." + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(paths.NativeLog).ToUpperInvariant()))));
            bool acquired = false;
            try
            {
                try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(3)); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new IOException("Le journal Bastos est occupé. Réessaie dans quelques instants.");
                if (PlainLocalPath(paths.NativeLog) && File.Exists(paths.NativeLog) && new FileInfo(paths.NativeLog).Length >= 5 * 1024 * 1024)
                {
                    string archive = Path.Combine(paths.LogRoot, "BASTOS-Native-Archive-" + DateTime.UtcNow.ToString("yyyyMMdd'T'HHmmssfff", CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N") + ".log");
                    // Rotation preserves the complete old log. If a reader holds it,
                    // defer rotation; never truncate the active file.
                    try { File.Move(paths.NativeLog, archive, false); }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
                }
                File.AppendAllText(paths.NativeLog, contents, new UTF8Encoding(false));
            }
            finally { if (acquired) mutex.ReleaseMutex(); }
		}
	}
    private static bool PlainLocalPath(string path)
    {
        try {
            if (Path.GetFullPath(path).StartsWith(@"\\", StringComparison.Ordinal)) return false;
            for (string? cursor = Path.GetFullPath(path); cursor != null; cursor = Path.GetDirectoryName(cursor))
                if ((File.Exists(cursor) || Directory.Exists(cursor)) && (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0) return false;
            return true;
        } catch { return false; }
    }

	public string ReadLatest(int maximumLines = 80)
	{
		if (!File.Exists(paths.NativeLog))
		{
			return "Aucune opération native enregistrée.";
		}
        try {
            using var input = new FileStream(paths.NativeLog, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(input);
            var lines = new System.Collections.Generic.Queue<string>();
            while (reader.ReadLine() is { } line) { lines.Enqueue(line); if (lines.Count > Math.Clamp(maximumLines, 1, 1000)) lines.Dequeue(); }
            return string.Join(Environment.NewLine, lines);
        } catch (IOException) { return "Le journal est occupé ou vient d’être archivé. Actualise pour lire les dernières lignes."; }
	}
}
