using System;
using System.Runtime.InteropServices;

namespace Bastos.Native.Services;

internal static class PhysicalMemoryService
{
	public static int TotalKilobytes
	{
		get
		{
			MemoryStatus status = new() { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
			if (!GlobalMemoryStatusEx(ref status)) throw new InvalidOperationException("La quantité de mémoire physique n’a pas pu être lue.");
			return checked((int)(status.TotalPhysical / 1024));
		}
	}

	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

	[StructLayout(LayoutKind.Sequential)]
	private struct MemoryStatus
	{
		public uint Length;
		public uint MemoryLoad;
		public ulong TotalPhysical;
		public ulong AvailablePhysical;
		public ulong TotalPageFile;
		public ulong AvailablePageFile;
		public ulong TotalVirtual;
		public ulong AvailableVirtual;
		public ulong AvailableExtendedVirtual;
	}
}
