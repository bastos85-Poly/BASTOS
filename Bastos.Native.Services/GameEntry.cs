using System;

namespace Bastos.Native.Services;

public sealed class GameEntry
{
	public string Path { get; set; } = string.Empty;

	public string Name { get; set; } = string.Empty;

	public string AddedUtc { get; set; } = DateTime.UtcNow.ToString("O");
}
