using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CursorWasher
{
    internal static class CursorRenderer
    {
        internal static Bitmap RenderSurface(CursorSprite sprite, Frame frame, double scale, out Point offset)
        {
            // Tight passive surface; never a desktop-sized input window.
            RectangleF body = sprite.ImageRect;
            Vec[] corners = { new Vec(body.Left, body.Top), new Vec(body.Right, body.Top), new Vec(body.Left, body.Bottom), new Vec(body.Right, body.Bottom) };
            double left = double.MaxValue, bottom = double.MaxValue, right = double.MinValue, top = double.MinValue;
            foreach (Vec corner in corners) { Vec p = frame.Position + corner.Transform(frame.Scale, frame.Angle); left = Math.Min(left, p.X); right = Math.Max(right, p.X); bottom = Math.Min(bottom, p.Y); top = Math.Max(top, p.Y); }
            foreach (Particle p in frame.Drops) { left = Math.Min(left, p.Position.X - p.Radius * 2); right = Math.Max(right, p.Position.X + p.Radius * 2); bottom = Math.Min(bottom, p.Position.Y - p.Radius * 2); top = Math.Max(top, p.Position.Y + p.Radius * 2); }
            foreach (Particle p in frame.Sparkles) { left = Math.Min(left, p.Position.X - p.Radius - 2); right = Math.Max(right, p.Position.X + p.Radius + 2); bottom = Math.Min(bottom, p.Position.Y - p.Radius - 2); top = Math.Max(top, p.Position.Y + p.Radius + 2); }
            int px = (int)Math.Floor(left * scale) - 2, py = (int)Math.Floor((BucketLayout.Side - top) * scale) - 2;
            int width = Math.Max(1, (int)Math.Ceiling(right * scale) - px + 2), height = Math.Max(1, (int)Math.Ceiling((BucketLayout.Side - bottom) * scale) - py + 2);
            offset = new Point(px, py);
            Bitmap image = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            try {
                using (Graphics g = SceneGraphics.Create(image, scale, -px, BucketLayout.Side - py / scale)) CursorRenderer.Draw(g, sprite, frame);
                return image;
            } catch { image.Dispose(); throw; }
        }
        public static void Draw(Graphics g, CursorSprite sprite, Frame f)
        {
            // Keep the native cursor pixel-exact at capture/return. Animated poses
            // use a finer grid so changing rotation cannot shift the sampled center.
            if (Math.Abs(f.Scale - 1) < 1e-9 && Math.Abs(f.Angle) < 1e-9) { DrawCore(g, sprite, f); return; }
            const int samples = 2;
            RectangleF clip = g.VisibleClipBounds;
            PointF[] corners = { new PointF(clip.Left, clip.Top), new PointF(clip.Right, clip.Top),
                new PointF(clip.Left, clip.Bottom), new PointF(clip.Right, clip.Bottom) };
            using (Matrix transform = g.Transform) {
                transform.TransformPoints(corners);
                float left = corners[0].X, right = left, top = corners[0].Y, bottom = top;
                foreach (PointF p in corners) { left = Math.Min(left, p.X); right = Math.Max(right, p.X); top = Math.Min(top, p.Y); bottom = Math.Max(bottom, p.Y); }
                Rectangle target = Rectangle.FromLTRB((int)Math.Floor(left), (int)Math.Floor(top), (int)Math.Ceiling(right), (int)Math.Ceiling(bottom));
                if (target.Width <= 0 || target.Height <= 0) return;
                using (Bitmap sampled = new Bitmap(target.Width * samples, target.Height * samples, PixelFormat.Format32bppPArgb)) {
                    using (Graphics high = Graphics.FromImage(sampled)) {
                        high.SmoothingMode = SmoothingMode.AntiAlias;
                        high.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        high.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        transform.Translate(-target.X, -target.Y, MatrixOrder.Append);
                        transform.Scale(samples, samples, MatrixOrder.Append);
                        high.Transform = transform;
                        DrawCore(high, sprite, f);
                    }
                    GraphicsState state = g.Save();
                    try {
                        g.ResetTransform();
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.DrawImage(sampled, target, 0, 0, sampled.Width, sampled.Height, GraphicsUnit.Pixel);
                    } finally { g.Restore(state); }
                }
            }
        }
        private static void DrawCore(Graphics g, CursorSprite sprite, Frame f)
        {
            GraphicsState state = g.Save();
            if (f.Waterline.HasValue) {
                float line = (float)f.Waterline.Value;
                using (GraphicsPath mask = new GraphicsPath()) {
                    mask.AddLine(-4096, line, f.Immersion == null ? 4096 : (float)(f.Immersion.Center.X - f.Immersion.HalfWidth), line);
                    if (f.Immersion != null) {
                        for (int i = 0; i < 48; i++) {
                            double x = f.Immersion.Center.X + f.Immersion.HalfWidth * (i / 24.0 - 1);
                            double next = x + f.Immersion.HalfWidth / 24;
                            mask.AddLine((float)x, (float)f.Immersion.LowerEdge(x), (float)next, (float)f.Immersion.LowerEdge(next));
                        }
                        mask.AddLine((float)(f.Immersion.Center.X + f.Immersion.HalfWidth), line, 4096, line);
                    }
                    mask.AddLine(4096, line, 4096, 8192); mask.AddLine(4096, 8192, -4096, 8192); mask.CloseFigure();
                    g.SetClip(mask, CombineMode.Intersect);
                }
            }
            if (f.Immersion == null) DrawCursorBody(g, sprite, f, 0);
            else {
                double lower = f.Immersion.Center.Y - f.Immersion.Depth, upper = f.Immersion.Center.Y + 2;
                GraphicsState clear = g.Save();
                g.SetClip(new RectangleF(-4096, (float)upper, 8192, 8192), CombineMode.Intersect);
                DrawCursorBody(g, sprite, f, 0); g.Restore(clear);
                // Disjoint bands preserve the cursor alpha, including antialiasing.
                for (int band = 0; band < 8; band++) {
                    double a = lower + (upper - lower) * band / 8, b = lower + (upper - lower) * (band + 1) / 8;
                    GraphicsState tint = g.Save();
                    g.SetClip(new RectangleF(-4096, (float)a, 8192, (float)(b - a)), CombineMode.Intersect);
                    DrawCursorBody(g, sprite, f, .48 * (1 - (band + .5) / 8)); g.Restore(tint);
                }
            }
            g.Restore(state);
            foreach (Particle drop in f.Drops) PaintedDrop.Draw(g, drop);
            foreach (Particle sparkle in f.Sparkles) {
                float r = (float)sparkle.Radius; Vec p = sparkle.Position;
                PointF[] vertices = new PointF[8];
                for (int i = 0; i < 8; i++) { double a = i * Math.PI / 4; double size = i % 2 == 0 ? r : r * .22; vertices[i] = (p + new Vec(Math.Cos(a) * size * .8, Math.Sin(a) * size)).Point; }
                using (SolidBrush light = new SolidBrush(Color.FromArgb((int)(Motion.Clamp(sparkle.Opacity) * 255), 239, 252, 255))) g.FillPolygon(light, vertices);
                using (Pen edge = new Pen(Color.FromArgb((int)(Motion.Clamp(sparkle.Opacity) * 200), 114, 190, 230), .65f)) g.DrawPolygon(edge, vertices);
            }
        }
        private static void DrawCursorBody(Graphics g, CursorSprite sprite, Frame f, double wet)
        {
            GraphicsState state = g.Save();
            g.TranslateTransform((float)f.Position.X, (float)f.Position.Y); g.RotateTransform((float)(f.Angle * 180 / Math.PI)); g.ScaleTransform((float)f.Scale, (float)f.Scale);
            bool nativeSize = f.Scale <= 1.001 && f.ShadowVisible;
            SceneGraphics.DrawImage(g, nativeSize ? sprite.NativeImage : f.ShadowVisible ? sprite.Image : sprite.ShadowlessImage,
                nativeSize ? sprite.NativeImageRect : sprite.ImageRect, 1, wet); g.Restore(state);
        }
    }
}
