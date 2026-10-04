using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace CursorWasher
{
    // Same 256px water plane, paint selection and drawing order as WaterSurface.swift.
    internal sealed class WaterSurface : IDisposable
    {
        internal const int TextureSide = 256;
        private readonly Bitmap stillImage, contactPaint, pocketShade;
        private readonly Bitmap[] layers = new Bitmap[3];
        private readonly GraphicsPath contour;
        private Bitmap lastGood;
        private bool reportedFailure;

        public WaterSurface(Bitmap calm, Bitmap highlights, GraphicsPath path)
        {
            contour = (GraphicsPath)path.Clone();
            stillImage = Crop(calm);
            using (Bitmap reference = Crop(highlights)) {
                for (int layer = 0; layer < 3; layer++) {
                    layers[layer] = new Bitmap(TextureSide, TextureSide, PixelFormat.Format32bppArgb);
                    for (int y = 0; y < TextureSide; y++) for (int x = 0; x < TextureSide; x++) {
                        Color color = reference.GetPixel(x, y);
                        if (color.A / 255.0 <= .05) continue;
                        // GetPixel returns unpremultiplied RGB; the Mac selection also
                        // unpremultiplies and uses source alpha only as a threshold.
                        double luminance = (color.R * .25 + color.G * .6 + color.B * .15) / 255;
                        double u = (x + .5) / TextureSide, v = (y + .5) / TextureSide;
                        double radius = Math.Sqrt(Math.Pow((u - .5) * 2, 2) + Math.Pow((v - .5) * 2, 2));
                        double edge = 1 - Motion.Smooth((radius - .82) / .15);
                        double inner = 1 - Motion.Smooth((radius - .30) / .14), outer = Motion.Smooth((radius - .62) / .16);
                        double weight = layer == 0 ? outer : layer == 1 ? Math.Max(0, 1 - inner - outer) : inner;
                        int alpha = Byte(Motion.Smooth((luminance - .59) / .28) * edge * weight * 255);
                        layers[layer].SetPixel(x, y, Color.FromArgb(alpha, color.R, color.G, color.B));
                    }
                }
            }
            contactPaint = new Bitmap(TextureSide, TextureSide, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(contactPaint)) foreach (Bitmap layer in layers) g.DrawImageUnscaled(layer, 0, 0);
            pocketShade = MakePocketShade();
        }
        private static int Byte(double value) { return Math.Max(0, Math.Min(255, (int)Math.Round(value, MidpointRounding.AwayFromZero))); }
        private static Bitmap Crop(Bitmap source)
        {
            Bitmap image = new Bitmap(TextureSide, TextureSide, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(image)) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.ScaleTransform(TextureSide / BucketLayout.Texture.Width, -TextureSide / BucketLayout.Texture.Height);
                g.TranslateTransform(-BucketLayout.Texture.X, -BucketLayout.Texture.Bottom);
                SceneGraphics.DrawImage(g, source, BucketLayout.Image);
            }
            return image;
        }
        private static Bitmap MakePocketShade()
        {
            Bitmap image = new Bitmap(TextureSide, TextureSide, PixelFormat.Format32bppArgb);
            for (int y = 0; y < TextureSide; y++) for (int x = 0; x < TextureSide; x++) {
                double dx = (x + .5 - 128) / 128, dy = (y + .5 - 128) / 128, t = Math.Sqrt(dx * dx + dy * dy);
                if (t >= 1) continue;
                double alpha = t <= .52 ? .52 + (.38 - .52) * t / .52 : .38 * (1 - (t - .52) / .48);
                image.SetPixel(x, y, Color.FromArgb(Byte(alpha * 255), Byte(.23 * 255), Byte(.39 * 255), Byte(.43 * 255)));
            }
            return image;
        }
        // Borrowed image, owned by this surface. Retain the previous good frame if
        // the graphics backend cannot allocate or composite a frame.
        public Bitmap Frame(IList<Impulse> impulses, bool paintCrests = true)
        {
            bool active = false;
            foreach (Impulse impulse in impulses) if (impulse.Active) { active = true; break; }
            if (!active) {
                if (lastGood != null) { lastGood.Dispose(); lastGood = null; }
                reportedFailure = false; return stillImage;
            }
            try {
                using (Bitmap strokes = new Bitmap(TextureSide, TextureSide, PixelFormat.Format32bppPArgb)) {
                    if (paintCrests) using (Graphics g = SceneGraphics.Create(strokes, 1, 0, TextureSide)) {
                        WaterLayerPose[] poses = WaterMotion.Layers(impulses);
                        for (int i = 0; i < poses.Length; i++) {
                            WaterLayerPose pose = poses[i]; if (pose.Opacity <= 0) continue;
                            GraphicsState state = g.Save();
                            g.TranslateTransform((float)(128 + pose.X * TextureSide), (float)(128 + pose.Y * TextureSide));
                            g.RotateTransform((float)(pose.Rotation * 180 / Math.PI));
                            SceneGraphics.DrawImage(g, layers[i], new RectangleF(-128, -128, TextureSide, TextureSide), pose.Opacity);
                            g.Restore(state);
                        }
                        foreach (Impulse impulse in impulses) if (impulse.Active && impulse.Kind == ImpulseKind.Contact) DrawContact(g, impulse);
                        foreach (WaterRipple ripple in WaterMotion.Ripples(impulses)) {
                            if (ripple.IsDrop) { DrawArc(g, ripple, .16, 2.91, 3); DrawArc(g, ripple, 3.32, 6.05, 8); }
                            else DrawRing(g, ripple);
                        }
                    }
                    Bitmap result = CompositeAtop(stillImage, strokes);
                    if (lastGood != null) lastGood.Dispose();
                    lastGood = result; reportedFailure = false; return result;
                }
            } catch (ExternalException) { ReportFailure(); } catch (OutOfMemoryException) { ReportFailure(); }
            return lastGood ?? stillImage;
        }
        private void ReportFailure()
        { if (!reportedFailure) Log.Write("water_frame_failed: keeping last good image"); reportedFailure = true; }
        internal static Bitmap CompositeAtop(Bitmap basis, Bitmap strokes)
        {
            // GDI+ offers SourceOver/SourceCopy, but not CG's SourceAtop. Compose
            // the ordered strokes first, then apply Porter-Duff in premultiplied
            // pixels: Cout = Cs*Ad + Cd*(1-As); Aout = Ad, including the rim.
            Bitmap result = (Bitmap)basis.Clone();
            Rectangle rect = new Rectangle(0, 0, result.Width, result.Height);
            BitmapData target = null, source = null;
            try {
                target = result.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
                source = strokes.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                byte[] row = new byte[result.Width * 4], ink = new byte[result.Width * 4];
                for (int y = 0; y < result.Height; y++) {
                    IntPtr destination = IntPtr.Add(target.Scan0, y * target.Stride);
                    Marshal.Copy(destination, row, 0, row.Length); Marshal.Copy(IntPtr.Add(source.Scan0, y * source.Stride), ink, 0, ink.Length);
                    for (int x = 0; x < row.Length; x += 4) {
                        int alpha = row[x + 3], inverse = 255 - ink[x + 3];
                        for (int c = 0; c < 3; c++) row[x + c] = (byte)((ink[x + c] * alpha + row[x + c] * inverse + 127) / 255);
                    }
                    Marshal.Copy(row, 0, destination, row.Length);
                }
            } catch { if (target != null) { result.UnlockBits(target); target = null; } result.Dispose(); throw; }
            finally { if (source != null) strokes.UnlockBits(source); if (target != null) result.UnlockBits(target); }
            return result;
        }
        private void DrawContact(Graphics g, Impulse contact)
        {
            double decay = Math.Exp(-contact.Age * 8) * Math.Pow(1 - contact.Age / contact.Duration, 2);
            double gain = Math.Min(1, Math.Abs(contact.Strength) * decay);
            Vec uv = BucketLayout.WaterCoordinates(contact.Position);
            double radius = (contact.Width * 1.05 + .035) * TextureSide;
            GraphicsState state = g.Save();
            g.TranslateTransform((float)(uv.X * TextureSide), (float)(uv.Y * TextureSide)); g.ScaleTransform(1, .8f);
            double pocketRadius = (radius + (contact.Width * .55 + .035) * TextureSide) * 1.6;
            double centerY = TextureSide / BucketLayout.Texture.Height / .8;
            SceneGraphics.DrawImage(g, pocketShade, new RectangleF((float)-pocketRadius, (float)(centerY - pocketRadius), (float)(pocketRadius * 2), (float)(pocketRadius * 2)), gain);
            g.RotateTransform((float)(contact.Rotation * 180 / Math.PI));
            float span = (float)(radius * 4.6);
            SceneGraphics.DrawImage(g, contactPaint, new RectangleF(-span / 2, -span / 2, span, span), gain * .95);
            g.Restore(state);
        }
        private static void DrawArc(Graphics g, WaterRipple ripple, double start, double end, double seed)
        {
            Vec uv = BucketLayout.WaterCoordinates(ripple.Position);
            foreach (bool shadow in new[] { true, false }) {
                List<PointF> points = new List<PointF>();
                foreach (int edge in new[] { 1, -1 }) for (int j = 0; j <= 80; j++) {
                    int i = edge > 0 ? j : 80 - j;
                    double t = i / 80.0, angle = start + (end - start) * t;
                    double taper = Math.Pow(Math.Max(0, Math.Sin(t * Math.PI)), .55);
                    double grain = .78 + .16 * Math.Sin(t * 47 + seed) + .06 * Math.Sin(t * 113 + seed);
                    double wobble = Math.Sin(angle * 5 + seed) * 1.1 + Math.Sin(angle * 11 + seed) * .45;
                    double thickness = 2 * 1.4 * (shadow ? 1.8 : 1) * taper * grain;
                    double radius = ripple.Radius * TextureSide + wobble + edge * thickness * .5;
                    points.Add(new PointF((float)(uv.X * TextureSide + Math.Cos(angle) * radius),
                        (float)(uv.Y * TextureSide + Math.Sin(angle) * radius + (shadow ? -2.4 : 0))));
                }
                using (Brush brush = new SolidBrush(shadow ? Color.FromArgb(Byte(ripple.Opacity * .34 * 255), Byte(.27 * 255), Byte(.40 * 255), Byte(.44 * 255))
                    : Color.FromArgb(Byte(ripple.Opacity * .64 * 255), Byte(.83 * 255), Byte(.89 * 255), Byte(.86 * 255)))) g.FillPolygon(brush, points.ToArray());
            }
        }
        private void DrawRing(Graphics g, WaterRipple ripple)
        {
            using (GraphicsPath path = (GraphicsPath)contour.Clone()) {
                using (Matrix transform = new Matrix((float)ripple.Radius, 0, 0, (float)ripple.Radius,
                    (float)(ripple.Position.X * (1 - ripple.Radius)), (float)(ripple.Position.Y * (1 - ripple.Radius)))) path.Transform(transform);
                GraphicsState scene = g.Save();
                g.ScaleTransform(TextureSide / BucketLayout.Texture.Width, TextureSide / BucketLayout.Texture.Height);
                g.TranslateTransform(-BucketLayout.Texture.X, -BucketLayout.Texture.Y);
                double[] widths = { 1.5, 1, .6, 1.1, .7, .4 }, alphas = { .05, .12, .28, .06, .14, .62 };
                for (int band = 0; band < widths.Length; band++) {
                    GraphicsState state = g.Save(); if (band < 3) g.TranslateTransform(0, -.18f);
                    Color color = band < 3 ? Color.FromArgb(Byte(.25 * 255), Byte(.40 * 255), Byte(.44 * 255))
                        : Color.FromArgb(Byte(.81 * 255), Byte(.88 * 255), Byte(.85 * 255));
                    using (Pen ink = new Pen(Color.FromArgb(Byte(ripple.Opacity * alphas[band] * 255), color), (float)widths[band])) {
                        ink.LineJoin = LineJoin.Round; g.DrawPath(ink, path);
                    }
                    g.Restore(state);
                }
                g.Restore(scene);
            }
        }
        public void Dispose()
        {
            stillImage.Dispose(); contactPaint.Dispose(); pocketShade.Dispose(); contour.Dispose();
            foreach (Bitmap layer in layers) layer.Dispose(); if (lastGood != null) lastGood.Dispose();
        }
    }
}
