using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CursorWasher
{
    internal sealed class Artwork : IDisposable
    {
        private readonly Bitmap bucket;
        private readonly WaterSurface water;
        private Bitmap idle;
        private double idleScale;
        public readonly GraphicsPath WaterPath;
        public Artwork()
        {
            try {
                bucket = ImageResources.Load("bucket-dry.png"); WaterPath = MakeWaterPath();
                using (Bitmap calm = ImageResources.Load("water-calm-source.png"))
                using (Bitmap highlights = ImageResources.Load("water-highlights-source.png")) water = new WaterSurface(calm, highlights, WaterPath);
            } catch { Dispose(); throw; }
        }
        private static PointF WaterPoint(float x, float y) { return new PointF(32 + x / 1254 * 128, 32 + (1254 - y) / 1254 * 128); }
        private static GraphicsPath MakeWaterPath()
        {
            GraphicsPath path = new GraphicsPath();
            path.AddBezier(WaterPoint(312, 416), WaterPoint(397, 323), WaterPoint(882, 322), WaterPoint(976, 417));
            path.AddBezier(WaterPoint(976, 417), WaterPoint(914, 464), WaterPoint(782, 489), WaterPoint(647, 492));
            path.AddBezier(WaterPoint(647, 492), WaterPoint(513, 492), WaterPoint(379, 466), WaterPoint(312, 416));
            path.CloseFigure(); return path;
        }
        internal bool Contains(Vec p)
        {
            if (!BucketLayout.Image.Contains(p.Point)) return false;
            if (WaterPath.IsVisible(p.Point)) return true;
            int x = Math.Min(bucket.Width - 1, (int)((p.X - 32) / 128 * bucket.Width));
            int y = Math.Min(bucket.Height - 1, (int)((160 - p.Y) / 128 * bucket.Height));
            return bucket.GetPixel(Math.Max(0, x), Math.Max(0, y)).A >= 26;
        }
        public Bitmap Bucket(double scale, Frame frame)
        {
            int side = (int)Math.Round(BucketLayout.Side * scale);
            if (idle == null || idleScale != scale) {
                Bitmap replacement = new Bitmap(side, side, PixelFormat.Format32bppPArgb);
                try {
                    using (Graphics g = SceneGraphics.Create(replacement, scale)) {
                        SceneGraphics.DrawImage(g, bucket, BucketLayout.Image); g.SetClip(WaterPath);
                        g.CompositingMode = CompositingMode.SourceCopy;
                        SceneGraphics.DrawImage(g, water.Frame(new Impulse[0]), BucketLayout.Texture);
                    }
                } catch { replacement.Dispose(); throw; }
                if (idle != null) idle.Dispose();
                idleScale = scale; idle = replacement;
            }
            Bitmap image = (Bitmap)idle.Clone();
            try {
                if (frame != null) using (Graphics g = SceneGraphics.Create(image, scale, 0, 192, false)) {
                    g.SetClip(WaterPath); g.CompositingMode = CompositingMode.SourceCopy;
                    SceneGraphics.DrawImage(g, water.Frame(frame.Impulses), BucketLayout.Texture);
                }
                return image;
            } catch { image.Dispose(); throw; }
        }
        public void Dispose()
        {
            if (bucket != null) bucket.Dispose();
            if (water != null) water.Dispose();
            if (idle != null) idle.Dispose();
            if (WaterPath != null) WaterPath.Dispose();
        }
    }
}
