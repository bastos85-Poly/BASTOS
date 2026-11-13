namespace Bastos.Native.Services;

public sealed record NetworkSample(double Percent, double DownloadBytesPerSecond, double UploadBytesPerSecond, string AdapterName);
