using System;
using System.Diagnostics;
using System.Windows.Forms;

namespace CursorWasher
{
    internal static class SmokeProbe
    {
        public static void Run(BucketWindow window, CursorSprite sprite, double scale, Action<Frame> render, Action hideBucket)
        {
            using (Process process = Process.GetCurrentProcess()) {
                IntPtr foreground = Native.GetForegroundWindow();
                if (sprite == null) throw new InvalidOperationException("Smoke test needs a visible system arrow.");
                WashAnimation preview = new WashAnimation(new Vec(98, 85), sprite.Shape);
                render(preview.At(.30, new Vec(98, 85)));
                VerifyPassiveFocus(foreground, process.Id);
                uint before = Native.GetGuiResources(process.Handle, 0);
                Stopwatch rendering = Stopwatch.StartNew();
                for (int i = 0; i < 90; i++) {
                    foreground = Native.GetForegroundWindow();
                    render(preview.At(i * WashAnimation.Duration / 90, new Vec(98, 85)));
                    VerifyPassiveFocus(foreground, process.Id);
                }
                uint after = Native.GetGuiResources(process.Handle, 0);
                Log.Write("smoke_render average_ms=" + (rendering.Elapsed.TotalMilliseconds / 90).ToString("F2", System.Globalization.CultureInfo.InvariantCulture));
                if (after > before + 3) throw new InvalidOperationException("GDI resources grew across repeated animation frames: " + before + " -> " + after);
                render(preview.At(1.55, new Vec(98, 85)));
                Native.Point water = new Native.Point(window.Left + (int)(98 * scale), window.Top + (int)(74 * scale));
                if (Native.WindowFromPoint(water) != window.Handle) throw new InvalidOperationException("Passive cursor surface intercepted the bucket input.");
                Native.Point margin = new Native.Point(window.Left + 3, window.Top + 3);
                if (Native.WindowFromPoint(margin) == window.Handle) throw new InvalidOperationException("Transparent margin intercepted desktop input.");
                render(null);
                hideBucket();
                using (System.Threading.EventWaitHandle signal = System.Threading.EventWaitHandle.OpenExisting(Program.ReopenEventName)) signal.Set();
                Log.Write("smoke_pass focus_and_hit_testing gdi=" + before + "->" + after);
                Timer smokeTimer = new Timer { Interval = 800 };
                smokeTimer.Tick += delegate {
                    smokeTimer.Stop(); smokeTimer.Dispose();
                    if (!window.Visible) throw new InvalidOperationException("The second-instance signal did not reopen the bucket.");
                    Log.Write("smoke_pass layered_window_and_tray instance_signal_reopens_bucket"); window.Exit();
                };
                window.Disposed += delegate { smokeTimer.Dispose(); };
                smokeTimer.Start();
            }
        }
        private static void VerifyPassiveFocus(IntPtr before, int currentProcessId)
        {
            IntPtr after = Native.GetForegroundWindow();
            uint process; Native.GetWindowThreadProcessId(after, out process);
            // The user may switch their own apps while the probe runs. Only a
            // transition into our process indicates the overlay stole focus.
            if (after != before && process == (uint)currentProcessId)
                throw new InvalidOperationException("Passive animation stole focus.");
        }
    }
}
