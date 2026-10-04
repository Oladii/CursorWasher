using System;
using System.Collections.Generic;
using System.Drawing;

namespace CursorWasher
{
    internal sealed class WashAnimation
    {
        // Same phase order and timings as Sources/WashAnimation.swift, v0.20.0.
        public static readonly double[] Durations = { .4875, .21, .15, .2625, .975, .30, .60, .30, .825, .35 };
        public static readonly double[] Starts = MakeStarts();
        public static readonly double Duration = Starts[9] + Durations[9];
        private readonly Vec startCenter, hoverCenter, riseCenter;
        private readonly CursorShape shape;
        private readonly double enlargedScale;
        // Mac reference: 104 x 173 opaque pixels in the 280 x 400 bitmap,
        // displayed at 28 x 40 points and enlarged 3x (Build/Preview/cursor-native-shadow.png).
        // Fit both dimensions uniformly: the Windows arrow is proportionally wider.
        private const double MacCursorWidth = 31.2, MacCursorHeight = 51.9;
        // The white Windows arrow still reads larger at equal bounding-box size.
        // Apply the user's visual adjustment independently of system cursor/DPI size.
        private const double VisualSize = .85;
        // Keep the agreed upside-down resting position (Mac visible center, then
        // the user's one-point left adjustment), as a FIXED scene axis for all poses.
        internal const double CursorAxisX = BucketLayout.CenterX + 2.6715410666 - 1;
        private readonly double[] impacts = new double[2];
        private readonly Vec[] impactPoints = new Vec[2];
        private readonly List<Flight> flights = new List<Flight>();
        private sealed class WaterState { public Vec Velocity; public double Strength, Rotation; }
        private readonly List<WaterState> waterStates = new List<WaterState>();
        private const double WaterStep = 1.0 / 240;
        private const double WashingAngle = Math.PI * 160 / 180;
        private sealed class Flight { public Vec Origin, Landing; public double Emission, Lifetime; public int Id; }

        public WashAnimation(Vec start, CursorShape shape)
        {
            this.shape = shape;
            RectangleF nativeBody = shape.Bounds(1, 0);
            enlargedScale = Math.Min(MacCursorWidth / Math.Max(.001, nativeBody.Width),
                MacCursorHeight / Math.Max(.001, nativeBody.Height)) * VisualSize;
            startCenter = start + shape.VisibleCenter;
            Vec upsideCenter = shape.VisibleCenter.Transform(enlargedScale, Math.PI);
            hoverCenter = new Vec(CursorAxisX, BucketLayout.Water.Bottom + 8
                + upsideCenter.Y - shape.Bounds(enlargedScale, Math.PI).Top);
            riseCenter = SubmergedCenter(WashingAngle, BucketLayout.CenterX) + new Vec(0, 4);
            for (int i = 0; i < 2; i++) {
                Phase phase = i == 0 ? Phase.PartialDip : Phase.Dive;
                Vec from = i == 0 ? hoverCenter : InterDip;
                Vec to = i == 0 ? Partial : SubmergedCenter(Math.PI, BucketLayout.CenterX);
                double bottom = shape.PixelBounds(enlargedScale, Math.PI).Top - upsideCenter.Y;
                double threshold = Motion.Clamp((from.Y + bottom - BucketLayout.Waterline) / Math.Max(.001, from.Y - to.Y));
                double lo = 0, hi = 1;
                for (int j = 0; j < 32; j++) { double mid = (lo + hi) / 2; if (DipProgress(i, mid) < threshold) lo = mid; else hi = mid; }
                double t = (lo + hi) / 2;
                impacts[i] = Starts[(int)phase] + t * Durations[(int)phase];
                // Keep the Mac splash axis fixed while optically aligning the
                // differently shaped Windows arrow to the Mac's visible pixels.
                impactPoints[i] = new Vec(BucketLayout.CenterX, BucketLayout.Waterline);
            }
            MakeFlights(); MakeWaterStates();
        }
        private static double[] MakeStarts()
        { double[] starts = new double[Durations.Length]; for (int i = 1; i < starts.Length; i++) starts[i] = starts[i - 1] + Durations[i - 1]; return starts; }
        public Vec Hover(double angle)
        { return shape.PositionAtCenter(hoverCenter, enlargedScale, angle); }
        private Vec SubmergedCenter(double angle, double orbitX, double offset = 0, double depth = 1)
        {
            RectangleF pixels = shape.PixelBounds(enlargedScale, angle);
            double centerY = shape.VisibleCenter.Transform(enlargedScale, angle).Y;
            return new Vec(CursorAxisX + (orbitX - BucketLayout.CenterX),
                BucketLayout.Waterline + offset + centerY - pixels.Top - pixels.Height * .8 * depth);
        }
        private Vec Partial { get { return SubmergedCenter(Math.PI, BucketLayout.CenterX, 0, .75); } }
        private Vec InterDip { get { return Vec.Mix(Partial, hoverCenter, .5); } }
        private double EntryVelocity { get { return Math.Min(1.5, 120 * Durations[1] / Math.Max(.001, hoverCenter.Y - Partial.Y)); } }
        private double DipProgress(int index, double t) { return index == 0 ? Motion.Spring(t, 1, 7, EntryVelocity) : Motion.Spring(t, .58, 7); }
        public static double Shake(double t) { return Math.Sin(4 * Math.PI * t) * Math.Pow(Math.Sin(Math.PI * t), 2); }

