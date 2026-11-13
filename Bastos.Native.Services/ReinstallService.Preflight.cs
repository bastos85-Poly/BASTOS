using System;
using System.IO;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed partial class ReinstallService
{
    public async Task<RecoveryPreflight> ReviewRecoveryAsync(IsoChoice iso, RufusInstallOptions options, bool reinstall, OperationCancellation? cancellation = null)
    {
        cancellation?.ThrowIfRequested();
        cancellation?.AllowRead();
        RecoveryDiskPreview disk;
        try { disk = await PreviewRecoveryAsync(options, iso.Path); }
        catch (Exception ex) { disk = new(false, ex.Message, "", "", "", ""); }
        cancellation?.ThrowIfRequested();
        WindowsIsoEditionCatalog? catalog = null;
        long length = 0;
        string error = "";
        try
        {
            length = new FileInfo(iso.Path).Length;
            catalog = await ReadIsoEditionsAsync(iso);
        }
        catch (Exception ex) { error = ex.Message; }
        cancellation?.ThrowIfRequested();
        return RecoveryPreflightBuilder.Build(iso.Path, length, options, disk, catalog, error, reinstall);
    }
}
