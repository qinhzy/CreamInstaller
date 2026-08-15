using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace CreamInstaller.Utility;

internal static class DownloadValidator
{
    private const int BufferSize = 16384;

    internal static void ValidateResponseSize(long expectedBytes, long? contentLength)
    {
        if (expectedBytes <= 0)
            throw new InvalidDataException("The release asset did not include a valid download size.");
        if (contentLength is { } actualBytes && actualBytes != expectedBytes)
            throw new InvalidDataException(
                $"The update download size ({actualBytes} bytes) does not match the release metadata ({expectedBytes} bytes).");
    }

    internal static async Task CopyToAsync(Stream download, Stream destination, long expectedBytes,
        IProgress<int> progress, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(download);
        ArgumentNullException.ThrowIfNull(destination);
        ValidateResponseSize(expectedBytes, null);

        byte[] buffer = new byte[BufferSize];
        long bytesRead = 0;
        int lastReport = 0;
        int newBytes;
        while ((newBytes = await download.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) != 0)
        {
            if (newBytes > expectedBytes - bytesRead)
                throw new InvalidDataException("The update download exceeded its declared release size.");
            await destination.WriteAsync(buffer.AsMemory(0, newBytes), cancellationToken);
            bytesRead += newBytes;
            int report = bytesRead == expectedBytes ? 100 : (int)(bytesRead / (double)expectedBytes * 100);
            if (report <= lastReport)
                continue;
            progress?.Report(report);
            lastReport = report;
        }

        if (bytesRead != expectedBytes)
            throw new InvalidDataException(
                $"The update download ended early ({bytesRead} of {expectedBytes} bytes).");
        cancellationToken.ThrowIfCancellationRequested();
        await destination.FlushAsync(cancellationToken);
        if (lastReport < 100)
            progress?.Report(100);
    }
}