        public Frame At(double elapsed, Vec cursor)
        {
            double time = Math.Max(0, Math.Min(Duration, elapsed));
            int index = 0;
            while (index < 9 && time >= Starts[index] + Durations[index]) index++;
            double t = time >= Duration ? 1 : Motion.Clamp((time - Starts[index]) / Durations[index]), eased = Motion.Spring(t);
            Vec center = hoverCenter;
            Frame f = new Frame { Phase = (Phase)index, Scale = enlargedScale };
            switch (f.Phase) {
                case Phase.Approach:
                    f.Scale = 1 + (enlargedScale - 1) * eased; f.Angle = Math.PI * eased;
                    double speed = -EntryVelocity * (hoverCenter.Y - Partial.Y) / Durations[1];
                    Vec control = new Vec(hoverCenter.X, hoverCenter.Y - speed * Durations[0] / 3);
                    double u = 1 - t;
                    center = startCenter * (u * u * u + 3 * u * u * t) + control * (3 * u * t * t) + hoverCenter * (t * t * t);
                    break;
                case Phase.PartialDip: center = Vec.Mix(hoverCenter, Partial, DipProgress(0, t)); f.Waterline = BucketLayout.Waterline; break;
                case Phase.DipLift: center = Vec.Mix(Partial, InterDip, eased); f.Waterline = BucketLayout.Waterline; break;
                case Phase.Dive: center = Vec.Mix(InterDip, SubmergedCenter(Math.PI, BucketLayout.CenterX), DipProgress(1, t)); f.Waterline = BucketLayout.Waterline; break;
                case Phase.Wash:
                    f.Angle = Math.PI + (WashingAngle - Math.PI) * Motion.Smooth(t / .12);
                    Vec motion = BucketLayout.Washing(t);
                    double raise = 3 * Motion.Smooth(t / .12);
                    center = SubmergedCenter(f.Angle, motion.X, motion.Y - 119.5) + new Vec(0, Motion.Smooth(t / .06) + raise);
                    f.Waterline = BucketLayout.Waterline + raise; break;
                case Phase.Rise:
                    f.Angle = WashingAngle + (Math.PI - WashingAngle) * eased;
                    // Fixed endpoints for the center; rotation cannot bend the path.
                    center = Vec.Mix(riseCenter, hoverCenter, eased);
                    f.Waterline = BucketLayout.Waterline + 3 * (1 - eased); break;
                case Phase.Shake: center += new Vec(0, Shake(t) * 12); break;
                case Phase.Turn:
                    f.Angle = Math.PI * (1 - Motion.Spring(t, 1, 8.5)); break;
                case Phase.Sparkle: f.Angle = 0; break;
                case Phase.Returning:
                    f.Scale = enlargedScale + (1 - enlargedScale) * eased; f.Angle = 0;
                    center = Vec.Mix(hoverCenter, cursor + shape.VisibleCenter, eased) + new Vec(0, Math.Sin(Math.PI * eased) * 10); break;
            }
            // The only conversion to a hotspot-based render pose. Every phase
            // moves the same visible center, and every rotation pivots around it.
            f.Position = shape.PositionAtCenter(center, f.Scale, f.Angle);
            if (f.Phase == Phase.Wash || f.Phase == Phase.Rise) {
                double depth = 1.35 * (f.Phase == Phase.Wash ? Motion.Smooth(t / .12) : 1 - eased);
                f.Immersion = shape.Immersed(f.Position, f.Scale, f.Angle, f.Waterline.Value, depth);
            }
            if (f.Phase == Phase.Sparkle) AddSparkles(f, t);
            List<Impulse> landedDrops = new List<Impulse>();
            foreach (Flight flight in flights) {
                double age = time - flight.Emission, progress = age / flight.Lifetime;
                if (progress >= 0 && progress < 1) {
                    Vec p = new Vec(flight.Origin.X + (flight.Landing.X - flight.Origin.X) * progress,
                        flight.Origin.Y + (flight.Landing.Y - flight.Origin.Y) * (.6 * progress + .4 * progress * progress));
                    f.Drops.Add(new Particle(p, (4.7 + flight.Id % 3 * .65) / 2, Math.Min(1, (1 - progress) * 12)) {
                        Variant = flight.Id, Velocity = new Vec((flight.Landing.X - flight.Origin.X) / flight.Lifetime,
                            (flight.Landing.Y - flight.Origin.Y) * (.6 + .8 * progress) / flight.Lifetime) });
                }
                if (age >= flight.Lifetime && age < flight.Lifetime + .8) landedDrops.Add(new Impulse(flight.Landing, age - flight.Lifetime, .32, ImpulseKind.Drop));
            }
            for (int i = 0; i < 2; i++) if (time >= impacts[i]) {
                f.Impulses.Add(new Impulse(impactPoints[i], time - impacts[i], i == 0 ? .75 : 1.15));
                Splash(f, time - impacts[i], impactPoints[i]);
            }
            Impulse stirring = StirImpulse(time);
            if (stirring != null) f.Impulses.Add(stirring);
            f.ShadowVisible = index < 1 || index > 4;
            if (f.Waterline.HasValue) {
                double bottom = f.Position.Y + shape.PixelBounds(f.Scale, f.Angle).Top;
                double wet = Motion.Smooth((f.Waterline.Value - bottom) / 2.5);
                double roundedDepth = f.Immersion == null ? 0 : f.Immersion.Depth;
                Immersion contact = shape.Immersed(f.Position, f.Scale, f.Angle, f.Waterline.Value, Math.Max(1.35, roundedDepth));
                if (wet > 0 && contact != null) {
                    double front = roundedDepth / 1.35, inset = 1.1 * (1 - front) - .15 * front;
                    f.Impulses.Add(new Impulse(new Vec(contact.Center.X, contact.Center.Y - roundedDepth + inset), 1e-6,
                        (.88 + Math.Min(.12, (stirring == null ? 0 : stirring.Strength) * .5)) * wet * Motion.Smooth((time - impacts[0]) / .045), ImpulseKind.Contact) {
                        Direction = stirring == null ? -Math.PI / 2 : stirring.Direction,
                        Rotation = -(time - impacts[0]) * 12 + (stirring == null ? 0 : stirring.Rotation) * .65,
                        Width = (Math.Min(8, Math.Max(3, contact.HalfWidth)) + 2 * (1 - front)) / BucketLayout.Texture.Width
                    });
                }
            }
            f.Impulses.AddRange(landedDrops);
            return f;
        }
        private void AddSparkles(Frame f, double t)
        {
            RectangleF b = shape.Bounds(f.Scale, f.Angle); b.Offset(f.Position.Point);
            double cycle = t * 2, fraction = cycle - Math.Floor(cycle);
            bool second = cycle >= 1;
            Vec[] centers = second ? new[] { new Vec(b.Right + 7, b.Bottom - 3), new Vec(b.Left - 9, b.Top + b.Height / 2 + 1), new Vec(b.Right + 6, b.Top + 7) }
                : new[] { new Vec(b.Left - 8, b.Bottom - 7), new Vec(b.Right + 8, b.Top + b.Height / 2 + 3), new Vec(b.Left - 7, b.Top + 5) };
            double[] delays = second ? new[] { .16, 0, .30 } : new[] { 0, .16, .30 };
            double[] radii = second ? new[] { 5, 7, 4.5 } : new[] { 7.0, 5, 6 };
            double[] lifetimes = second ? new[] { .68, .65, .70 } : new[] { .65, .68, .70 };
            for (int i = 0; i < 3; i++) {
                double flash = (fraction - delays[i]) / lifetimes[i];
                if (flash > 0 && flash < 1) { double pulse = Math.Sin(Math.PI * flash); f.Sparkles.Add(new Particle(centers[i], radii[i] * (.35 + .65 * pulse), pulse)); }
            }
        }
        private Impulse StirImpulse(double time)
        {
            double elapsed = time - Starts[4];
            if (elapsed <= 0 || elapsed >= Durations[4] + 2.3) return null;
            double sample = elapsed / WaterStep; int at = Math.Min((int)sample, waterStates.Count - 2);
            double fraction = sample - at;
            WaterState a = waterStates[at], b = waterStates[at + 1];
            Vec velocity = Vec.Mix(a.Velocity, b.Velocity, fraction);
            Vec motion = BucketLayout.Washing(Math.Min(1, elapsed / Durations[4]));
            return new Impulse(new Vec(motion.X, 116 + motion.Y - 118 + Motion.Smooth(elapsed / Durations[4] / .06)),
                1e-6, a.Strength + (b.Strength - a.Strength) * fraction, ImpulseKind.Stir) {
                Direction = Math.Atan2(velocity.Y, velocity.X), Rotation = a.Rotation + (b.Rotation - a.Rotation) * fraction
            };
        }
        public static void Splash(Frame f, double age, Vec origin)
        {
            double[] delay = { 0, .05, .02, .09, .03, .07 }, rise = { 27, 42, 34, 25, 46, 36 }, drift = { -29, 18, -11, 34, -21, 8 }, diameter = { 6.6, 7.4, 5.2, 6.1, 5.8, 7 };
            for (int i = 0; i < 6; i++) {
                double speed = Math.Sqrt(8000 * rise[i]), life = 2 * speed / 4000, elapsed = age - delay[i] * .315, u = elapsed / life;
                if (u < 0 || u >= 1) continue;
                f.Drops.Add(new Particle(origin + new Vec(drift[i] * u, speed * elapsed - 2000 * elapsed * elapsed), diameter[i] / 2, Math.Min(1, u * 9) * Math.Pow(1 - u, .6)) {
                    Variant = i, Velocity = new Vec(drift[i] / life, speed - 4000 * elapsed) });
            }
        }
        private void MakeFlights()
        {
            for (int burst = 0; burst < 2; burst++) {
                double lo = burst == 0 ? .25 : .75, hi = lo + .25;
                for (int j = 0; j < 48; j++) { double a = lo + (hi - lo) / 3, b = hi - (hi - lo) / 3; if (Shake(a) < Shake(b)) hi = b; else lo = a; }
                double fraction = (lo + hi) / 2;
                int count = burst == 0 ? 4 : 2;
                RectangleF bounds = shape.PixelBounds(enlargedScale, Math.PI);
                for (int i = 0; i < count; i++) {
                    double x = bounds.Left + bounds.Width * (i + 1) / (count + 1);
                    Vec attachment = new Vec(); double distance = double.MaxValue;
                    double[] heights = { .2, .62, .4, .78 };
                    foreach (Vec sample in shape.Samples) distance = Math.Min(distance, Math.Abs(sample.Transform(enlargedScale, Math.PI).X - x));
                    List<Vec> column = shape.Samples.ConvertAll(delegate(Vec sample) { return sample.Transform(enlargedScale, Math.PI); })
                        .FindAll(delegate(Vec p) { return Math.Abs(p.X - x) <= distance + 1e-6; });
                    double bottom = double.MaxValue, top = double.MinValue;
                    foreach (Vec p in column) { bottom = Math.Min(bottom, p.Y); top = Math.Max(top, p.Y); }
                    double desiredY = bottom + (top - bottom) * heights[i], nearest = double.MaxValue;
                    foreach (Vec p in column) if (Math.Abs(p.Y - desiredY) < nearest) { nearest = Math.Abs(p.Y - desiredY); attachment = p; }
                    Vec origin = Hover(Math.PI) + attachment + new Vec(0, Shake(fraction) * 12);
                    flights.Add(new Flight { Id = burst * 4 + i, Origin = origin,
                        Landing = new Vec(origin.X + (i - (count - 1) / 2.0) * 2, 115 + ((i + burst) % 3 - 1) * .75),
                        Emission = Starts[6] + fraction * Durations[6], Lifetime = .135 * (1 - .08 * (i % 3)) });
                }
            }
        }
        private void MakeWaterStates()
        {
            Vec velocity = new Vec(); double strength = 0, spin = 0, angle = 0;
            waterStates.Add(new WaterState());
            for (int i = 1; i <= Math.Ceiling((Durations[4] + 2.3) / WaterStep); i++) {
                double time = i * WaterStep, progress = Math.Min(1, time / Durations[4]);
                Vec v = BucketLayout.Velocity(progress), orbit = BucketLayout.Washing(progress);
                double orbitRate = ((orbit.X - BucketLayout.CenterX) / 9 * v.Y / 1.5 - (orbit.Y - 118) / 1.5 * v.X / 9) / Durations[4];
                if (progress > 0 && progress < .06) { double q = progress / .06; v.Y += 6 * q * (1 - q) / .06; }
                double attack = Motion.Smooth(time / .12), final = Motion.Smooth((time - Durations[4] + .30) / .30), release = Motion.Smooth((time - Durations[4]) / .08);
                double response = 1 - Math.Exp(-WaterStep / (.07 + .48 * final + 1.65 * release));
                Vec target = time < Durations[4] ? new Vec(v.X / 70 / Durations[4] * attack, v.Y / 17 / Durations[4] * attack) : new Vec();
                velocity = Vec.Mix(velocity, target, response);
                double targetStrength = time < Durations[4] ? .6 * Math.Min(1, Math.Max(velocity.Length / 6, Math.Abs(spin) / 16 * final)) : 0;
                strength += (targetStrength - strength) * response;
                double settle = 1 - Motion.Smooth((time - Durations[4] - .90) / 1.40);
                spin += ((time < Durations[4] ? orbitRate * .42 * attack : 0) - spin) * response;
                angle += spin * settle * WaterStep;
                waterStates.Add(new WaterState { Velocity = velocity * settle, Strength = strength * settle, Rotation = angle });
            }
        }
    }
}
