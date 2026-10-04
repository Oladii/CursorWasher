using System;
using System.IO;

namespace CursorWasher
{
    internal static class Log
    {
        public static void Write(string message)
        {
            try { File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "CursorWasher.log"), DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
