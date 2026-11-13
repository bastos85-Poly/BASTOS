using System.Collections.Generic;

namespace Bastos.Native.Services;

public sealed record TroubleshootingSnapshot(Dictionary<string, bool> States, Dictionary<string, string> Choices);
