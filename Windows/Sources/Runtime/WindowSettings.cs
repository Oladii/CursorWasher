using System;
using System.Drawing;
using System.IO;
using Microsoft.Win32;

namespace CursorWasher
{
    // Keep user preferences out of the folder containing the portable executable.
    internal sealed class WindowSettings
    {
        private const string KeyPath = @"Software\CursorWasher";

        public bool TryRead(out Point location, out bool topMost)
        {
            location = Point.Empty; topMost = true;
            try {
                string value;
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(KeyPath))
                    value = key == null ? null : key.GetValue("Window") as string;
                if (value == null) return false;
                string[] parts = value.Split(','); int x, y;
                if (parts.Length != 3 || !int.TryParse(parts[0], out x) || !int.TryParse(parts[1], out y)) return false;
                location = new Point(x, y); topMost = parts[2] != "back";
                return true;
            } catch (IOException) { return false; } catch (UnauthorizedAccessException) { return false; }
            catch (System.Security.SecurityException) { return false; }
        }

        public void Write(Point location, bool topMost)
        {
            try {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(KeyPath))
                    if (key != null) key.SetValue("Window", location.X + "," + location.Y + "," + (topMost ? "front" : "back"), RegistryValueKind.String);
            }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
            catch (System.Security.SecurityException) { }
        }
    }
}
