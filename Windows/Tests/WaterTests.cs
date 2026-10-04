using System;
using System.Drawing;

namespace CursorWasher
{
    internal static class WaterTests
    {
        public static void Run(Action<bool, string> check)
        {
            Vec center = new Vec(98, 117.5);
            foreach (ImpulseKind kind in Enum.GetValues(typeof(ImpulseKind))) {
                Impulse impulse = new Impulse(center, .13, .4, kind);
                foreach (double age in new[] { -1.0, 0, impulse.Duration, impulse.Duration + 1 }) {
                    impulse.Age = age;
                    check(WaterMotion.Ripples(new[] { impulse }).Count == 0, "Inactive water impulses produce no rings");
                    foreach (WaterLayerPose p in WaterMotion.Layers(new[] { impulse })) check(p.X == 0 && p.Y == 0 && p.Opacity == 0, "Inactive water is still");
                }
                for (int step = 1; step < 200; step++) {
                    impulse.Age = step / 200.0 * impulse.Duration;
                    WaterLayerPose[] a = WaterMotion.Layers(new[] { impulse }), b = WaterMotion.Layers(new[] { impulse });
                    for (int i = 0; i < 3; i++) check(a[i].X == b[i].X && a[i].Rotation == b[i].Rotation && Math.Abs(a[i].X) <= .18
                        && Math.Abs(a[i].Y) <= .07 && a[i].Opacity >= 0 && a[i].Opacity <= .58, "Mac water motion is deterministic and bounded");
                    foreach (WaterRipple r in WaterMotion.Ripples(new[] { impulse })) check((r.Position - center).Length == 0 && r.Radius > 0 && r.Opacity > 0 && r.Opacity <= .8, "Rings keep their impact point");
                }
            }
            Impulse right = new Impulse(center, 1e-6, .4, ImpulseKind.Stir) { Rotation = -2.5 };
            Impulse left = right.Advance(0, 1); left.Direction = Math.PI;
            WaterLayerPose[] rightLayers = WaterMotion.Layers(new[] { right }), leftLayers = WaterMotion.Layers(new[] { left });
            for (int i = 0; i < 3; i++) check(rightLayers[i].X > 0 && leftLayers[i].X < 0 && Math.Abs(rightLayers[i].X + leftLayers[i].X) < 1e-10
                && rightLayers[i].Opacity == leftLayers[i].Opacity, "The paint follows stirring direction, not just rotation");
            check(Math.Abs(rightLayers[0].Rotation) < Math.Abs(rightLayers[2].Rotation) / 4, "Outer paint rotates more slowly");
            right.Rotation = -.2; WaterLayerPose[] first = WaterMotion.Layers(new[] { right });
            check(first[2].Opacity > 0 && first[1].Opacity == 0 && first[0].Opacity == 0, "Disturbance starts at the center");
            right.Rotation = -.9; first = WaterMotion.Layers(new[] { right });
            check(first[1].Opacity > 0 && first[0].Opacity == 0, "Disturbance spreads gradually to the rim");
            Impulse dip = new Impulse(center, .35, 1);
            var rings = WaterMotion.Ripples(new[] { dip });
            check(rings.Count == 2 && rings[0].Radius > rings[1].Radius && rings[1].Opacity < rings[0].Opacity * .4, "Dip produces one crest and a quiet echo");
            dip.Age = .72; WaterRipple approaching = WaterMotion.Ripples(new[] { dip })[0];
            dip.Age = .85; WaterRipple crossing = WaterMotion.Ripples(new[] { dip })[0];
            check(crossing.Radius > 1 && crossing.Radius > approaching.Radius + .1 && crossing.Opacity < approaching.Opacity, "Ring keeps travelling and fades through the rim");
            dip.Age = 1.15; check(WaterMotion.Ripples(new[] { dip }).Count == 0, "No wave lingers at the rim");

            using (Artwork artwork = new Artwork()) using (CursorSprite sprite = new CursorSprite(1.5))
            using (Bitmap calm = ImageResources.Load("water-calm-source.png")) using (Bitmap highlights = ImageResources.Load("water-highlights-source.png"))
            using (WaterSurface water = new WaterSurface(calm, highlights, artwork.WaterPath)) {
                WashAnimation animation = new WashAnimation(new Vec(98, 85), sprite.Shape);
                bool firstContact = false;
                for (double time = .49; time < .69; time += .01) {
                    Frame f = animation.At(time, center);
                    if (f.Immersion == null && f.Impulses.Exists(delegate(Impulse x) { return x.Kind == ImpulseKind.Contact && x.Active; })) firstContact = true;
                }
                check(firstContact, "Water reacts to first contact before rounded cursor immersion exists");
                Frame wash = animation.At(1.55, center), rise = animation.At(2.3, center), settling = animation.At(2.7, center);
                Impulse a = rise.Impulses.Find(delegate(Impulse x) { return x.Kind == ImpulseKind.Stir; });
                Impulse b = settling.Impulses.Find(delegate(Impulse x) { return x.Kind == ImpulseKind.Stir; });
                check(a != null && b != null && b.Strength > 0 && b.Rotation < a.Rotation, "Water retains its momentum after the cursor leaves");
                SinkAnimation sink = new SinkAnimation(wash, sprite.Shape); Frame sunk = sink.At(.08);
                for (int i = 0; i < wash.Impulses.Count; i++) check(sunk.Impulses[i].Kind == wash.Impulses[i].Kind
                    && sunk.Impulses[i].Rotation == wash.Impulses[i].Rotation && Math.Abs(sunk.Impulses[i].Age - wash.Impulses[i].Age - .08) < 1e-10,
                    "Cancellation ages all water impulses without inventing new spin");
                using (Bitmap basis = (Bitmap)water.Frame(new Impulse[0]).Clone()) {
                    foreach (Frame f in new[] { animation.At(.64, center), wash, settling, sunk }) {
                        Bitmap rendered = water.Frame(f.Impulses); bool alphaSame = true; int changed = 0;
                        for (int y = 0; y < 256; y++) for (int x = 0; x < 256; x++) {
                            Color before = basis.GetPixel(x, y), after = rendered.GetPixel(x, y);
                            if (before.A != after.A) alphaSame = false;
                            if (before.ToArgb() != after.ToArgb()) changed++;
                        }
                        check(alphaSame, "Every alpha byte of the original watercolor is preserved");
                        check(changed > 20, "Contact/stirring/settling changes actual water pixels");
                    }
                    Bitmap disabled = water.Frame(wash.Impulses, false); bool identical = true;
                    for (int y = 0; y < 256; y++) for (int x = 0; x < 256; x++) if (basis.GetPixel(x, y) != disabled.GetPixel(x, y)) identical = false;
                    check(identical, "Disabling crests returns the original painting without re-coloring it");
                }
            }
            using (Bitmap basis = new Bitmap(3, 1, System.Drawing.Imaging.PixelFormat.Format32bppPArgb))
            using (Bitmap ink = new Bitmap(3, 1, System.Drawing.Imaging.PixelFormat.Format32bppPArgb)) {
                basis.SetPixel(1, 0, Color.FromArgb(128, 0, 0, 255)); basis.SetPixel(2, 0, Color.Blue);
                for (int x = 0; x < 3; x++) ink.SetPixel(x, 0, Color.FromArgb(128, 255, 0, 0));
                using (Bitmap result = WaterSurface.CompositeAtop(basis, ink)) {
                    check(result.GetPixel(0, 0).A == 0, "Paint never fills transparent water pixels");
                    Color mixed = result.GetPixel(1, 0);
                    check(mixed.A == 128 && Math.Abs(mixed.R - 128) <= 2 && Math.Abs(mixed.B - 127) <= 2, "SourceAtop matches the analytical half-red/half-blue result");
                    check(result.GetPixel(2, 0).A == 255, "SourceAtop also preserves opaque alpha");
                }
            }
        }
    }
}
