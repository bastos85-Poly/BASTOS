using System;

namespace Bastos.Native.Models;

// Only the explicit operation-message protocol is split. Unknown module messages
// remain visible in full: a sentence or a path may carry an important warning.
public sealed record MessagePresentation(string Summary, string NextStep = "", string Effects = "", string Details = "")
{
    public static MessagePresentation From(string? message, string? detail = null)
    {
        string text = (message ?? "").Replace("\r\n", "\n");
        const string effectsMarker = "\nÉtat : ", nextMarker = "\nÀ faire : ", referenceMarker = "\nRéférence : ";
        int effects = text.IndexOf(effectsMarker, StringComparison.Ordinal);
        int next = text.IndexOf(nextMarker, StringComparison.Ordinal);
        if (effects <= 0 || next <= effects) return new(text, Details: detail ?? "");
        int reference = text.IndexOf(referenceMarker, next, StringComparison.Ordinal);
        string details = "", suffix = "";
        if (reference >= 0)
        {
            string tail = text[(reference + referenceMarker.Length)..];
            const string ending = ". Détails dans Journal.";
            // Services can append cancellation/restart warnings after the reference.
            // Hide only the exact metadata, never the remainder of that line.
            if (tail.Length >= 32 + ending.Length && Guid.TryParseExact(tail[..32], "N", out _) &&
                tail[32..].StartsWith(ending, StringComparison.Ordinal))
            {
                details = "Référence : " + tail[..(32 + ending.Length)];
                suffix = tail[(32 + ending.Length)..];
            }
            else reference = -1;
        }
        if (!string.IsNullOrWhiteSpace(detail)) details += (details.Length == 0 ? "" : "\n\n") + detail;
        return new(text[..effects],
            text[(next + nextMarker.Length)..(reference < 0 ? text.Length : reference)] + suffix,
            text[(effects + effectsMarker.Length)..next], details);
    }
}
