using CreamInstaller.Utility;

namespace CreamInstaller.Tests;

internal static class Program
{
    private static async Task Main()
    {
        (string Name, Func<Task> Run)[] tests =
        [
            (nameof(AcceptsMatchingOrMissingContentLength), AcceptsMatchingOrMissingContentLength),
            (nameof(RejectsInvalidExpectedSize), RejectsInvalidExpectedSize),
            (nameof(RejectsMismatchedContentLength), RejectsMismatchedContentLength),
            (nameof(CopiesExactDownload), CopiesExactDownload),
            (nameof(RejectsTruncatedDownload), RejectsTruncatedDownload),
            (nameof(RejectsOversizedDownloadBeforeWritingExtraBytes), RejectsOversizedDownloadBeforeWritingExtraBytes),
            (nameof(HonorsCancellationAtEndOfDownload), HonorsCancellationAtEndOfDownload)
        ];

        foreach ((string name, Func<Task> run) in tests)
        {
            await run();
            Console.WriteLine($"PASS {name}");
        }
    }

    private static Task AcceptsMatchingOrMissingContentLength()
    {
        DownloadValidator.ValidateResponseSize(4, 4);
        DownloadValidator.ValidateResponseSize(4, null);
        return Task.CompletedTask;
    }

    private static Task RejectsInvalidExpectedSize()
    {
        ExpectThrows<InvalidDataException>(() => DownloadValidator.ValidateResponseSize(0, null));
        ExpectThrows<InvalidDataException>(() => DownloadValidator.ValidateResponseSize(-1, null));
        return Task.CompletedTask;
    }

    private static Task RejectsMismatchedContentLength()
    {
        ExpectThrows<InvalidDataException>(() => DownloadValidator.ValidateResponseSize(4, 3));
        ExpectThrows<InvalidDataException>(() => DownloadValidator.ValidateResponseSize(4, 5));
        return Task.CompletedTask;
    }

    private static async Task CopiesExactDownload()
    {
        byte[] payload = [1, 2, 3, 4];
        await using MemoryStream source = new(payload, false);
        await using MemoryStream destination = new();
        RecordingProgress progress = new();

        await DownloadValidator.CopyToAsync(source, destination, payload.Length, progress, CancellationToken.None);

        Assert(payload.SequenceEqual(destination.ToArray()), "The copied payload did not match the source.");
        Assert(progress.Values.Count > 0 && progress.Values[^1] == 100, "Progress did not finish at 100 percent.");
    }

    private static async Task RejectsTruncatedDownload()
    {
        byte[] payload = [1, 2, 3];
        await using MemoryStream source = new(payload, false);
        await using MemoryStream destination = new();

        await ExpectThrowsAsync<InvalidDataException>(
            () => DownloadValidator.CopyToAsync(source, destination, payload.Length + 1, null, CancellationToken.None));
    }

    private static async Task RejectsOversizedDownloadBeforeWritingExtraBytes()
    {
        const int expectedBytes = 16384;
        byte[] payload = new byte[expectedBytes + 1];
        await using MemoryStream source = new(payload, false);
        await using MemoryStream destination = new();

        await ExpectThrowsAsync<InvalidDataException>(
            () => DownloadValidator.CopyToAsync(source, destination, expectedBytes, null, CancellationToken.None));
        Assert(destination.Length == expectedBytes, "The validator wrote bytes beyond the declared size.");
    }

    private static async Task HonorsCancellationAtEndOfDownload()
    {
        byte[] payload = [1, 2, 3, 4];
        using CancellationTokenSource cancellation = new();
        await using CancelOnEofStream source = new(payload, cancellation);
        await using MemoryStream destination = new();

        await ExpectThrowsAsync<OperationCanceledException>(
            () => DownloadValidator.CopyToAsync(source, destination, payload.Length, null, cancellation.Token));
    }

    private static void ExpectThrows<TException>(Action action) where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }
        throw new InvalidOperationException($"Expected {typeof(TException).Name}.");
    }

    private static async Task ExpectThrowsAsync<TException>(Func<Task> action) where TException : Exception
    {
        try
        {
            await action();
        }
        catch (TException)
        {
            return;
        }
        throw new InvalidOperationException($"Expected {typeof(TException).Name}.");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }

    private sealed class RecordingProgress : IProgress<int>
    {
        internal List<int> Values { get; } = [];

        public void Report(int value) => Values.Add(value);
    }

    private sealed class CancelOnEofStream(byte[] payload, CancellationTokenSource cancellation) : MemoryStream(payload, false)
    {
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            int bytesRead = await base.ReadAsync(buffer, cancellationToken);
            if (bytesRead == 0)
                cancellation.Cancel();
            return bytesRead;
        }
    }
}
