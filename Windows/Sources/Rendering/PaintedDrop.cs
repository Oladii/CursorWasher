using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CursorWasher
{
    internal static class PaintedDrop
    {
        // Same asymmetric watercolor outline as Sources/PaintedWaterDrop.swift.
        public static void Draw(Graphics g, Particle drop)
        {
            if (drop.Opacity <= 0) return;
            GraphicsState state = g.Save();
            g.TranslateTransform((float)drop.Position.X, (float)drop.Position.Y);
            double angle = drop.Velocity.Length > .001 ? Math.Atan2(drop.Velocity.Y, drop.Velocity.X) + Math.PI / 2 : 0;
            g.RotateTransform((float)(angle * 180 / Math.PI));
            float w = (float)drop.Width, h = (float)drop.Height;
            float taper = drop.Variant % 3 == 0 ? 0 : (float)(.3 * Math.Min(1, drop.Velocity.Length / 700));
            float skew = (float)(Math.Sin(drop.Variant * 2.4) * .045 * w);
            using (GraphicsPath path = new GraphicsPath()) {
                path.AddBezier(skew, h * .5f, -w * (.34f - taper * .2f) + skew, h * .5f, -w * .51f, h * .23f, -w * .5f, -h * .03f);
                path.AddBezier(-w * .5f, -h * .03f, -w * .49f, -h * .33f, -w * .28f, -h * .5f, -skew, -h * .5f);
                path.AddBezier(-skew, -h * .5f, w * .3f, -h * .5f, w * .51f, -h * .3f, w * .49f, -h * .01f);
                path.AddBezier(w * .49f, -h * .01f, w * .48f, h * .24f, w * (.3f - taper * .2f) + skew, h * .5f, skew, h * .5f);
                path.CloseFigure();
                using (SolidBrush body = new SolidBrush(Color.FromArgb((int)(Motion.Clamp(drop.Opacity) * 217), 140, 173, 176))) g.FillPath(body, path);
                using (Pen edge = new Pen(Color.FromArgb((int)(Motion.Clamp(drop.Opacity) * 122), 77, 110, 115), .45f)) g.DrawPath(edge, path);
            }
            using (GraphicsPath light = new GraphicsPath()) {
                light.AddBezier(-w * .18f, h * .13f, -w * .33f, h * .06f, -w * .34f, -h * .1f, -w * .2f, -h * .2f);
                using (Pen ink = new Pen(Color.FromArgb((int)(Motion.Clamp(drop.Opacity) * 184), 235, 237, 217), .65f)) { ink.StartCap = ink.EndCap = LineCap.Round; g.DrawPath(ink, light); }
            }
            g.Restore(state);
        }
    }
}
