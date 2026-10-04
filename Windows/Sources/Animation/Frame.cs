using System;
using System.Collections.Generic;

namespace CursorWasher
{
    internal enum Phase { Approach, PartialDip, DipLift, Dive, Wash, Rise, Shake, Turn, Sparkle, Returning }
    internal sealed class Particle
    {
        public Vec Position;
        public Vec Velocity;
        public int Variant;
        public double Radius, Opacity;
        public Particle(Vec p, double radius, double opacity) { Position = p; Radius = radius; Opacity = opacity; }
        public double Stretch { get { return 1 + Math.Min(1, Velocity.Length / 700) * (.7 - .12 * (Variant % 3)); } }
        public double Width { get { return Radius * 2 / Math.Sqrt(Stretch); } }
        public double Height { get { return Radius * 2 * Math.Sqrt(Stretch); } }
    }
    internal sealed class Frame
    {
        public Phase Phase;
        public Vec Position;
        public double Scale = 1, Angle = Math.PI;
        public double? Waterline;
        public Immersion Immersion;
        public bool ShadowVisible = true;
        public readonly List<Particle> Drops = new List<Particle>();
        public readonly List<Particle> Sparkles = new List<Particle>();
        public readonly List<Impulse> Impulses = new List<Impulse>();
    }
}
