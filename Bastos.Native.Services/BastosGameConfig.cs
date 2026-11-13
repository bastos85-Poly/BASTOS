using System.Collections.Generic;

namespace Bastos.Native.Services;

public sealed class BastosGameConfig
{
	public int Version { get; set; } = 2;

	public bool Enabled { get; set; } = true;

	public bool AutoDetect { get; set; } = true;

	public bool RunAtStartup { get; set; } = true;

	public bool OptimizeBackground { get; set; }

	public List<GameEntry> Games { get; set; } = new List<GameEntry>();

	public List<GameEntry> BlockedApps { get; set; } = new List<GameEntry>();
}
