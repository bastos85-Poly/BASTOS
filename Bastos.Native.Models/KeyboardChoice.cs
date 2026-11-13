namespace Bastos.Native.Models;

public sealed record KeyboardChoice(string Display, string InputLocale)
{
	public override string ToString()
	{
		return Display;
	}
}
