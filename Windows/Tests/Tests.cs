using System;
using System.Collections.Generic;

namespace CursorWasher
{
    internal static class Tests
    {
        private sealed class FakeCursor : ILocalCursor
        {
            public int Hides, Restores;
            public void HideInWindow() { Hides++; }
            public void RestoreInWindow() { Restores++; }
        }
        private static int checks;
        private static void Check(bool condition, string message)
        { checks++; if (!condition) throw new Exception(message); }
        [STAThread]
        public static int Main()
        {
            try {
                FakeCursor driver = new FakeCursor(); CursorSession session = new CursorSession(driver);
                WashClickSequence clicks = new WashClickSequence();
                clicks.Begin(1);
                Check(clicks.ConsumeInitialDoubleClick(2, 1.2, .5), "The second press of the starting double click continues washing");
                Check(!clicks.ConsumeInitialDoubleClick(2, 1.3, .5), "A further double click is a cancellation");
                clicks.Begin(2); Check(!clicks.ConsumeInitialDoubleClick(2, 2.6, .5), "Late double click cancels");
                clicks.Begin(3); Check(!clicks.ConsumeInitialDoubleClick(1, 3.1, .5), "Repeat single click cancels");
                clicks.Begin(4); clicks.Cancel(); Check(!clicks.ConsumeInitialDoubleClick(2, 4.1, .5), "Cancelled sequence cannot swallow a click");
                Immersion rounded = new Immersion(new Vec(100, 110), 5, 1.35);
                Check(Math.Abs(rounded.LowerEdge(100) - 108.65) < .000001, "Rounded immersion retains the submerged center");
                Check(rounded.LowerEdge(95) == 110 && rounded.LowerEdge(105) == 110, "Immersion joins the waterline at both ends");
                Particle moving = new Particle(new Vec(), 3, 1) { Velocity = new Vec(250, -600), Variant = 1 };
                Check(moving.Height > moving.Width && Math.Abs(moving.Width * moving.Height - 36) < .000001, "Fast drops stretch while preserving area");
                Check(!session.Begin(false, true) && !session.Begin(true, false), "Refuse inactive / outside starts");
                Check(driver.Hides == 0 && driver.Restores == 0, "Refused starts do not touch cursor");
                for (int i = 0; i < 500; i++) {
                    Check(session.Begin(true, true), "Begin cycle");
                    Check(!session.Begin(true, true), "Duplicate start refused");
                    Check(session.Apply(true, true), "Local cursor message remains hidden");
                    Check(!session.Apply(i % 2 == 0, i % 2 != 0), "Either leaving or losing focus restores");
                    session.Finish(); session.Finish();
                    Check(!session.IsWashing && driver.Restores == i + 1, "Cleanup is idempotent");
                }
                List<Vec> samples = new List<Vec>();
                for (int y = -20; y <= 0; y++) for (int x = 0; x <= Math.Min(-y, 12); x++) samples.Add(new Vec(x, y));
                CursorShape shape = new CursorShape(samples);
                CheckCursorSize(samples);
                Check(Math.Abs(WashAnimation.Duration - 4.46) < .00001, "Mac duration retained");
                for (int x = 35; x < 160; x += 25) for (int y = 35; y < 160; y += 25) {
                    Vec start = new Vec(x, y), target = new Vec(109, 83);
                    WashAnimation wash = new WashAnimation(start, shape);
                    Check((wash.At(0, target).Position - start).Length < .0001, "Animation starts at real hotspot");
                    Frame last = wash.At(WashAnimation.Duration, target);
                    Check((last.Position - target).Length < .0001 && last.Scale == 1 && last.Angle == 0, "Return exactly to current hotspot");
                    foreach (double boundary in WashAnimation.Starts) {
                        if (boundary == 0) continue;
                        Frame before = wash.At(boundary - .000001, target), after = wash.At(boundary, target);
                        Check((before.Position - after.Position).Length < .02, "Position continuous at phase " + after.Phase);
                        Check(Math.Abs(before.Angle - after.Angle) < .001, "Angle continuous at phase " + after.Phase);
                        Check(Math.Abs(before.Scale - after.Scale) < .001, "Size continuous at phase " + after.Phase);
                    }
                    for (double t = 0; t <= WashAnimation.Duration; t += .037) {
                        Frame f = wash.At(t, target);
                        Check(!double.IsNaN(f.Position.X + f.Position.Y + f.Scale + f.Angle), "Finite trajectory");
                        foreach (Impulse impulse in f.Impulses) Check(!double.IsNaN(impulse.Strength + impulse.Rotation + impulse.Direction), "Finite water state");
                        SinkAnimation sink = new SinkAnimation(f, shape);
                        Check((sink.At(0).Position - f.Position).Length < .001, "Cancellation has no jump");
                        Frame sunk = sink.At(sink.Duration);
                        Check(sunk.Waterline.HasValue && sunk.Position.Y + shape.Bounds(sunk.Scale, sunk.Angle).Bottom < sunk.Waterline.Value, "Cancelled cursor fully submerged");
                        Frame impact = sink.At(sink.ImpactAt);
                        double depth = f.Immersion == null ? 0 : f.Immersion.Depth;
                        Check(impact.Position.Y + shape.PixelBounds(impact.Scale, impact.Angle).Bottom <= impact.Waterline.Value - depth + .002, "Cancellation splash starts at actual opaque pixel submersion");
                    }
                }
                CheckMenus();
                CursorRasterTests.Run(Check);
                WaterTests.Run(Check);
                CursorFileTests.Run(Check);
                using (System.Drawing.Bitmap blackIcon = StatusBarIcon.Render(36, System.Drawing.Color.Black))
                using (System.Drawing.Bitmap whiteIcon = StatusBarIcon.Render(36, System.Drawing.Color.White)) {
                    Check(blackIcon.GetPixel(0, 0).A == 0, "Status SVG keeps transparent corners");
                    int visiblePixels = 0;
                    for (int y = 0; y < 36; y++) for (int x = 0; x < 36; x++) {
                        System.Drawing.Color a = blackIcon.GetPixel(x, y), b = whiteIcon.GetPixel(x, y);
                        Check(a.A == b.A, "Tray theme changes color without changing the Mac contours");
                        if (a.A > 128) visiblePixels++;
                    }
                    Check(visiblePixels > 150 && visiblePixels < 600, "Mac status SVG has visible bucket and cursor outlines");
                }
                using (Artwork artwork = new Artwork()) {
                    Check(artwork.Contains(new Vec(98, 85)), "Painted bucket is interactive");
                    Check(artwork.Contains(new Vec(98, 118)), "Water is interactive");
                    Check(!artwork.Contains(new Vec(10, 10)), "Transparent margin is not interactive");
                    foreach (double dpi in new[] { 1.0, 1.25, 1.5, 2.0 }) {
                        using (CursorSprite native = new CursorSprite(dpi)) {
                            Check(native.Shape.Samples.Count > 0, "Native cursor rasterizes at DPI " + dpi);
                            System.Drawing.RectangleF body = native.Shape.Bounds(1, 0);
                            Check(body.Width > 0 && body.Height > 0, "Detailed cursor retains native logical dimensions");
                            WashAnimation wash = new WashAnimation(new Vec(98, 85), native.Shape);
                            CheckMacSize(native.Shape, wash);
                            foreach (double dipTime in new[] { .60, .68, .87, 1.03 }) {
                                Frame dip = wash.At(dipTime, new Vec(98, 85));
                                Vec visibleCenter = dip.Position + native.Shape.VisibleCenter.Transform(dip.Scale, dip.Angle);
                                Check(Math.Abs(visibleCenter.X - (96.5 + 2.6715410666)) < .0001, "Visible pixels keep the requested one-point left offset at DPI " + dpi);
                                foreach (Impulse impulse in dip.Impulses) if (impulse.Kind == ImpulseKind.Dip)
                                    Check(Math.Abs(impulse.Position.X - 97.5) < .0001 && impulse.Position.Y == 110.5, "Dip splashes retain Mac coordinates, independently of cursor shape");
                            }
                            for (int step = 0; step <= 30; step++) {
                                Frame rising = wash.At(WashAnimation.Starts[(int)Phase.Rise] + WashAnimation.Durations[(int)Phase.Rise] * step / 30, new Vec(98, 85));
                                Vec center = rising.Position + native.Shape.VisibleCenter.Transform(rising.Scale, rising.Angle);
                                Check(Math.Abs(center.X - (96.5 + 2.6715410666)) < .0001, "The visible center rises along a fixed vertical axis throughout rotation");
                            }
                            for (int step = 0; step <= 30; step++) {
                                Frame shaking = wash.At(WashAnimation.Starts[(int)Phase.Shake] + WashAnimation.Durations[(int)Phase.Shake] * step / 30, new Vec(98, 85));
                                Check(Math.Abs(shaking.Position.X - wash.Hover(Math.PI).X) < .0001 && shaking.Angle == Math.PI,
                                    "No horizontal movement or extra rotation through the upper shake");
                            }
                            double previousAngle = Math.PI;
                            for (int step = 0; step <= 60; step++) {
                                Frame turning = wash.At(WashAnimation.Starts[(int)Phase.Turn] + WashAnimation.Durations[(int)Phase.Turn] * step / 60, new Vec(98, 85));
                                Check(turning.Angle >= 0 && turning.Angle <= previousAngle, "Return turn is monotonic and never overshoots upright");
                                previousAngle = turning.Angle;
                                Vec center = turning.Position + native.Shape.VisibleCenter.Transform(turning.Scale, turning.Angle);
                                Frame still = wash.At(WashAnimation.Starts[(int)Phase.Sparkle], new Vec(98, 85));
                                Vec resting = still.Position + native.Shape.VisibleCenter.Transform(still.Scale, still.Angle);
                                Check((center - resting).Length < .0001, "The entire reverse turn uses the same stationary pivot as the sparkle phase");
                            }
                            CursorTrajectoryTests.CheckRenderedPivot(Check, native, wash, dpi);
                            foreach (double time in new[] { 0.0, .65, 1.55, 2.7, 3.5, 4.2 }) {
                                Frame frame = wash.At(time, new Vec(98, 85));
                                using (System.Drawing.Bitmap image = artwork.Bucket(dpi, frame)) {
                                    Check(image.Width == (int)Math.Round(192 * dpi), "DPI pixel dimensions");
                                    Check(image.GetPixel(0, 0).A == 0, "Per-pixel transparent corner");
                                    Check(image.GetPixel((int)(98 * dpi), (int)(107 * dpi)).A > 100, "Bucket remains visible");
                                }
                            }
                            Frame immersed = wash.At(1.55, new Vec(98, 85));
                            Check(immersed.Immersion != null, "Washing has a rounded water contact at every DPI");
                            immersed.Drops.Clear(); immersed.Sparkles.Clear();
                            using (System.Drawing.Bitmap image = new System.Drawing.Bitmap(192, 192)) {
                                using (System.Drawing.Graphics g = SceneGraphics.Create(image, 1)) CursorRenderer.Draw(g, native, immersed);
                                int below = (int)Math.Ceiling(192 - immersed.Waterline.Value + immersed.Immersion.Depth + 1);
                                bool clean = true;
                                for (int y = below; y < 192; y++) for (int x = 0; x < 192; x++) if (image.GetPixel(x, y).A != 0) clean = false;
                                Check(clean, "No cursor pixels leak below the water mask");
                            }
                        }
                    }
                }
                Console.WriteLine("PASS: " + checks + " cursor recovery, Mac water, alpha, CUR/ANI sources, alignment, menus and rendering assertions."); return 0;
            } catch (Exception e) { Console.Error.WriteLine(e); return 1; }
        }
        private static void CheckMacSize(CursorShape shape, WashAnimation wash)
        {
            Frame frame = wash.At(WashAnimation.Starts[(int)Phase.Sparkle], new Vec(98, 85));
            System.Drawing.RectangleF body = shape.Bounds(frame.Scale, frame.Angle);
            Check(body.Width <= 26.521 && body.Height <= 44.116, "Animated cursor fits the visually adjusted Mac bounds");
            Check(Math.Abs(body.Width - 26.52) < .001 || Math.Abs(body.Height - 44.115) < .001, "Visual size adjustment is independent of native cursor size");
            System.Drawing.RectangleF native = shape.Bounds(1, 0);
            Check(Math.Abs(body.Width / body.Height - native.Width / native.Height) < .0001, "Sizing preserves the system arrow's proportions");
        }
        private static void CheckCursorSize(List<Vec> samples)
        {
            // Include larger accessibility cursors and both wider/taller arrow shapes.
            foreach (double size in new[] { .5, 1.0, 2.0, 4.0 }) foreach (double width in new[] { .7, 1.0, 1.5 }) {
                CursorShape shape = new CursorShape(samples.ConvertAll(delegate(Vec p) { return new Vec((p.X * width - 2) * size, (p.Y + 3) * size); }));
                Vec start = new Vec(80, 90), target = new Vec(109, 83);
                WashAnimation wash = new WashAnimation(start, shape);
                CheckMacSize(shape, wash);
                CursorTrajectoryTests.CheckPath(Check, shape, wash);
                Frame first = wash.At(0, target), last = wash.At(WashAnimation.Duration, target);
                Check(first.Scale == 1 && first.Angle == 0 && (first.Position - start).Length < .0001, "Capture retains the real cursor's size and hotspot");
                Check(last.Scale == 1 && last.Angle == 0 && (last.Position - target).Length < .0001, "Return retains the real cursor's size and hotspot for every source size");
                foreach (double boundary in WashAnimation.Starts) if (boundary > 0) {
                    Frame before = wash.At(boundary - .000001, target), after = wash.At(boundary, target);
                    Check((before.Position - after.Position).Length < .02 && Math.Abs(before.Scale - after.Scale) < .001, "No size or position jump with a different source size");
                }
            }
        }
        private static void CheckMenus()
        {
            int front = 0, back = 0, hidden = 0, toggled = 0, quit = 0;
            foreach (bool context in new[] { false, true })
                using (System.Windows.Forms.ContextMenuStrip menu = WidgetMenu.Create(context, delegate { toggled++; }, delegate { hidden++; },
                    delegate { front++; }, delegate { back++; }, delegate { quit++; }, delegate { }, delegate { return true; }, delegate { return true; })) {
                    string[] expected = context ? new[] { "Bring to Front", "Send to Back", "-", "Hide Bucket" }
                        : new[] { "Hide Bucket", "-", "Bring to Front", "Send to Back", "-", "Quit" };
                    Check(menu.Items.Count == expected.Length, "Only Mac menu actions are present");
                    for (int i = 0; i < expected.Length; i++) {
                        bool separator = menu.Items[i] is System.Windows.Forms.ToolStripSeparator;
                        Check(separator ? expected[i] == "-" : menu.Items[i].Text == expected[i], "Mac context/tray menu order");
                        if (!separator) menu.Items[i].PerformClick();
                    }
                }
            Check(front == 2 && back == 2 && hidden == 1 && toggled == 1 && quit == 1, "Each Mac menu command invokes the matching action");
        }
    }
}
