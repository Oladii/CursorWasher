using System;
using System.Drawing;

namespace CursorWasher
{
    // Animation keeps the original Mac coordinate system: 192 units, Y upwards.
    // Only the renderer and screen-coordinate adapter flip Y / apply DPI.
    internal struct Vec
    {
        public double X, Y;
        public Vec(double x, double y) { X = x; Y = y; }
        public static Vec operator +(Vec a, Vec b) { return new Vec(a.X + b.X, a.Y + b.Y); }
        public static Vec operator -(Vec a, Vec b) { return new Vec(a.X - b.X, a.Y - b.Y); }
        public static Vec operator *(Vec a, double b) { return new Vec(a.X * b, a.Y * b); }
        public double Length { get { return Math.Sqrt(X * X + Y * Y); } }
        public PointF Point { get { return new PointF((float)X, (float)Y); } }
        public static Vec Mix(Vec a, Vec b, double t) { return a + (b - a) * t; }
        public Vec Transform(double scale, double angle)
        { return new Vec((X * Math.Cos(angle) - Y * Math.Sin(angle)) * scale, (X * Math.Sin(angle) + Y * Math.Cos(angle)) * scale); }
    }

    internal static class Motion
    {
        public static double Clamp(double t) { return Math.Max(0, Math.Min(1, t)); }
        public static double Smooth(double t) { t = Clamp(t); return t * t * (3 - 2 * t); }
        public static double Spring(double t, double z = 1, double w = 7, double velocity = 0)
        {
            t = Clamp(t);
            if (t == 0 || t == 1) return t;
            Func<double, Vec> response = delegate(double x) {
                double decay = Math.Exp(-z * w * x);
                if (z >= 1) return new Vec(1 - (1 + (w - velocity) * x) * decay, (velocity + w * (w - velocity) * x) * decay);
                double wd = w * Math.Sqrt(1 - z * z);
                return new Vec(1 - decay * (Math.Cos(wd * x) + (z * w - velocity) / wd * Math.Sin(wd * x)),
                    decay * (velocity * Math.Cos(wd * x) + (w * w - z * w * velocity) / wd * Math.Sin(wd * x)));
            };
            Vec end = response(1);
            return response(t).X + (1 - end.X) * t * t * (3 - 2 * t) + end.Y * t * t * (1 - t);
        }
    }

    internal static class BucketLayout
    {
        public const double Side = 192, CenterX = 97.5, Waterline = 110.5;
        public static readonly RectangleF Image = new RectangleF(32, 32, 128, 128);
        public static readonly RectangleF Water = new RectangleF(67, 110.5f, 63, 15);
        public static readonly RectangleF Texture = new RectangleF(63, 109, 70, 17);
        public static Vec WaterCoordinates(Vec p) { return new Vec((p.X - 63) / 70, (p.Y - 109) / 17); }
        public static Vec Washing(double t)
        { double a = Motion.Smooth(t) * Math.PI * 8; return new Vec(CenterX + Math.Sin(a) * 9, 118 + Math.Cos(a) * 1.5); }
        public static Vec Velocity(double t)
        { double a = Motion.Smooth(t) * Math.PI * 8, rate = 6 * t * (1 - t) * Math.PI * 8; return new Vec(Math.Cos(a) * rate * 9, -Math.Sin(a) * rate * 1.5); }
    }
}
