using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public static class WindowsKeyboardLayoutDetector
{
	[DllImport("user32.dll")]
	private static extern IntPtr GetKeyboardLayout(uint threadId);

	[DllImport("user32.dll", EntryPoint = "GetKeyboardLayoutNameW", CharSet = CharSet.Unicode)]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool GetKeyboardLayoutName(StringBuilder name);

	public static string? DetectInputLocale()
	{
		try
		{
			var layoutName = new StringBuilder(9);
			if (GetKeyboardLayoutName(layoutName) && IsLayoutId(layoutName.ToString()))
			{
				int languageId = (int)(GetKeyboardLayout(0).ToInt64() & 0xFFFF);
				if (languageId != 0)
					return languageId.ToString("X4", CultureInfo.InvariantCulture) + ":" + layoutName.ToString().ToUpperInvariant();
			}
		}
		catch (Exception)
		{
			// Windows peut ne pas fournir de disposition au thread pendant l'ouverture.
		}

		try
		{
			using RegistryKey? preload = Registry.CurrentUser.OpenSubKey(@"Keyboard Layout\Preload");
			string? fallback = preload?.GetValue("1") as string;
			if (!IsLayoutId(fallback)) return null;
			fallback = fallback!.ToUpperInvariant();
			return fallback.Substring(4, 4) + ":" + fallback;
		}
		catch (Exception)
		{
			return null;
		}
	}

	private static bool IsLayoutId(string? value) => value != null && Regex.IsMatch(value, "^[0-9A-Fa-f]{8}$");
}
