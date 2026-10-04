using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

namespace CursorWasher
{
    internal static class PreviewRenderer
    {
        public static void Render(string output)
        {
            Directory.CreateDirectory(output);
            using (Artwork artwork = new Artwork()) using (CursorSprite sprite = new CursorSprite(1.5)) {
                using (Bitmap detail = new Bitmap(600, 240, PixelFormat.Format32bppArgb)) {
                    using (Graphics g = Graphics.FromImage(detail)) g.Clear(Color.FromArgb(238, 235, 226));
                    using (Graphics g = SceneGraphics.Create(detail, 1.5, 0, 150, false)) {
                        System.Drawing.Drawing2D.GraphicsState old = g.Save();
                        g.TranslateTransform(65, 130); g.ScaleTransform(3, 3);
                        SceneGraphics.DrawImage(g, sprite.NativeImage, sprite.NativeImageRect); g.Restore(old);
                        CursorRenderer.Draw(g, sprite, new Frame { Position = new Vec(265, 130), Scale = 3, Angle = 0 });
                    }
                    using (Graphics g = Graphics.FromImage(detail)) using (Font font = new Font("Segoe UI", 11)) {
                        g.DrawString("Before: " + sprite.NativeImage.Width + " px source", font, Brushes.DimGray, 30, 195);
                        g.DrawString("After: " + sprite.SourcePixelSize.Width + " px source", font, Brushes.DimGray, 330, 195);
                    }
                    detail.Save(Path.Combine(output, "cursor-detail.png"), ImageFormat.Png);
                }
                using (Bitmap icon = StatusBarIcon.Render(96, Color.Black)) icon.Save(Path.Combine(output, "status-icon.png"), ImageFormat.Png);
                WashAnimation animation = new WashAnimation(new Vec(97, 85), sprite.Shape);
                RenderMotionStudy(output, artwork, sprite, animation);
                double[] waterTimes = { -1, .58, .64, .69, .90, 1.02, 1.35, 1.8, 2.1, 2.5, 3.1, 4.4 };
                using (Bitmap progression = new Bitmap(320 * 4, 132 * 3)) using (Graphics sheet = Graphics.FromImage(progression)) {
                    sheet.Clear(Color.FromArgb(238, 235, 226));
                    for (int i = 0; i < waterTimes.Length; i++) {
                        Frame f = waterTimes[i] < 0 ? null : animation.At(waterTimes[i], new Vec(110, 85));
                        using (Bitmap bucket = artwork.Bucket(4, f)) {
                            int x = (i % 4) * 320, y = (i / 4) * 132;
                            sheet.DrawImage(bucket, new Rectangle(x + 20, y + 12, 280, 68), new Rectangle(63 * 4, (192 - 126) * 4, 280, 68), GraphicsUnit.Pixel);
                            using (Font font = new Font("Segoe UI", 10)) sheet.DrawString(f == null ? "Idle" : waterTimes[i].ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "s / " + f.Phase, font, Brushes.DimGray, x + 20, y + 92);
                        }
                    }
                    progression.Save(Path.Combine(output, "water-progression.png"), ImageFormat.Png);
                }
                double[] times = { -1, .30, .65, 1.02, 1.55, 2.3, 2.7, 3.15, 3.5, 4.2 };
                using (Bitmap contact = new Bitmap(256 * 5, 296 * 2, PixelFormat.Format32bppArgb)) using (Graphics sheet = Graphics.FromImage(contact)) {
                    sheet.Clear(Color.FromArgb(238, 235, 226));
                    for (int i = 0; i < times.Length; i++) {
                        Frame frame = times[i] < 0 ? null : animation.At(times[i], new Vec(110, 85));
                        using (Bitmap bucket = artwork.Bucket(1, frame)) using (Bitmap panel = new Bitmap(256, 272, PixelFormat.Format32bppArgb)) {
                            using (Graphics g = Graphics.FromImage(panel)) g.DrawImageUnscaled(bucket, 32, 64);
                            using (Graphics g = SceneGraphics.CreateForExisting(panel, 32, 256)) { if (frame != null) CursorRenderer.Draw(g, sprite, frame); }
                            panel.Save(Path.Combine(output, "frame-" + i + ".png"), ImageFormat.Png);
                            sheet.DrawImageUnscaled(panel, (i % 5) * 256, (i / 5) * 296);
                            using (Font font = new Font("Segoe UI", 10)) sheet.DrawString(frame == null ? "Idle" : frame.Phase.ToString(), font, Brushes.DimGray, (i % 5) * 256 + 40, (i / 5) * 296 + 270);
                        }
                    }
                    contact.Save(Path.Combine(output, "contact-sheet.png"), ImageFormat.Png);
                }
            }
            Log.Write("preview_pass");
        }
        private static void RenderMotionStudy(string output, Artwork artwork, CursorSprite sprite, WashAnimation animation)
        {
            foreach (Phase phase in new[] { Phase.Rise, Phase.Turn }) using (Bitmap study = new Bitmap(320 * 6, 420)) using (Graphics sheet = Graphics.FromImage(study)) {
                string name = phase == Phase.Rise ? "rise" : "turn";
                sheet.Clear(Color.FromArgb(210, 210, 210));
                for (int i = 0; i < 6; i++) {
                    double time = WashAnimation.Starts[(int)phase] + WashAnimation.Durations[(int)phase] * i / 5;
                    Frame frame = animation.At(time, new Vec(98, 85));
                    frame.Drops.Clear(); frame.Sparkles.Clear();
                    using (Bitmap bucket = artwork.Bucket(2, frame)) sheet.DrawImageUnscaled(bucket, i * 320 - 32, 48);
                    using (Bitmap cursor = new Bitmap(384, 420)) {
                        Point origin;
                        using (Bitmap surface = CursorRenderer.RenderSurface(sprite, frame, 2, out origin))
                        using (Graphics g = Graphics.FromImage(cursor)) g.DrawImageUnscaled(surface, origin.X, origin.Y + 48);
                        cursor.Save(Path.Combine(output, name + "-cursor-" + i + ".png"), ImageFormat.Png);
                        sheet.DrawImageUnscaled(cursor, i * 320 - 32, 0);
                    }
                    using (Font font = new Font("Segoe UI", 10)) sheet.DrawString(time.ToString("F3") + "s", font, Brushes.Black, i * 320 + 20, 392);
                }
                study.Save(Path.Combine(output, "cursor-" + name + ".png"), ImageFormat.Png);
            }
            using (Bitmap study = new Bitmap(384, 160)) using (Graphics g = Graphics.FromImage(study)) {
                g.Clear(Color.FromArgb(210, 210, 210));
                g.DrawImageUnscaled(sprite.NativeImage, 0, 0);
                g.DrawImageUnscaled(sprite.Image, 128, 0);
                g.DrawImageUnscaled(sprite.ShadowlessImage, 256, 0);
                study.Save(Path.Combine(output, "cursor-sources.png"), ImageFormat.Png);
            }
        }
    }
}
