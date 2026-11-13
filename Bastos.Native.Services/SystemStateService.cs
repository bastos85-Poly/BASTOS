using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Bastos.Native.Models;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class SystemStateService
{
	private struct Luid
	{
		public uint LowPart;

		public int HighPart;
	}

	private struct OpenAdapterFromHdc
	{
		public nint Hdc;

		public uint Adapter;

		public Luid AdapterLuid;

		public uint VidPnSourceId;
	}

	private struct QueryAdapterInfo
	{
		public uint Adapter;

		public uint Type;

		public nint Data;

		public uint DataSize;
	}

	private struct CloseAdapter
	{
		public uint Adapter;
	}

	public bool? ReadHagsSelection()
	{
		if (Registry.GetValue("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "HwSchMode", null) is int num)
		{
			return num switch
			{
				1 => false, 
				2 => true, 
				_ => null, 
			};
		}
		int num2 = QueryPrimaryAdapterWddm27Caps();
		if (num2 < 0 || (num2 & 1) == 0)
		{
			return null;
		}
		return (num2 & 2) != 0;
	}

	public IReadOnlyList<StatusCard> ReadDashboard()
	{
		return new List<StatusCard>
		{
			new StatusCard("Système", ReadWindowsIdentity(), Environment.Is64BitOperatingSystem ? "64 bits" : "32 bits", StatusTone.Neutral),
			new StatusCard("Droits", "Les actions protégées demandent une élévation uniquement au moment nécessaire.", IsAdministrator() ? "Administrateur" : "Session standard", IsAdministrator() ? StatusTone.Success : StatusTone.Neutral),
			ReadHags(),
			ReadVbs(),
			ReadSmartScreen(),
			ReadUtilman()
		};
	}

	private static StatusCard ReadHags()
	{
		int? num = ((Registry.GetValue("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "HwSchMode", null) is int value) ? new int?(value) : ((int?)null));
		int num2 = QueryPrimaryAdapterWddm27Caps();
		bool flag = num2 >= 0;
		bool flag2 = flag && (num2 & 1) != 0;
		bool flag3 = flag2 && (num2 & 2) != 0;
		bool? flag4 = ((num == 1) ? new bool?(false) : ((num == 2) ? new bool?(true) : ((bool?)null)));
		bool flag5 = flag && flag4.HasValue && flag4.Value != flag3;
		if (flag && !flag2)
		{
			return new StatusCard("HAGS", "Le pilote a répondu à la requête WDDM 2.7 mais ne déclare pas HAGS.", "Non pris en charge", StatusTone.Warning);
		}
		if (flag5)
		{
			return new StatusCard("HAGS", "Le réglage demandé diffère de l’état réel du pilote.", flag4.Value ? "Activation configurée — redémarrage requis" : "Désactivation configurée — redémarrage requis", StatusTone.Warning);
		}
		if (flag)
		{
			return new StatusCard("HAGS", "État réel interrogé auprès du pilote graphique par D3DKMT.", flag3 ? "Activée" : "Désactivée", flag3 ? StatusTone.Success : StatusTone.Warning);
		}
		return num switch
		{
			2 => new StatusCard("HAGS", "Requête pilote indisponible ; affichage du choix explicite du Registre.", "Activation configurée", StatusTone.Warning), 
			1 => new StatusCard("HAGS", "Requête pilote indisponible ; affichage du choix explicite du Registre.", "Désactivation configurée", StatusTone.Warning), 
			_ => new StatusCard("HAGS", "État indisponible. Vérifie les paramètres graphiques Windows.", "Inconnu", StatusTone.Neutral), 
		};
	}

	[DllImport("user32.dll")]
	private static extern nint GetDC(nint window);

	[DllImport("user32.dll")]
	private static extern int ReleaseDC(nint window, nint dc);

	[DllImport("gdi32.dll")]
	private static extern int D3DKMTOpenAdapterFromHdc(ref OpenAdapterFromHdc data);

	[DllImport("gdi32.dll")]
	private static extern int D3DKMTQueryAdapterInfo(ref QueryAdapterInfo data);

	[DllImport("gdi32.dll")]
	private static extern int D3DKMTCloseAdapter(ref CloseAdapter data);

	private static int QueryPrimaryAdapterWddm27Caps()
	{
		nint dC = GetDC(IntPtr.Zero);
		if (dC == IntPtr.Zero)
		{
			return -1;
		}
		OpenAdapterFromHdc data = new OpenAdapterFromHdc
		{
			Hdc = dC
		};
		try
		{
			if (D3DKMTOpenAdapterFromHdc(ref data) != 0)
			{
				return -1;
			}
			nint num = Marshal.AllocHGlobal(4);
			try
			{
				Marshal.WriteInt32(num, 0);
				QueryAdapterInfo data2 = new QueryAdapterInfo
				{
					Adapter = data.Adapter,
					Type = 70u,
					Data = num,
					DataSize = 4u
				};
				return (D3DKMTQueryAdapterInfo(ref data2) == 0) ? Marshal.ReadInt32(num) : (-1);
			}
			finally
			{
				Marshal.FreeHGlobal(num);
				CloseAdapter data3 = new CloseAdapter
				{
					Adapter = data.Adapter
				};
				D3DKMTCloseAdapter(ref data3);
			}
		}
		finally
		{
			ReleaseDC(IntPtr.Zero, dC);
		}
	}

	private static StatusCard ReadVbs()
	{
		bool flag = Registry.GetValue("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\DeviceGuard", "EnableVirtualizationBasedSecurity", null) is int num && num == 1;
		return new StatusCard("Sécurité basée sur la virtualisation", "État déclaré dans Device Guard.", flag ? "Activée" : "Désactivée", flag ? StatusTone.Success : StatusTone.Warning);
	}

	private static StatusCard ReadSmartScreen()
	{
		bool flag = File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "smartscreen.exe"));
		return new StatusCard("Microsoft SmartScreen", "Protection de réputation des fichiers téléchargés.", flag ? "Présent" : "Fichier absent", flag ? StatusTone.Success : StatusTone.Danger);
	}

	private static StatusCard ReadUtilman()
	{
		string systemDirectory = Environment.SystemDirectory;
		string text = Path.Combine(systemDirectory, "utilman.exe");
		string text2 = Path.Combine(systemDirectory, "cmd.exe");
		bool flag = File.Exists(text) && File.Exists(text2) && FilesEqual(text, text2);
		return new StatusCard("Fichier Utilman", "Contrôle local contre le remplacement de l’outil d’accessibilité par CMD.", flag ? "Remplacé par CMD" : "Distinct de CMD", (!flag) ? StatusTone.Success : StatusTone.Danger);
	}

	private static bool FilesEqual(string first, string second)
	{
		FileInfo fileInfo = new FileInfo(first);
		FileInfo fileInfo2 = new FileInfo(second);
		if (fileInfo.Length != fileInfo2.Length)
		{
			return false;
		}
		using FileStream fileStream = File.OpenRead(first);
		using FileStream fileStream2 = File.OpenRead(second);
		Span<byte> buffer = stackalloc byte[8192];
		Span<byte> buffer2 = stackalloc byte[8192];
		int num;
		int num2;
		do
		{
			num = fileStream.Read(buffer);
			num2 = fileStream2.Read(buffer2);
			if (num != num2)
			{
				return false;
			}
			if (num == 0)
			{
				return true;
			}
		}
		while (buffer.Slice(0, num).SequenceEqual(buffer2.Slice(0, num2)));
		return false;
	}

	private static bool IsAdministrator()
	{
		using WindowsIdentity ntIdentity = WindowsIdentity.GetCurrent();
		return new WindowsPrincipal(ntIdentity).IsInRole(WindowsBuiltInRole.Administrator);
	}

	private static string ReadWindowsIdentity()
	{
		using RegistryKey registryKey = Registry.LocalMachine.OpenSubKey("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion");
		string value = registryKey?.GetValue("ProductName")?.ToString() ?? "Windows";
		string value2 = registryKey?.GetValue("DisplayVersion")?.ToString() ?? "";
		string value3 = registryKey?.GetValue("CurrentBuild")?.ToString() ?? Environment.OSVersion.Version.Build.ToString();
		return $"{value} {value2} — build {value3}".Trim();
	}
}
