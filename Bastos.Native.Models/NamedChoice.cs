namespace Bastos.Native.Models;

public sealed record NamedChoice(string Display, string Value)
{
	public override string ToString()
	{
		return Display;
	}
}
