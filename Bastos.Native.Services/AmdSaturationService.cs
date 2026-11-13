using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace Bastos.Native.Services;

// AMD ADL2 interface adapted from EXFIL (MIT, copyright 2026 Blazzer).
// Only mapped, connected displays with a successful saturation query are used.
internal sealed class AmdSaturationService : IDisposable
{
    private const int Saturation = 1 << 2;
    private const int ConnectedAndMapped = 0x3;
    private readonly IntPtr library;
    private readonly IntPtr context;
    private readonly AdlAlloc alloc;
    private readonly AdlDestroy destroy;
    private readonly AdlAdapterCount adapterCount;
    private readonly AdlAdapterActive adapterActive;
    private readonly AdlDisplayInfoGet displayInfoGet;
    private readonly AdlColorCapsGet colorCapsGet;
    private readonly AdlColorGet colorGet;
    private readonly AdlColorSet colorSet;
    private readonly Dictionary<IntPtr, int> allocations = new();
    private readonly object allocationLock = new();
    private readonly Dictionary<(int Adapter, int Display), int> originalLevels = new();
    private bool disposed;

    private AmdSaturationService(IntPtr library)
    {
        this.library = library;
        alloc = Allocate;
        destroy = Load<AdlDestroy>("ADL2_Main_Control_Destroy");
        adapterCount = Load<AdlAdapterCount>("ADL2_Adapter_NumberOfAdapters_Get");
        adapterActive = Load<AdlAdapterActive>("ADL2_Adapter_Active_Get");
        displayInfoGet = Load<AdlDisplayInfoGet>("ADL2_Display_DisplayInfo_Get");
        colorCapsGet = Load<AdlColorCapsGet>("ADL2_Display_ColorCaps_Get");
        colorGet = Load<AdlColorGet>("ADL2_Display_Color_Get");
        colorSet = Load<AdlColorSet>("ADL2_Display_Color_Set");
        var create = Load<AdlCreate>("ADL2_Main_Control_Create");
        if (create(alloc, 1, out context) != 0 || context == IntPtr.Zero)
            throw new InvalidOperationException("Initialisation AMD ADL2 impossible.");
    }

    public static AmdSaturationService? TryOpen()
    {
        var dll = Path.Combine(Environment.SystemDirectory, "atiadlxx.dll");
        if (!File.Exists(dll) || !NativeLibrary.TryLoad(dll, out var library)) return null;
        AmdSaturationService? service = null;
        try
        {
            service = new AmdSaturationService(library);
            if (service.Displays().Count > 0) return service;
            service.Dispose();
            return null;
        }
        catch
        {
            if (service != null) service.Dispose();
            else NativeLibrary.Free(library);
            return null;
        }
    }

    public (int Current, int Minimum, int Maximum, int Default)? ReadPrimary()
    {
        var displays = Displays();
        if (displays.Count == 0) return null;
        return Read(displays[0].Adapter, displays[0].Display);
    }

    public void SetAll(int value)
    {
        var displays = Displays();
        if (displays.Count == 0) throw new InvalidOperationException("Aucun écran AMD ne prend en charge la vibrance.");
        foreach (var (adapter, display) in displays)
        {
            var info = Read(adapter, display);
            var key = (adapter, display);
            if (!originalLevels.ContainsKey(key)) originalLevels[key] = info.Current;
            var level = Math.Clamp(value, info.Minimum, info.Maximum);
            if (colorSet(context, adapter, display, Saturation, level) != 0)
                throw new InvalidOperationException($"Le pilote AMD refuse la vibrance sur l'écran {display}.");
        }
    }

    public void RestoreOriginal()
    {
        foreach (var (key, level) in originalLevels)
            colorSet(context, key.Adapter, key.Display, Saturation, level);
    }

    private (int Current, int Minimum, int Maximum, int Default) Read(int adapter, int display)
    {
        if (colorGet(context, adapter, display, Saturation, out var current, out var normal,
                out var minimum, out var maximum, out _) != 0 || minimum > maximum)
            throw new InvalidOperationException("Lecture de la vibrance AMD impossible.");
        return (current, minimum, maximum, normal);
    }

    private List<(int Adapter, int Display)> Displays()
    {
        var result = new List<(int, int)>();
        if (adapterCount(context, out var count) != 0 || count < 0 || count > 64) return result;
        var structureSize = Marshal.SizeOf<AdlDisplayInfo>();
        for (var adapter = 0; adapter < count; adapter++)
        {
            if (adapterActive(context, adapter, out var active) != 0 || active == 0) continue;
            if (displayInfoGet(context, adapter, out var reported, out var pointer, 0) != 0 || pointer == IntPtr.Zero) continue;
            try
            {
                int allocated;
                lock (allocationLock) { if (!allocations.TryGetValue(pointer, out allocated)) continue; }
                var safeCount = Math.Min(Math.Max(0, reported), allocated / structureSize);
                for (var i = 0; i < safeCount; i++)
                {
                    var item = Marshal.PtrToStructure<AdlDisplayInfo>(IntPtr.Add(pointer, i * structureSize));
                    if ((item.InfoValue & ConnectedAndMapped) != ConnectedAndMapped ||
                        item.Id.LogicalAdapterIndex != adapter) continue;
                    var display = item.Id.LogicalIndex;
                    if (result.Contains((adapter, display))) continue;
                    if (colorCapsGet(context, adapter, display, out var caps, out var valid) == 0 &&
                        (caps & valid & Saturation) == 0) continue;
                    try { Read(adapter, display); result.Add((adapter, display)); }
                    catch { }
                }
            }
            finally { FreeAllocation(pointer); }
        }
        return result;
    }

    private IntPtr Allocate(int bytes)
    {
        if (bytes <= 0 || bytes > 8 * 1024 * 1024) return IntPtr.Zero;
        var pointer = Marshal.AllocHGlobal(bytes);
        lock (allocationLock) allocations[pointer] = bytes;
        return pointer;
    }

    private void FreeAllocation(IntPtr pointer)
    {
        lock (allocationLock)
        {
            if (allocations.Remove(pointer)) Marshal.FreeHGlobal(pointer);
        }
    }

    private T Load<T>(string name) where T : Delegate
        => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (context != IntPtr.Zero) destroy(context);
        List<IntPtr> remaining;
        lock (allocationLock) remaining = new List<IntPtr>(allocations.Keys);
        foreach (var pointer in remaining) FreeAllocation(pointer);
        NativeLibrary.Free(library);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AdlDisplayId
    {
        public int LogicalIndex;
        public int PhysicalIndex;
        public int LogicalAdapterIndex;
        public int PhysicalAdapterIndex;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AdlDisplayInfo
    {
        public AdlDisplayId Id;
        public int ControllerIndex;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public byte[] DisplayName;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public byte[] ManufacturerName;
        public int DisplayType;
        public int OutputType;
        public int Connector;
        public int InfoMask;
        public int InfoValue;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate IntPtr AdlAlloc(int bytes);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlCreate(AdlAlloc callback, int enumConnectedAdapters, out IntPtr context);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlDestroy(IntPtr context);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlAdapterCount(IntPtr context, out int count);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlAdapterActive(IntPtr context, int adapter, out int active);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlDisplayInfoGet(IntPtr context, int adapter, out int count, out IntPtr info, int forceDetect);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlColorCapsGet(IntPtr context, int adapter, int display, out int caps, out int valid);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlColorGet(IntPtr context, int adapter, int display, int type,
        out int current, out int normal, out int minimum, out int maximum, out int step);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int AdlColorSet(IntPtr context, int adapter, int display, int type, int value);
}
