using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class SystemPerformanceService : IDisposable
{
	private struct FileTime
	{
		public uint Low;

		public uint High;

		public readonly ulong Value => ((ulong)High << 32) | Low;
	}

	[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
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

	[StructLayout(LayoutKind.Explicit)]
	private struct PdhValue
	{
		[FieldOffset(0)]
		public uint Status;

		[FieldOffset(8)]
		public double DoubleValue;
	}

	private const uint PdhFormatDouble = 512u;

	private ulong previousIdle;

	private ulong previousKernel;

	private ulong previousUser;

	private long previousReceived;

	private long previousSent;

	private DateTime previousNetworkAt = DateTime.UtcNow;

	private bool hasCpuBaseline;

	private bool hasNetworkBaseline;

	private nint diskQuery;

	private nint diskUsageCounter;

	private nint diskReadCounter;

	private nint diskWriteCounter;

	private bool diskCountersAvailable;

	private readonly List<nint> gpuCounters = new List<nint>();
	private readonly string cpuName = ReadCpuName();

	public SystemPerformanceService()
	{
		InitializeDiskCounters();
		InitializeGpuCounters();
	}

	public PerformanceSnapshot Read()
	{
		if (diskQuery != IntPtr.Zero)
		{
			PdhCollectQueryData(diskQuery);
		}
		double cpuPercent = ReadCpu();
		(double Percent, ulong Used, ulong Total) tuple = ReadMemory();
		return new PerformanceSnapshot(MemoryPercent: tuple.Percent, MemoryUsed: tuple.Used, MemoryTotal: tuple.Total, Network: ReadNetwork(), Disk: ReadDisk(), Gpu: ReadGpu(), CpuPercent: cpuPercent, CpuName: cpuName, LogicalProcessors: Environment.ProcessorCount, CapturedAt: DateTime.Now);
	}

	private double ReadCpu()
	{
		if (!GetSystemTimes(out var idleTime, out var kernelTime, out var userTime))
		{
			return 0.0;
		}
		ulong value = idleTime.Value;
		ulong value2 = kernelTime.Value;
		ulong value3 = userTime.Value;
		if (!hasCpuBaseline)
		{
			previousIdle = value;
			previousKernel = value2;
			previousUser = value3;
			hasCpuBaseline = true;
			return 0.0;
		}
		ulong val = value - previousIdle;
		ulong num = value2 - previousKernel;
		ulong num2 = value3 - previousUser;
		previousIdle = value;
		previousKernel = value2;
		previousUser = value3;
		ulong num3 = num + num2;
		if (num3 != 0L)
		{
			return Math.Clamp((double)(num3 - Math.Min(num3, val)) * 100.0 / (double)num3, 0.0, 100.0);
		}
		return 0.0;
	}

	private static (double Percent, ulong Used, ulong Total) ReadMemory()
	{
		MemoryStatus buffer = new MemoryStatus
		{
			Length = (uint)Marshal.SizeOf<MemoryStatus>()
		};
		if (!GlobalMemoryStatusEx(ref buffer) || buffer.TotalPhysical == 0L)
		{
			return (Percent: 0.0, Used: 0uL, Total: 0uL);
		}
		ulong num = buffer.TotalPhysical - buffer.AvailablePhysical;
		return (Percent: (double)num * 100.0 / (double)buffer.TotalPhysical, Used: num, Total: buffer.TotalPhysical);
	}

	private NetworkSample ReadNetwork()
	{
		try
		{
			NetworkInterface[] array = NetworkInterface.GetAllNetworkInterfaces().Where(delegate(NetworkInterface adapter)
			{
				if (adapter.OperationalStatus == OperationalStatus.Up)
				{
					NetworkInterfaceType networkInterfaceType = adapter.NetworkInterfaceType;
					if (networkInterfaceType != NetworkInterfaceType.Loopback)
					{
						return networkInterfaceType != NetworkInterfaceType.Tunnel;
					}
					return false;
				}
				return false;
			}).ToArray();
			NetworkInterface[] array2 = array.Where(HasGateway).ToArray();
			NetworkInterface[] array3 = ((array2.Length != 0) ? array2 : array);
			long num = 0L;
			long num2 = 0L;
			long num3 = 0L;
			NetworkInterface[] array4 = array3;
			foreach (NetworkInterface networkInterface in array4)
			{
				IPv4InterfaceStatistics iPv4Statistics = networkInterface.GetIPv4Statistics();
				num += iPv4Statistics.BytesReceived;
				num2 += iPv4Statistics.BytesSent;
				if (networkInterface.Speed > 0)
				{
					num3 += networkInterface.Speed;
				}
			}
			DateTime utcNow = DateTime.UtcNow;
			double num5 = Math.Max(0.1, (utcNow - previousNetworkAt).TotalSeconds);
			double num6 = (hasNetworkBaseline ? ((double)Math.Max(0L, num - previousReceived) / num5) : 0.0);
			double num7 = (hasNetworkBaseline ? ((double)Math.Max(0L, num2 - previousSent) / num5) : 0.0);
			previousReceived = num;
			previousSent = num2;
			previousNetworkAt = utcNow;
			hasNetworkBaseline = true;
			double percent = ((num3 <= 0) ? 0.0 : Math.Clamp((num6 + num7) * 8.0 * 100.0 / (double)num3, 0.0, 100.0));
			double downloadBytesPerSecond = num6;
			double uploadBytesPerSecond = num7;
			return new NetworkSample(percent, downloadBytesPerSecond, uploadBytesPerSecond, array3.Length switch
			{
				0 => "Aucune interface active", 
				1 => array3[0].Name, 
				_ => $"{array3.Length} interfaces actives", 
			});
		}
		catch
		{
			return new NetworkSample(0.0, 0.0, 0.0, "Compteur réseau indisponible");
		}
	}

	private static bool HasGateway(NetworkInterface adapter)
	{
		try
		{
			return adapter.GetIPProperties().GatewayAddresses.Any((GatewayIPAddressInformation item) => !item.Address.Equals(IPAddress.Any) && !item.Address.Equals(IPAddress.IPv6Any));
		}
		catch
		{
			return false;
		}
	}

	private DiskSample ReadDisk()
	{
		DriveInfo driveInfo = null;
		try
		{
			driveInfo = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
		}
		catch
		{
		}
		long num = 0L;
		long num2 = 0L;
		if (driveInfo != null && driveInfo.IsReady)
		{
			num = driveInfo.TotalSize;
			num2 = driveInfo.AvailableFreeSpace;
		}
		double percent = ((num <= 0) ? 0.0 : ((double)(num - num2) * 100.0 / (double)num));
		if (!diskCountersAvailable)
		{
			return new DiskSample(percent, 0.0, 0.0, num, num2, IsActivity: false);
		}
		bool num3 = TryReadPdh(diskUsageCounter, out var value);
		bool flag = TryReadPdh(diskReadCounter, out var value2);
		bool flag2 = TryReadPdh(diskWriteCounter, out var value3);
		if (!num3)
		{
			return new DiskSample(percent, 0.0, 0.0, num, num2, IsActivity: false);
		}
		return new DiskSample(Math.Clamp(value, 0.0, 100.0), flag ? Math.Max(0.0, value2) : 0.0, flag2 ? Math.Max(0.0, value3) : 0.0, num, num2, IsActivity: true);
	}

	private GpuSample ReadGpu()
	{
		double num = 0.0;
		bool isAvailable = false;
		foreach (nint gpuCounter in gpuCounters)
		{
			if (TryReadPdh(gpuCounter, out var value))
			{
				num = Math.Max(num, value);
				isAvailable = true;
			}
		}
		return new GpuSample(Math.Clamp(num, 0.0, 100.0), ReadGpuName(), isAvailable);
	}

	private void InitializeDiskCounters()
	{
		try
		{
			if (PdhOpenQueryW(null, IntPtr.Zero, out diskQuery) == 0 && PdhAddEnglishCounterW(diskQuery, "\\PhysicalDisk(_Total)\\% Disk Time", IntPtr.Zero, out diskUsageCounter) == 0 && PdhAddEnglishCounterW(diskQuery, "\\PhysicalDisk(_Total)\\Disk Read Bytes/sec", IntPtr.Zero, out diskReadCounter) == 0 && PdhAddEnglishCounterW(diskQuery, "\\PhysicalDisk(_Total)\\Disk Write Bytes/sec", IntPtr.Zero, out diskWriteCounter) == 0)
			{
				diskCountersAvailable = PdhCollectQueryData(diskQuery) == 0;
			}
		}
		catch
		{
			diskCountersAvailable = false;
		}
	}

	private void InitializeGpuCounters()
	{
		try
		{
			if (diskQuery == IntPtr.Zero && PdhOpenQueryW(null, IntPtr.Zero, out diskQuery) != 0)
			{
				return;
			}
			uint pathListLength = 0u;
			uint num = PdhExpandWildCardPathW(null, "\\GPU Engine(*)\\Utilization Percentage", null, ref pathListLength, 0u);
			if (pathListLength == 0 || (num != 0 && num != 2147485650u))
			{
				return;
			}
			char[] array = new char[pathListLength];
			if (PdhExpandWildCardPathW(null, "\\GPU Engine(*)\\Utilization Percentage", array, ref pathListLength, 0u) != 0)
			{
				return;
			}
			string[] array2 = new string(array).Split('\0', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
			foreach (string fullCounterPath in array2)
			{
				if (PdhAddEnglishCounterW(diskQuery, fullCounterPath, IntPtr.Zero, out var counter) == 0)
				{
					gpuCounters.Add(counter);
				}
			}
			if (gpuCounters.Count > 0)
			{
				PdhCollectQueryData(diskQuery);
			}
		}
		catch
		{
			gpuCounters.Clear();
		}
	}

	private static string ReadCpuName()
	{
		try
		{
			return Registry.GetValue("HKEY_LOCAL_MACHINE\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", "ProcessorNameString", null)?.ToString()?.Trim() ?? "Processeur";
		}
		catch
		{
			return "Processeur";
		}
	}

	private static string ReadGpuName()
	{
		try
		{
			using RegistryKey registryKey = Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Video");
			if (registryKey == null)
			{
				return "Carte graphique";
			}
			string text = null;
			string[] subKeyNames = registryKey.GetSubKeyNames();
			foreach (string text2 in subKeyNames)
			{
				using RegistryKey registryKey2 = registryKey.OpenSubKey(text2 + "\\0000");
				string text3 = registryKey2?.GetValue("DriverDesc")?.ToString()?.Trim();
				string text4 = registryKey2?.GetValue("MatchingDeviceId")?.ToString();
				if (!string.IsNullOrWhiteSpace(text3) && text == null)
				{
					text = text3;
				}
				if (!string.IsNullOrWhiteSpace(text3) && !string.IsNullOrWhiteSpace(text4) && text4.Contains("VEN_", StringComparison.OrdinalIgnoreCase))
				{
					return text3;
				}
			}
			if (!string.IsNullOrWhiteSpace(text))
			{
				return text;
			}
		}
		catch
		{
		}
		return "Carte graphique";
	}

	private static bool TryReadPdh(nint counter, out double value)
	{
		value = 0.0;
		if (counter == IntPtr.Zero || PdhGetFormattedCounterValue(counter, 512u, out var _, out var value2) != 0)
		{
			return false;
		}
		value = value2.DoubleValue;
		if (value2.Status == 0)
		{
			return double.IsFinite(value);
		}
		return false;
	}

	public void Dispose()
	{
		if (diskQuery != IntPtr.Zero)
		{
			PdhCloseQuery(diskQuery);
			diskQuery = IntPtr.Zero;
		}
		GC.SuppressFinalize(this);
	}

	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool GetSystemTimes(out FileTime idleTime, out FileTime kernelTime, out FileTime userTime);

	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool GlobalMemoryStatusEx(ref MemoryStatus buffer);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern uint PdhOpenQueryW(string? dataSource, nint userData, out nint query);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern uint PdhAddEnglishCounterW(nint query, string fullCounterPath, nint userData, out nint counter);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern uint PdhExpandWildCardPathW(string? dataSource, string wildcardPath, [Out] char[]? expandedPathList, ref uint pathListLength, uint flags);

	[DllImport("pdh.dll")]
	private static extern uint PdhCollectQueryData(nint query);

	[DllImport("pdh.dll")]
	private static extern uint PdhGetFormattedCounterValue(nint counter, uint format, out uint type, out PdhValue value);

	[DllImport("pdh.dll")]
	private static extern uint PdhCloseQuery(nint query);
}
