using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CursorWasher
{
    // Shared Y-up scene canvas; Windows pixels and DPI are applied only here.
    internal static class SceneGraphics
    {
        public static void DrawImage(Graphics g, Image image, RectangleF rect, double opacity = 1, double wet = 0)
        {
            GraphicsState state = g.Save();
            g.TranslateTransform(rect.X, rect.Bottom); g.ScaleTransform(1, -1);
            using (ImageAttributes attributes = new ImageAttributes()) {
                ColorMatrix matrix = new ColorMatrix(); matrix.Matrix33 = (float)Motion.Clamp(opacity);
                matrix.Matrix00 = matrix.Matrix11 = matrix.Matrix22 = (float)(1 - wet);
                matrix.Matrix40 = (float)(.25 * wet); matrix.Matrix41 = (float)(.43 * wet); matrix.Matrix42 = (float)(.49 * wet);
                attributes.SetColorMatrix(matrix);
                PointF[] points = { new PointF(0, 0), new PointF(rect.Width, 0), new PointF(0, rect.Height) };
                g.DrawImage(image, points, new RectangleF(0, 0, image.Width, image.Height), GraphicsUnit.Pixel, attributes);
            }
            g.Restore(state);
        }
        public static Graphics Create(Bitmap image, double scale, double x = 0, double y = 192, bool clear = true)
        {
            Graphics g = Graphics.FromImage(image);
            if (clear) g.Clear(Color.Transparent); g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TranslateTransform((float)x, (float)(y * scale)); g.ScaleTransform((float)scale, (float)-scale);
            return g;
        }
        internal static Graphics CreateForExisting(Bitmap image, float x = 0, float top = 192)
        {
            Graphics g = Graphics.FromImage(image);
            g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TranslateTransform(x, top); g.ScaleTransform(1, -1); return g;
        }
    }
}
