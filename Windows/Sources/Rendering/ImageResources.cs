using System;
using System.Drawing;
using System.Reflection;

namespace CursorWasher
{
    internal static class ImageResources
    {
        public static Bitmap Load(string name)
        {
            using (System.IO.Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CursorWasher." + name)) {
                if (stream == null) throw new InvalidOperationException("Missing resource: " + name);
                using (Bitmap source = new Bitmap(stream)) return new Bitmap(source);
            }
        }
    }
}
