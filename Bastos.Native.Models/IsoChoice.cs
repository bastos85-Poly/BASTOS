using System;
using System.IO;

namespace Bastos.Native.Models;

public sealed record IsoChoice(string Display, string Path, bool IsBastosCustom = false, long SizeBytes = 0L, DateTime CreatedAt = default(DateTime), DateTime ModifiedAt = default(DateTime))
{
	public string FileName => System.IO.Path.GetFileName(Path);

	public string SizeDisplay
	{
		get
		{
			if (SizeBytes <= 0)
			{
				return "taille inconnue";
			}
			return $"{(double)SizeBytes / 1024.0 / 1024.0 / 1024.0:N2} Go";
		}
	}

	public string CreatedDisplay
	{
		get
		{
			if (!(CreatedAt == default(DateTime)))
			{
				return $"créée le {CreatedAt:dd/MM/yyyy 'à' HH:mm}";
			}
			return "date de création inconnue";
		}
	}

	public string ModifiedDisplay
	{
		get
		{
			if (!(ModifiedAt == default(DateTime)))
			{
				return $"modifiée le {ModifiedAt:dd/MM/yyyy 'à' HH:mm}";
			}
			return "date de modification inconnue";
		}
	}

	public string Metadata => $"{SizeDisplay}  •  {CreatedDisplay}  •  {ModifiedDisplay}";

	public override string ToString()
	{
		return Display;
	}
}
