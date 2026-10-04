using System;
using System.Collections.Generic;

namespace CursorWasher
{
    internal enum ImpulseKind { Dip, Stir, Wake, Drop, Contact }
    internal sealed class Impulse
    {
        // Positions use scene units; WaterMotion converts them to the Mac water UV plane.
        public Vec Position;
        public double Age, Strength, Direction, Rotation, Width = .06;
        public ImpulseKind Kind;
        public Impulse(Vec position, double age, double strength, ImpulseKind kind = ImpulseKind.Dip)
        { Position = position; Age = age; Strength = strength; Kind = kind; }
        public double Duration {
            get { switch (Kind) { case ImpulseKind.Dip: return 3.5; case ImpulseKind.Stir: case ImpulseKind.Contact: return .35; case ImpulseKind.Wake: return 1.1; default: return .8; } }
        }
        public bool Active { get { return Age > 0 && Age < Duration && Math.Abs(Strength) > 1e-6; } }
        public Impulse Advance(double time, double gain)
        { return new Impulse(Position, Age + time, Strength * gain, Kind) { Direction = Direction, Rotation = Rotation, Width = Width }; }
    }
    internal sealed class WaterLayerPose
    { public double X, Y, Opacity, Rotation; }
    internal sealed class WaterRipple
    {
        public Vec Position;
        public double Radius, Opacity;
        public bool IsDrop;
    }
    // Direct numerical port of Sources/WaterMotion.swift.
    internal static class WaterMotion
    {
        public static WaterLayerPose[] Layers(IEnumerable<Impulse> impulses)
        {
            double[] travel = { .20, .65, 1.20 }, arrival = { 1.15, .32, 0 }, coverage = { .48, .74, .90 };
            WaterLayerPose[] layers = { new WaterLayerPose(), new WaterLayerPose(), new WaterLayerPose() };
            foreach (Impulse impulse in impulses) {
                if (!impulse.Active || (impulse.Kind != ImpulseKind.Stir && impulse.Kind != ImpulseKind.Wake)) continue;
                Vec uv = BucketLayout.WaterCoordinates(impulse.Position);
                double t = impulse.Age / impulse.Duration;
                double attack = impulse.Kind == ImpulseKind.Wake ? 1 - Math.Exp(-impulse.Age * 40) : 1;
                double gain = impulse.Strength * attack * Math.Exp(-impulse.Age * 5) * Math.Pow(1 - t, 2);
                for (int i = 0; i < layers.Length; i++) {
                    layers[i].X += ((uv.X - .5) * .72 + Math.Cos(impulse.Direction) * .11) * gain * .35;
                    layers[i].Y += ((uv.Y - .5) * .20 + Math.Sin(impulse.Direction) * .055) * gain * .3;
                    layers[i].Rotation += impulse.Rotation * travel[i];
                    double phase = Math.Abs(impulse.Rotation) + (impulse.Kind == ImpulseKind.Wake ? impulse.Age * 6 : 0);
                    layers[i].Opacity += (1 - Math.Exp(-Math.Abs(gain) * 5)) * coverage[i] * Motion.Smooth((phase - arrival[i]) / .75);
                }
            }
            foreach (WaterLayerPose layer in layers) {
                layer.X = Math.Max(-.18, Math.Min(.18, layer.X)); layer.Y = Math.Max(-.07, Math.Min(.07, layer.Y));
                layer.Opacity = Math.Min(.58, layer.Opacity);
            }
            return layers;
        }
        public static List<WaterRipple> Ripples(IEnumerable<Impulse> impulses)
        {
            List<WaterRipple> result = new List<WaterRipple>();
            foreach (Impulse impulse in impulses) {
                if (!impulse.Active || (impulse.Kind != ImpulseKind.Dip && impulse.Kind != ImpulseKind.Drop)) continue;
                bool drop = impulse.Kind == ImpulseKind.Drop;
                for (int i = 0; i < (drop ? 1 : 2); i++) {
                    double age = impulse.Age - i * .20, life = drop ? impulse.Duration : 1.15;
                    if (age <= 0 || age >= life) continue;
                    double radius = drop ? .025 + age * .30 : .04 + age * .92 + .20 * (1 - Math.Exp(-age * 12));
                    double envelope = drop ? (1 - Math.Exp(-age * 45)) * Math.Pow(1 - age / life, 2)
                        : (1 - Math.Exp(-age * 30)) * (1 - Math.Min(1, radius) * .35) * (1 - Motion.Smooth((radius - .88) / .20));
                    double opacity = Math.Min(.8, Math.Abs(impulse.Strength) * envelope * (drop ? 2.2 : .90) * (i == 0 ? 1 : .28));
                    if (opacity > 0) result.Add(new WaterRipple { Position = impulse.Position, Radius = radius, Opacity = opacity, IsDrop = drop });
                }
            }
            return result;
        }
    }
}
