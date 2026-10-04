using System;
using System.Drawing;

namespace CursorWasher
{
    internal static class CursorRasterTests
    {
        internal static void Run(Action<bool, string> check)
        {
            // A thin black outline touching the source edge, as in aero_arrow.cur.
            // Measure rendered ink, not an implementation detail of the padding.
            using (Bitmap source = new Bitmap(16, 64)) {
                using (Graphics g = Graphics.FromImage(source)) {
                    g.Clear(Color.White); g.FillRectangle(Brushes.Black, 0, 0, 2, 64);
                }
                using (Bitmap padded = CursorSprite.WithSamplingBorder(source)) {
                    double minimum = double.MaxValue, maximum = 0;
                    foreach (double dpi in new[] { 1.0, 1.25, 1.5, 2.0 }) for (int step = 0; step < 16; step++) {
                        const double zoom = .53;
                        using (Bitmap rendered = new Bitmap(128, 128)) {
                            using (Graphics g = SceneGraphics.Create(rendered, dpi, 0, 64)) {
                                g.TranslateTransform((float)(32 + step / (16 * dpi)), 32);
                                g.RotateTransform(180);
                                SceneGraphics.DrawImage(g, padded, new RectangleF((float)(-2 * zoom), (float)(-2 * zoom),
                                    (float)(padded.Width * zoom), (float)(padded.Height * zoom)));
                            }
                            double ink = 0; int row = (int)(44 * dpi);
                            for (int x = 0; x < rendered.Width; x++) {
                                Color p = rendered.GetPixel(x, row);
                                ink += p.A / 255.0 * (1 - p.R / 255.0);
                            }
                            double ratio = ink / (2 * zoom * dpi);
                            minimum = Math.Min(minimum, ratio); maximum = Math.Max(maximum, ratio);
                            // The original unpadded path drops below 1% at some
                            // offsets. The full outline must retain most of its ink.
                            check(ratio > .60 && ratio < 1.15, "Thin source-edge outline keeps its coverage at DPI " + dpi + ", subpixel " + step + ": " + ratio);
                        }
                    }
                    Console.WriteLine("OUTLINE: ink coverage " + minimum.ToString("F3") + ".." + maximum.ToString("F3"));
                }
            }
        }
    }
}
