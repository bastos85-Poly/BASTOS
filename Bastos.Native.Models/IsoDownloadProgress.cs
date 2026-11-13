namespace Bastos.Native.Models;

public sealed record IsoDownloadProgress(string Status, long Bytes, long TotalBytes, double Percent, double BytesPerSecond, string FilePath);
