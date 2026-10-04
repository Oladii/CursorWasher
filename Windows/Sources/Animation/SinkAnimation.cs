using System;
using System.Drawing;

namespace CursorWasher
{
    internal sealed class SinkAnimation
    {
        private readonly Frame source;
        private readonly CursorShape shape;
        private readonly Vec entry, destination;
        private readonly double transit, line, depth;
        internal readonly double ImpactAt;
        internal readonly Vec ImpactPoint;
        public double Duration { get { return Math.Max(transit + .32, ImpactAt + .315); } }
        public SinkAnimation(Frame source, CursorShape shape)
        {
            this.source = source; this.shape = shape;
            RectangleF b = shape.Bounds(source.Scale, source.Angle);
            RectangleF image = CursorShape.TransformBounds(shape.ImageBounds, source.Scale, source.Angle);
            line = source.Waterline ?? BucketLayout.Waterline;
            depth = source.Immersion == null ? 0 : source.Immersion.Depth;
            double center = source.Position.X + (b.Left + b.Right) / 2;
            bool direct = source.Waterline.HasValue || (center >= 67 && center <= 130 && source.Position.Y + b.Top >= line);
            transit = direct ? 0 : .22;
            entry = direct ? source.Position : new Vec(WashAnimation.CursorAxisX - shape.VisibleCenter.Transform(source.Scale, source.Angle).X, line + 3 - image.Top);
            destination = new Vec(entry.X, line - depth - image.Bottom - 2);
            double visibleTop = shape.PixelBounds(source.Scale, source.Angle).Bottom;
            double contact = Motion.Clamp((entry.Y + visibleTop - line + depth) / Math.Max(.001, entry.Y - destination.Y));
            double lo = 0, hi = 1;
            for (int i = 0; i < 32; i++) { double mid = (lo + hi) / 2; if (Motion.Spring(mid) < contact) lo = mid; else hi = mid; }
            ImpactAt = transit + (contact == 0 ? 0 : (lo + hi) / 2 * .32);
            ImpactPoint = shape.Contact(Vec.Mix(entry, destination, Motion.Spring((ImpactAt - transit) / .32)), source.Scale, source.Angle, line - depth);
        }
        public Frame At(double elapsed)
        {
            double time = Math.Min(Duration, Math.Max(0, elapsed));
            Frame f = new Frame { Phase = Phase.Dive, Scale = source.Scale, Angle = source.Angle, ShadowVisible = false };
            if (time < transit) {
                double t = Motion.Spring(time / transit), u = 1 - t;
                Vec control = new Vec((source.Position.X + entry.X) / 2, Math.Max(source.Position.Y, entry.Y) + 20);
                f.Position = source.Position * (u * u) + control * (2 * u * t) + entry * (t * t);
                f.Waterline = source.Waterline;
            } else { f.Position = Vec.Mix(entry, destination, Motion.Spring((time - transit) / .32)); f.Waterline = line; }
            f.Immersion = shape.Immersed(f.Position, f.Scale, f.Angle, line, depth);
            double fade = 1 - Motion.Spring((time - ImpactAt) / Math.Max(.001, Duration - ImpactAt));
            foreach (Impulse impulse in source.Impulses) f.Impulses.Add(impulse.Advance(time, fade));
            if (time >= ImpactAt) { f.Impulses.Add(new Impulse(ImpactPoint, time - ImpactAt, 1.2 * fade)); WashAnimation.Splash(f, time - ImpactAt, ImpactPoint); }
            return f;
        }
    }
}
