using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Xml;
using Microsoft.Win32;

namespace CursorWasher
{
    internal static class StatusBarIcon
    {
        public static Icon Create(double scale)
        {
            Color ink = SystemColors.WindowText;
            if (!SystemInformation.HighContrast) {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                    ink = key != null && Convert.ToInt32(key.GetValue("SystemUsesLightTheme", 0)) != 0 ? Color.Black : Color.White;
            }
            using (Bitmap bitmap = Render(Math.Max(16, (int)Math.Round(16 * scale)), ink)) {
                IntPtr handle = bitmap.GetHicon();
                try { using (Icon borrowed = Icon.FromHandle(handle)) return (Icon)borrowed.Clone(); }
                finally { Native.DestroyIcon(handle); }
            }
        }
        public static Bitmap Render(int side, Color ink)
        {
            // The exact same source as Sources/StatusBarIcon.swift. No optical offsets.
            XmlDocument svg = new XmlDocument { XmlResolver = null };
            using (System.IO.Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CursorWasher.status-bar-icon.svg")) svg.Load(stream);
            Bitmap result = new Bitmap(side, side, PixelFormat.Format32bppArgb);
            using (Bitmap large = new Bitmap(side * 4, side * 4, PixelFormat.Format32bppArgb)) {
                using (Graphics g = Graphics.FromImage(large)) using (Brush brush = new SolidBrush(ink)) {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.ScaleTransform(side * 4f / 18, side * 4f / 18);
                    foreach (XmlNode element in svg.GetElementsByTagName("path"))
                        using (GraphicsPath path = Outline(element.Attributes["d"].Value)) g.FillPath(brush, path);
                }
                using (Graphics g = Graphics.FromImage(result)) {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(large, new Rectangle(0, 0, side, side), 0, 0, large.Width, large.Height, GraphicsUnit.Pixel);
                }
            }
            return result;
        }
        private static GraphicsPath Outline(string data)
        {
            // This project-owned SVG uses only absolute M/L/H/V/C/Z commands.
            MatchCollection tokens = Regex.Matches(data, @"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?");
            int at = 0; Func<float> number = delegate { return Single.Parse(tokens[at++].Value, CultureInfo.InvariantCulture); };
            GraphicsPath path = new GraphicsPath(FillMode.Winding); PointF point = new PointF();
            while (at < tokens.Count) {
                string command = tokens[at++].Value; PointF next;
                switch (command) {
                    case "M": point = new PointF(number(), number()); path.StartFigure(); break;
                    case "L": next = new PointF(number(), number()); path.AddLine(point, next); point = next; break;
                    case "H": next = new PointF(number(), point.Y); path.AddLine(point, next); point = next; break;
                    case "V": next = new PointF(point.X, number()); path.AddLine(point, next); point = next; break;
                    case "C": PointF a = new PointF(number(), number()), b = new PointF(number(), number());
                        next = new PointF(number(), number()); path.AddBezier(point, a, b, next); point = next; break;
                    case "Z": path.CloseFigure(); break;
                    default: path.Dispose(); throw new InvalidOperationException("Unsupported status icon SVG command: " + command);
                }
            }
            return path;
        }
    }
}
