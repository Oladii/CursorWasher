using System.Collections.Generic;
using System.IO;
using Microsoft.Win32;
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CursorWasher
{
    internal sealed class CursorSprite : IDisposable
    {
        public readonly Bitmap Image;
        public readonly Bitmap ShadowlessImage;
        public readonly Bitmap NativeImage;
        public readonly RectangleF NativeImageRect;
        public readonly CursorShape Shape;
        public readonly RectangleF ImageRect;
        public readonly Size SourcePixelSize;
        public readonly IntPtr Handle;
        public CursorSprite(double scale)
        {
            uint dpi = (uint)Math.Round(scale * 96);
            int side = 32;
            try { side = Native.GetSystemMetricsForDpi(13, dpi); } catch (EntryPointNotFoundException) { }
            Handle = Native.LoadImage(IntPtr.Zero, new IntPtr(32512), 2, side, side, 0x8000);
            if (Handle == IntPtr.Zero) throw new InvalidOperationException("Cannot load the Windows arrow.");
            Native.IconInfo info;
            if (!Native.GetIconInfo(Handle, out info)) throw new InvalidOperationException("Cannot read the Windows arrow.");
            try {
                // Legacy/monochrome and DPI-scaled cursors may have no alpha channel.
                // Recover coverage from native rendering on black and white surfaces.
                int width, height;
                using (Bitmap dimensions = System.Drawing.Image.FromHbitmap(info.Color != IntPtr.Zero ? info.Color : info.Mask)) {
                    width = dimensions.Width; height = info.Color != IntPtr.Zero ? dimensions.Height : dimensions.Height / 2;
                }
                NativeImage = Rasterize(Handle, width, height);
                NativeImageRect = new RectangleF((float)(-info.HotX / scale), (float)((info.HotY - (double)height) / scale), (float)(width / scale), (float)(height / scale));
                Rectangle nativePixels = OpaqueBounds(NativeImage);
                if (nativePixels.IsEmpty) throw new ArgumentException("The system arrow is temporarily transparent.");
                RectangleF visible = new RectangleF((float)((nativePixels.Left - (double)info.HotX) / scale),
                    (float)((info.HotY - (double)nativePixels.Bottom) / scale), (float)(nativePixels.Width / scale), (float)(nativePixels.Height / scale));
                Bitmap detailed = LoadDetailedArrow();
                if (detailed != null && detailed.Width * detailed.Height < width * height) { detailed.Dispose(); detailed = null; }
                try {
                    Bitmap source = detailed ?? NativeImage;
                    SourcePixelSize = source.Size;
                    // Leave room for bicubic filtering around all four source edges.
                    // The native Windows arrow starts at x=0; without padding its thin
                    // vertical outline gets clipped as the transformed image moves.
                    Image = WithSamplingBorder(source);
                } finally { if (detailed != null) detailed.Dispose(); }
                Rectangle pixels = OpaqueBounds(Image);
                // Higher-resolution system representations have slightly different
                // padding. Preserve the live cursor's size and hotspot, not that padding.
                float sx = visible.Width / pixels.Width, sy = visible.Height / pixels.Height;
                ImageRect = new RectangleF(visible.Left - pixels.Left * sx,
                    visible.Bottom + pixels.Top * sy - Image.Height * sy, Image.Width * sx, Image.Height * sy);
                List<Vec> samples = new List<Vec>(); List<double> weights = new List<double>();
                Vec weightedCenter = new Vec(); double totalWeight = 0;
                for (int y = 0; y < Image.Height; y++) for (int x = 0; x < Image.Width; x++) {
                    Color c = Image.GetPixel(x, y);
                    if (c.A < 128) continue;
                    Vec point = new Vec(ImageRect.Left + (x + .5) * sx, ImageRect.Bottom - (y + .5) * sy);
                    double weight = c.A / 255.0;
                    weightedCenter += point * weight; totalWeight += weight;
                    if (x % 2 == 0 && y % 2 == 0) { samples.Add(point); weights.Add(weight); }
                }
                ShadowlessImage = (Bitmap)Image.Clone();
                for (int y = 0; y < Image.Height; y++) for (int x = 0; x < Image.Width; x++) {
                    Color c = Image.GetPixel(x, y);
                    if (c.A < 253 && Math.Max(c.R, Math.Max(c.G, c.B)) < 128) ShadowlessImage.SetPixel(x, y, Color.Transparent);
                }
                Log.Write("cursor dpi=" + dpi + " native=" + width + "x" + height + " detail=" + SourcePixelSize.Width + "x" + SourcePixelSize.Height + " samples=" + samples.Count
                    + " visible=" + visible.Width.ToString("F2", System.Globalization.CultureInfo.InvariantCulture) + "x" + visible.Height.ToString("F2", System.Globalization.CultureInfo.InvariantCulture));
                Shape = new CursorShape(samples, weights, visible, ImageRect, weightedCenter * (1 / totalWeight));
            } catch { Dispose(); throw; }
            finally { if (info.Mask != IntPtr.Zero) Native.DeleteObject(info.Mask); if (info.Color != IntPtr.Zero) Native.DeleteObject(info.Color); }
        }
        internal static Bitmap WithSamplingBorder(Bitmap source)
        {
            Bitmap padded = new Bitmap(source.Width + 4, source.Height + 4, PixelFormat.Format32bppArgb);
            try {
                using (Graphics g = Graphics.FromImage(padded)) {
                    g.CompositingMode = CompositingMode.SourceCopy;
                    g.DrawImageUnscaled(source, 2, 2);
                }
                return padded;
            } catch { padded.Dispose(); throw; }
        }
        private static Rectangle OpaqueBounds(Bitmap image)
        {
            int left = image.Width, top = image.Height, right = -1, bottom = -1;
            for (int y = 0; y < image.Height; y++) for (int x = 0; x < image.Width; x++) if (image.GetPixel(x, y).A >= 128) {
                left = Math.Min(left, x); right = Math.Max(right, x); top = Math.Min(top, y); bottom = Math.Max(bottom, y);
            }
            return right < left ? Rectangle.Empty : Rectangle.FromLTRB(left, top, right + 1, bottom + 1);
        }
        private static Bitmap LoadDetailedArrow()
        {
            // Like NSCursor.image.representations on Mac, choose the largest ORIGINAL
            // image. Enlarging a 32/48px cached HCURSOR cannot recover its lost detail.
            try {
                string path;
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Cursors"))
                    path = key == null ? null : key.GetValue("Arrow") as string;
                if (String.IsNullOrWhiteSpace(path)) return null;
                path = Environment.ExpandEnvironmentVariables(path);
                return LoadDetailedFile(path);
            } catch (IOException) { return null; } catch (UnauthorizedAccessException) { return null; }
            catch (System.Security.SecurityException) { return null; }
        }
        internal static Bitmap LoadDetailedFile(string path)
        {
            CursorImageSource source = CursorImageSource.Read(path);
            if (source == null) return null;
            // CUR/ICO directory entries and ANI icon chunks contain the same
            // raw image resource. Only pixels are needed; the real hotspot stays
            // with the original native cursor, which is never replaced.
            IntPtr handle = Native.CreateIconFromResourceEx(source.Bits, (uint)source.Bits.Length, true, 0x30000, source.Width, source.Height, 0);
            if (handle == IntPtr.Zero) return null;
            try {
                Bitmap detailed = Rasterize(handle, source.Width, source.Height);
                if (!OpaqueBounds(detailed).IsEmpty) return detailed;
                detailed.Dispose(); return null;
            } catch (InvalidOperationException) { return null;
            } finally { Native.DestroyIcon(handle); }
        }
        private static Bitmap Rasterize(IntPtr handle, int width, int height)
        {
            Bitmap result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            try {
                using (Bitmap black = new Bitmap(width, height, PixelFormat.Format32bppArgb))
                using (Bitmap white = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                    DrawNative(black, handle, Color.Black); DrawNative(white, handle, Color.White);
                    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
                        Color b = black.GetPixel(x, y), w = white.GetPixel(x, y);
                        int alpha = Math.Max(0, Math.Min(255, 255 - Math.Max(w.R - b.R, Math.Max(w.G - b.G, w.B - b.B))));
                        if (alpha == 0) continue;
                        result.SetPixel(x, y, Color.FromArgb(alpha, Math.Min(255, b.R * 255 / alpha), Math.Min(255, b.G * 255 / alpha), Math.Min(255, b.B * 255 / alpha)));
                    }
                }
                return result;
            } catch { result.Dispose(); throw; }
        }
        private static void DrawNative(Bitmap image, IntPtr handle, Color background)
        {
            using (Graphics g = Graphics.FromImage(image)) {
                g.Clear(background);
                IntPtr dc = g.GetHdc();
                try { if (!Native.DrawIconEx(dc, 0, 0, handle, image.Width, image.Height, 0, IntPtr.Zero, 3)) throw new InvalidOperationException("Cannot draw the Windows arrow."); }
                finally { g.ReleaseHdc(dc); }
            }
        }
        public void Dispose()
        {
            if (Image != null) Image.Dispose();
            if (ShadowlessImage != null) ShadowlessImage.Dispose();
            if (NativeImage != null) NativeImage.Dispose();
            // LR_SHARED cursor is owned by Windows.
        }
    }

}
