using System.Collections.Generic;

namespace Bastos.Native.Services;

public sealed record TweakingSnapshot(Dictionary<string, bool> States, Dictionary<string, string> Choices, int Quantum);
