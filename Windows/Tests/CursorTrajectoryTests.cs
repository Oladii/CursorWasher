using System;
using System.Drawing;

namespace CursorWasher
{
    internal static class CursorTrajectoryTests
    {
        private static Vec Center(CursorShape shape, Frame f)
        { return f.Position + shape.VisibleCenter.Transform(f.Scale, f.Angle); }

        internal static void CheckPath(Action<bool, string> check, CursorShape shape, WashAnimation wash)
        {
            Vec target = new Vec(109, 83);
            Vec rest = Center(shape, wash.At(WashAnimation.Starts[(int)Phase.Sparkle], target));
            double previousY = double.MinValue;
            foreach (Phase phase in new[] { Phase.Rise, Phase.Shake, Phase.Turn, Phase.Sparkle }) {
                for (int step = 0; step <= 40; step++) {
                    Frame f = wash.At(WashAnimation.Starts[(int)phase] + WashAnimation.Durations[(int)phase] * step / 40, target);
                    Vec center = Center(shape, f);
                    check(Math.Abs(center.X - rest.X) < 1e-6, "A single vertical axis spans rise, shake, turn and sparkle for every cursor shape");
                    if (phase == Phase.Rise) {
                        check(center.Y >= previousY - 1e-6 && center.Y <= rest.Y + 1e-6, "Rising center follows a monotonic vertical path without overshoot");
                        previousY = center.Y;
                    }
                    if (phase == Phase.Turn || phase == Phase.Sparkle)
                        check((center - rest).Length < 1e-6, "Rotation and sparkle share exactly one fixed center, without sideways compensation");
                    SinkAnimation sink = new SinkAnimation(f, shape);
                    check(Math.Abs(sink.At(sink.Duration).Position.X - f.Position.X) < 1e-6,
                        "Cancellation above the bucket sinks vertically without recentering");
                }
            }
            // Adjacent phases must also join at the same visible-center velocity.
            const double dt = 1e-5;
            foreach (Phase phase in new[] { Phase.PartialDip, Phase.Wash, Phase.Rise, Phase.Shake, Phase.Turn, Phase.Sparkle, Phase.Returning }) {
                double time = WashAnimation.Starts[(int)phase];
                Vec before = Center(shape, wash.At(time - dt, target)), at = Center(shape, wash.At(time, target)), after = Center(shape, wash.At(time + dt, target));
                check((at - before).Length < .02 && (after - at).Length < .02, "Visible center has no jump at " + phase);
                check(((at - before) * (1 / dt) - (after - at) * (1 / dt)).Length < 1,
                    "Visible-center velocity is continuous at " + phase);
            }
        }

        internal static void CheckRenderedPivot(Action<bool, string> check, CursorSprite sprite, WashAnimation wash, double dpi)
        {
            double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
            for (int step = 0; step <= 16; step++) {
                Frame frame = wash.At(WashAnimation.Starts[(int)Phase.Turn] + WashAnimation.Durations[(int)Phase.Turn] * step / 16, new Vec(98, 85));
                frame.Drops.Clear(); frame.Sparkles.Clear();
                Point origin;
                using (Bitmap rendered = CursorRenderer.RenderSurface(sprite, frame, dpi, out origin)) {
                    double weight = 0, xSum = 0, ySum = 0;
                    for (int y = 0; y < rendered.Height; y++) for (int x = 0; x < rendered.Width; x++) {
                        double alpha = rendered.GetPixel(x, y).A / 255.0;
                        weight += alpha; xSum += (origin.X + x + .5) * alpha; ySum += (origin.Y + y + .5) * alpha;
                    }
                    check(weight > 0, "Cursor remains rendered through the reverse turn");
                    double cx = xSum / weight, cy = ySum / weight;
                    minX = Math.Min(minX, cx); maxX = Math.Max(maxX, cx);
                    minY = Math.Min(minY, cy); maxY = Math.Max(maxY, cy);
                }
            }
            check(maxX - minX < 1 && maxY - minY < 1, "Actual rendered pivot stays within one physical pixel at DPI " + dpi
                + ": dx=" + (maxX - minX) + ", dy=" + (maxY - minY));
            Console.WriteLine("PIVOT DPI " + dpi + ": dx=" + (maxX - minX).ToString("F3") + "px, dy=" + (maxY - minY).ToString("F3") + "px");
        }
    }
}
