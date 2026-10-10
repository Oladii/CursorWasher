using System;
using System.IO;

namespace CursorWasher
{
    internal static class Log
    {
        [System.Diagnostics.Conditional("DIAGNOSTICS")]
        public static void Write(string message)
        {
#if DIAGNOSTICS
            try { File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "CursorWasher.log"), DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
#endif
        }
    }
}
