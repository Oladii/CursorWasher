using System;
using System.Drawing;
using System.IO;

namespace CursorWasher
{
    // The portable settings format is shared with existing Windows previews.
    // I/O failures keep the current/default position, as in the original widget.
    internal sealed class WindowSettings
    {
        private readonly string path;
        public WindowSettings(string path) { this.path = path; }

        public bool TryRead(out Point location, out bool topMost)
        {
            location = Point.Empty; topMost = true;
            try {
                if (!File.Exists(path)) return false;
                string[] parts = File.ReadAllText(path).Split(','); int x, y;
                if (parts.Length != 3 || !int.TryParse(parts[0], out x) || !int.TryParse(parts[1], out y)) return false;
                location = new Point(x, y); topMost = parts[2] != "back";
                return true;
            } catch (IOException) { return false; } catch (UnauthorizedAccessException) { return false; }
        }

        public void Write(Point location, bool topMost)
        {
            try { File.WriteAllText(path, location.X + "," + location.Y + "," + (topMost ? "front" : "back")); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
