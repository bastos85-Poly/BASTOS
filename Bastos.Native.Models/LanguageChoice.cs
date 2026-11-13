namespace Bastos.Native.Models;

public sealed record LanguageChoice(string Display, string Value, string Locale)
{
	public override string ToString()
	{
		return Display;
	}
}
