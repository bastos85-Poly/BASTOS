Set-StrictMode -Version Latest

if(-not('BastosHagsNativeState' -as [type])){
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class BastosHagsNativeState {
    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public UInt32 LowPart; public Int32 HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct OpenAdapterFromHdc {
        public IntPtr hDc;
        public UInt32 hAdapter;
        public Luid AdapterLuid;
        public UInt32 VidPnSourceId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct QueryAdapterInfo {
        public UInt32 hAdapter;
        public UInt32 Type;
        public IntPtr pPrivateDriverData;
        public UInt32 PrivateDriverDataSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct CloseAdapter { public UInt32 hAdapter; }

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]
    private static extern Int32 ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")]
    private static extern Int32 D3DKMTOpenAdapterFromHdc(ref OpenAdapterFromHdc data);
    [DllImport("gdi32.dll")]
    private static extern Int32 D3DKMTQueryAdapterInfo(ref QueryAdapterInfo data);
    [DllImport("gdi32.dll")]
    private static extern Int32 D3DKMTCloseAdapter(ref CloseAdapter data);

    // Bits from D3DKMT_WDDM_2_7_CAPS. Returns -1 when the runtime query fails.
    public static Int32 QueryPrimaryAdapterCaps() {
        const UInt32 KMTQAITYPE_WDDM_2_7_CAPS = 70;
        IntPtr dc = GetDC(IntPtr.Zero);
        if (dc == IntPtr.Zero) return -1;
        OpenAdapterFromHdc open = new OpenAdapterFromHdc();
        open.hDc = dc;
        try {
            if (D3DKMTOpenAdapterFromHdc(ref open) != 0) return -1;
            IntPtr buffer = Marshal.AllocHGlobal(sizeof(UInt32));
            try {
                Marshal.WriteInt32(buffer, 0);
                QueryAdapterInfo query = new QueryAdapterInfo();
                query.hAdapter = open.hAdapter;
                query.Type = KMTQAITYPE_WDDM_2_7_CAPS;
                query.pPrivateDriverData = buffer;
                query.PrivateDriverDataSize = sizeof(UInt32);
                if (D3DKMTQueryAdapterInfo(ref query) != 0) return -1;
                return Marshal.ReadInt32(buffer);
            } finally {
                Marshal.FreeHGlobal(buffer);
                CloseAdapter close = new CloseAdapter();
                close.hAdapter = open.hAdapter;
                D3DKMTCloseAdapter(ref close);
            }
        } finally { ReleaseDC(IntPtr.Zero, dc); }
    }
}
'@
}

function Get-BastosHagsState {
    $registryPath='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    $registryValue=$null
    try{$registryValue=Get-ItemPropertyValue -LiteralPath $registryPath -Name 'HwSchMode' -ErrorAction Stop}catch{}
    try{$caps=[int][BastosHagsNativeState]::QueryPrimaryAdapterCaps()}catch{$caps=-1}

    $runtimeAvailable=$caps -ge 0
    $supported=$runtimeAvailable -and (($caps -band 1) -ne 0)
    $runtimeEnabled=$supported -and (($caps -band 2) -ne 0)
    $driverDefault=$supported -and (($caps -band 4) -ne 0)
    $configured=$null
    if($registryValue -eq 1){$configured=$false}elseif($registryValue -eq 2){$configured=$true}
    $effective=if($runtimeAvailable){[bool]$runtimeEnabled}elseif($null -ne $configured){[bool]$configured}else{$null}
    $displayEnabled=if($null -ne $configured){[bool]$configured}elseif($null -ne $effective){[bool]$effective}else{$false}
    $pending=$runtimeAvailable -and $null -ne $configured -and [bool]$configured -ne [bool]$runtimeEnabled

    if($runtimeAvailable -and -not $supported){
        $text='NON PRIS EN CHARGE par le GPU ou son pilote'
    }elseif($pending -and [bool]$configured){
        $text='DESACTIVE actuellement - ACTIVATION configuree, redemarrage requis'
    }elseif($pending){
        $text='ACTIF actuellement - DESACTIVATION configuree, redemarrage requis'
    }elseif($null -ne $effective -and [bool]$effective){
        $text=if($registryValue -eq 2){'ACTIF - activation explicite Windows'}else{'ACTIF - reglage Windows/pilote'}
    }elseif($null -ne $effective){
        $text=if($registryValue -eq 1){'DESACTIVE - desactivation explicite Windows'}else{'DESACTIVE - reglage Windows/pilote'}
    }else{
        $text='ETAT INDISPONIBLE - verification dans Parametres Windows necessaire'
    }

    return [pscustomobject]@{
        Available=$runtimeAvailable
        Supported=$supported
        Enabled=$effective
        DisplayEnabled=$displayEnabled
        RuntimeEnabled=if($runtimeAvailable){[bool]$runtimeEnabled}else{$null}
        DriverDefaultEnabled=if($runtimeAvailable){[bool]$driverDefault}else{$null}
        RegistryValue=$registryValue
        PendingRestart=$pending
        Text=$text
        Caps=$caps
    }
}
