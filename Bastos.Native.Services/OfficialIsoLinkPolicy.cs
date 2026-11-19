namespace Bastos.Native.Services;

public static class OfficialIsoLinkPolicy
{
    // Only restart a stopped browser worker once. Publisher refusals and
    // cancellation must never be retried as browser initialization failures.
    public static bool ShouldRetry(string status,int attempt,bool processStopped,bool cancelled) =>
        status=="WebViewUnavailable" && attempt==0 && processStopped && !cancelled;
}
