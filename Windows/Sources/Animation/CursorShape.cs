using System;
using System.Collections.Generic;
using System.Drawing;

namespace CursorWasher
{
    internal sealed class Immersion
    {
        public readonly Vec Center;
        public readonly double HalfWidth, Depth;
        public Immersion(Vec center, double halfWidth, double depth) { Center = center; HalfWidth = halfWidth; Depth = depth; }
        public double LowerEdge(double x)
        { double u = (x - Center.X) / HalfWidth; return Center.Y - Depth * Math.Sqrt(Math.Max(0, 1 - u * u)); }
    }

    internal sealed class CursorShape
    {
        public readonly List<Vec> Samples;
        public readonly List<double> Weights;
        private readonly RectangleF visibleBounds;
        public readonly RectangleF ImageBounds;
        public readonly Vec VisibleCenter;
        public CursorShape(List<Vec> samples, List<double> weights = null, RectangleF? visible = null, RectangleF? image = null, Vec? visibleCenter = null)
        {
            if (samples.Count == 0) throw new ArgumentException("The cursor has no visible pixels.");
            Samples = samples;
            Weights = weights ?? samples.ConvertAll(delegate(Vec p) { return 1.0; });
            visibleBounds = visible ?? PixelBounds(1, 0);
            ImageBounds = image ?? visibleBounds;
            Vec center = new Vec(); double weight = 0;
            for (int i = 0; i < samples.Count; i++) { center += samples[i] * Weights[i]; weight += Weights[i]; }
            VisibleCenter = visibleCenter ?? center * (1 / Math.Max(.001, weight));
        }
        public RectangleF Bounds(double scale, double angle)
        { return TransformBounds(visibleBounds, scale, angle); }
        public Vec PositionAtCenter(Vec center, double scale, double angle)
        { return center - VisibleCenter.Transform(scale, angle); }
        public static RectangleF TransformBounds(RectangleF rect, double scale, double angle)
        {
            Vec[] corners = { new Vec(rect.Left, rect.Top), new Vec(rect.Right, rect.Top), new Vec(rect.Right, rect.Bottom), new Vec(rect.Left, rect.Bottom) };
            return BoundsOf(corners, scale, angle);
        }
        public RectangleF PixelBounds(double scale, double angle) { return BoundsOf(Samples, scale, angle); }
        private static RectangleF BoundsOf(IEnumerable<Vec> points, double scale, double angle)
        {
            double left = double.MaxValue, bottom = double.MaxValue, right = double.MinValue, top = double.MinValue;
            foreach (Vec sample in points) {
                Vec p = sample.Transform(scale, angle);
                left = Math.Min(left, p.X); right = Math.Max(right, p.X);
                bottom = Math.Min(bottom, p.Y); top = Math.Max(top, p.Y);
            }
            return RectangleF.FromLTRB((float)left, (float)bottom, (float)right, (float)top);
        }
        public Vec Contact(Vec position, double scale, double angle, double line)
        {
            double distance = double.MaxValue;
            foreach (Vec sample in Samples) distance = Math.Min(distance, Math.Abs(position.Y + sample.Transform(scale, angle).Y - line));
            double sum = 0, weight = 0;
            for (int i = 0; i < Samples.Count; i++) {
                Vec p = position + Samples[i].Transform(scale, angle);
                if (Math.Abs(p.Y - line) <= distance + 0.6) { sum += p.X * Weights[i]; weight += Weights[i]; }
            }
            return new Vec(weight == 0 ? position.X : sum / weight, line);
        }
        public Immersion Immersed(Vec position, double scale, double angle, double line, double depth)
        {
            RectangleF body = PixelBounds(scale, angle);
            if (depth <= 0 || position.Y + body.Top >= line + .5 || position.Y + body.Bottom < line - depth) return null;
            double distance = double.MaxValue;
            foreach (Vec sample in Samples) distance = Math.Min(distance, Math.Abs(position.Y + sample.Transform(scale, angle).Y - line));
            double left = double.MaxValue, right = double.MinValue;
            foreach (Vec sample in Samples) {
                Vec p = position + sample.Transform(scale, angle);
                if (Math.Abs(p.Y - line) <= distance + .5) { left = Math.Min(left, p.X); right = Math.Max(right, p.X); }
            }
            return new Immersion(new Vec((left + right) / 2, line), Math.Max(1.2, (right - left) / 2 + .35), depth);
        }
    }
}
