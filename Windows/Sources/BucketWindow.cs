using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CursorWasher
{
    internal sealed class BucketWindow : LayeredWindow, ILocalCursor
    {
        private readonly Artwork artwork;
        private CursorSprite sprite;
        private readonly SpriteWindow overlay = new SpriteWindow();
        private readonly CursorSession session;
        private readonly WashClickSequence clicks = new WashClickSequence();
        private readonly Timer timer = new Timer { Interval = 16 };
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly NotifyIcon tray;
        private Icon trayIcon;
        private readonly ContextMenuStrip menu, contextMenu;
        private WashAnimation wash;
        private SinkAnimation sink;
        private double started, scale = 1, nextSpriteRetry;
        private bool reduced, initialized, exiting, armed, dragged, suppressUp, hadFocus, resourcesDisposed, reportedMissingCursor;
        private Point pressed, originalLocation;
        private IntPtr previousForeground;
        private uint previousProcess;
        private readonly bool smoke;
        private readonly WindowSettings settings = new WindowSettings();
        public BucketWindow(bool smoke)
        {
            this.smoke = smoke;
            previousForeground = Native.GetForegroundWindow();
            Native.GetWindowThreadProcessId(previousForeground, out previousProcess);
            session = new CursorSession(this);
            artwork = new Artwork();
            ClientSize = new Size(192, 192); TopMost = true;
            AccessibleName = "CursorWasher — ведро для мытья курсора";
            AccessibleDescription = "Нажмите на ведро, чтобы помыть курсор. Потяните ведро, чтобы переместить. Escape возвращает курсор.";
            AccessibleRole = AccessibleRole.PushButton;
            KeyPreview = true;
            menu = CreateMenu(false); contextMenu = CreateMenu(true);
            trayIcon = StatusBarIcon.Create(scale);
            Icon = trayIcon;
            tray = new NotifyIcon { Icon = trayIcon, Text = "CursorWasher", ContextMenuStrip = menu, Visible = true };
            tray.MouseClick += delegate(object sender, MouseEventArgs e) {
                if (e.Button == MouseButtons.Left) menu.Show(Cursor.Position);
            };
            timer.Tick += delegate { Tick(); };
            FormClosing += delegate(object sender, FormClosingEventArgs e) {
                Stop("closing");
                if (!exiting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; HideBucket(); }
            };
        }
        private ContextMenuStrip CreateMenu(bool context)
        {
            return WidgetMenu.Create(context, delegate { if (Visible) HideBucket(); else ShowBucket(); }, HideBucket,
                delegate { SetLayer(true); }, delegate { SetLayer(false); }, Exit, delegate { Stop("menu"); },
                delegate { return Visible; }, delegate { return TopMost; });
        }
        private void SetLayer(bool front)
        {
            Stop("layer"); TopMost = front; overlay.TopMost = front;
            Native.SetWindowPos(Handle, front ? new IntPtr(-1) : new IntPtr(1), 0, 0, 0, 0, 0x13);
            SavePosition();
        }
        private void RefreshTrayIcon()
        {
            Icon previous = trayIcon; trayIcon = StatusBarIcon.Create(scale);
            Icon = trayIcon; tray.Icon = trayIcon; previous.Dispose();
        }
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (initialized) return;
            initialized = true;
            LoadPosition();
            RebuildDpi(Native.Scale(Handle));
            KeepOnScreen();
            overlay.Attach(Handle); overlay.TopMost = TopMost;
            if (!TopMost) Native.SetWindowPos(Handle, new IntPtr(1), 0, 0, 0, 0, 0x13);
            Native.WTSRegisterSessionNotification(Handle, 0);
            Render(null);
            Log.Write("ready dpi=" + scale + " safe_local_cursor=true");
#if DIAGNOSTICS
            if (smoke) SmokeProbe.Run(this, sprite, scale, Render, HideBucket);
#endif
        }
        private void RebuildDpi(double newScale)
        {
            Stop("dpi"); scale = newScale;
            RefreshTrayIcon();
            if (sprite != null) sprite.Dispose();
            sprite = null;
            TryLoadCursor();
            Size = new Size((int)Math.Round(192 * scale), (int)Math.Round(192 * scale));
        }
        private void TryLoadCursor()
        {
            try { sprite = new CursorSprite(scale); reportedMissingCursor = false; }
            catch (ArgumentException) { ReportMissingCursor(); }
            catch (InvalidOperationException) { ReportMissingCursor(); }
            // Screen-control software can temporarily replace the system arrow with
            // a transparent cursor. Show the bucket and retry, without hiding input.
            if (sprite == null) { nextSpriteRetry = clock.Elapsed.TotalSeconds + .5; timer.Start(); }
        }
        private void ReportMissingCursor()
        { if (!reportedMissingCursor) Log.Write("cursor_temporarily_unavailable"); reportedMissingCursor = true; }
        private Vec Local(Point p) { return new Vec((p.X - Left) / scale, BucketLayout.Side - (p.Y - Top) / scale); }
        private Vec Pointer()
        { Native.Point p; return Native.GetCursorPos(out p) ? Local(new Point(p.X, p.Y)) : new Vec(-1000, -1000); }
        private bool PointerOverBucket()
        {
            Native.Point p;
            return Visible && Native.GetCursorPos(out p) && artwork.Contains(Local(new Point(p.X, p.Y))) && Native.WindowFromPoint(p) == Handle;
        }
        private bool IsForeground { get { return Native.GetForegroundWindow() == Handle; } }
        private void BeginWash()
        {
            if (wash != null || sink != null || !initialized) return;
            if (sprite == null) TryLoadCursor();
            if (sprite == null) return;
            Vec point = Pointer();
            // Prepare all resources before hiding. A failed frame must never strand input.
            WashAnimation candidate = new WashAnimation(point, sprite.Shape);
            if (!session.Begin(IsForeground, PointerOverBucket())) return;
            wash = candidate; reduced = !Native.AnimationsEnabled(); started = clock.Elapsed.TotalSeconds;
            clicks.Begin(started);
            hadFocus = IsForeground; timer.Start();
            Log.Write("wash_begin"); Tick();
        }
        private Frame CurrentFrame()
        {
            double elapsed = clock.Elapsed.TotalSeconds - started;
            if (sink != null) return sink.At(elapsed);
            if (wash == null) return null;
            if (!reduced) return wash.At(elapsed, Pointer());
            double pulse = Math.Pow(Math.Sin(Math.PI * Motion.Clamp(elapsed / .8)), 2);
            Frame f = new Frame { Phase = Phase.Sparkle, Position = Pointer(), Scale = 1, Angle = 0 };
            RectangleF image = sprite.NativeImageRect;
            f.Sparkles.Add(new Particle(f.Position + new Vec(image.Right + 3, image.Top + image.Height / 2), 2.5, pulse));
            f.Sparkles.Add(new Particle(f.Position + new Vec(image.Left - 3, image.Top + 2), 2, pulse));
            return f;
        }
        private void Tick()
        {
            if (sprite == null) {
                if (clock.Elapsed.TotalSeconds >= nextSpriteRetry) TryLoadCursor();
                if (sprite != null) { Render(null); timer.Stop(); }
                return;
            }
            if (session.IsWashing && (!IsForeground || !PointerOverBucket())) Interrupt("pointer_or_focus_left");
            Frame frame = CurrentFrame();
            if (frame == null) { timer.Stop(); return; }
            double elapsed = clock.Elapsed.TotalSeconds - started;
            double duration = sink != null ? sink.Duration : reduced ? .8 : WashAnimation.Duration;
            if (elapsed >= duration) {
                bool returnFocus = wash != null && IsForeground && !smoke;
                Stop("complete");
                if (returnFocus && previousForeground != Handle && Native.IsWindow(previousForeground)) {
                    uint process; Native.GetWindowThreadProcessId(previousForeground, out process);
                    if (process == previousProcess) {
                        bool accepted = Native.SetForegroundWindow(previousForeground);
                        Log.Write("return_focus accepted=" + accepted);
                    }
                }
                return;
            }
            Render(frame);
        }
        private void Render(Frame frame)
        {
            if (!initialized) return;
            using (Bitmap image = artwork.Bucket(scale, frame)) Present(image, Location);
            if (frame == null) overlay.Hide();
            else if (sprite != null) overlay.PresentSprite(sprite, frame, scale, Location);
        }
        private void Interrupt(string reason)
        {
            if (wash == null) return;
            Frame last;
            // Restoration precedes any allocation or passive cancellation animation.
            session.Finish();
            clicks.Cancel();
            last = CurrentFrame();
            wash = null;
            if (reduced || last == null) { Stop(reason); return; }
            sink = new SinkAnimation(last, sprite.Shape); started = clock.Elapsed.TotalSeconds;
            Log.Write("cursor_restored reason=" + reason + " sinking=true");
        }
        public void Stop(string reason, bool render = true)
        {
            bool running = session.IsWashing || wash != null || sink != null;
            session.Finish(); timer.Stop(); wash = null; sink = null;
            clicks.Cancel();
            armed = false; if (Capture) Capture = false;
            overlay.Hide();
            if (running) { Log.Write("stop reason=" + reason); if (render) Render(null); }
        }
        void ILocalCursor.HideInWindow() { Native.SetCursor(IntPtr.Zero); }
        void ILocalCursor.RestoreInWindow()
        {
            // Do not overwrite a cursor already chosen by another window.
            if (Native.GetCursor() == IntPtr.Zero) Native.SetCursor(sprite != null ? sprite.Handle : Cursors.Arrow.Handle);
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x21) { // Capture the prior app before Windows activates us.
                IntPtr foreground = Native.GetForegroundWindow();
                if (foreground != IntPtr.Zero && foreground != Handle) {
                    previousForeground = foreground; Native.GetWindowThreadProcessId(foreground, out previousProcess);
                }
            }
            if (m.Msg == 0x20 && initialized) { // WM_SETCURSOR
                if (session.Apply(IsForeground, PointerOverBucket())) { m.Result = new IntPtr(1); return; }
                if (wash != null) Interrupt("cursor_left");
                Native.SetCursor(sprite != null ? sprite.Handle : Cursors.Arrow.Handle); m.Result = new IntPtr(1); return;
            }
            if (initialized && m.Msg == 0x02E0) { // WM_DPICHANGED
                Native.Rect rect = (Native.Rect)Marshal.PtrToStructure(m.LParam, typeof(Native.Rect));
                RebuildDpi((m.WParam.ToInt64() & 0xffff) / 96.0);
                Location = new Point(rect.Left, rect.Top); KeepOnScreen(); Render(null); m.Result = IntPtr.Zero; return;
            }
            if (initialized && (m.Msg == 0x7E || m.Msg == 0x1A)) { // display / settings
                Stop("display_or_settings");
                if (m.Msg == 0x7E) KeepOnScreen();
                RebuildDpi(Native.Scale(Handle)); Render(null);
            }
            if (initialized && m.Msg == 0x31A) RefreshTrayIcon(); // WM_THEMECHANGED
            if (initialized && (m.Msg == 0x218 || m.Msg == 0x2B1 || m.Msg == 0x11 || m.Msg == 0x16)) Stop("power_or_session");
            if (m.Msg == 0x1F && initialized) Stop("cancel_mode");
            base.WndProc(ref m);
        }
        protected override void OnActivated(EventArgs e) { base.OnActivated(e); hadFocus = true; }
        protected override void OnDeactivate(EventArgs e)
        { base.OnDeactivate(e); if (initialized && hadFocus) Interrupt("deactivated"); armed = false; if (Capture) Capture = false; }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (initialized) Interrupt("pointer_left"); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right) { Stop("context_menu"); contextMenu.Show(this, e.Location); return; }
            if (e.Button != MouseButtons.Left) return;
            if (wash != null || sink != null) {
                suppressUp = true; Capture = false;
                if (!clicks.ConsumeInitialDoubleClick(e.Clicks, clock.Elapsed.TotalSeconds, SystemInformation.DoubleClickTime / 1000.0)) Interrupt("repeat_click");
                return;
            }
            suppressUp = false; armed = true; dragged = false;
            pressed = Cursor.Position; originalLocation = Location;
            Capture = true;
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!armed) return;
            Point p = Cursor.Position;
            int dx = p.X - pressed.X, dy = p.Y - pressed.Y;
            if (!dragged && Math.Sqrt(dx * dx + dy * dy) >= 4 * scale) dragged = true;
            if (dragged) Location = new Point(originalLocation.X + dx, originalLocation.Y + dy);
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            bool begin = armed && !dragged && !suppressUp;
            bool moved = dragged;
            armed = false; Capture = false; suppressUp = false;
            if (moved) { KeepOnScreen(); SavePosition(); }
            if (begin) BeginWash();
        }
        protected override void OnMouseCaptureChanged(EventArgs e)
        { base.OnMouseCaptureChanged(e); if (!Capture) armed = false; }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == Keys.Escape) { Stop("escape"); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }
        private void HideBucket() { Stop("hidden"); Hide(); }
        public void Reopen() { if (!initialized) return; SetLayer(true); ShowBucket(); }
        private void ShowBucket()
        {
            KeepOnScreen(); Show();
            if (!TopMost) Native.SetWindowPos(Handle, new IntPtr(1), 0, 0, 0, 0, 0x13);
            Render(null); if (sprite == null) timer.Start();
        }
        private void CenterBucket()
        { Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea; Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2); }
        private void KeepOnScreen()
        { Rectangle area = Screen.FromRectangle(Bounds).WorkingArea; Location = new Point(Math.Max(area.Left, Math.Min(Left, area.Right - Width)), Math.Max(area.Top, Math.Min(Top, area.Bottom - Height))); }
        private void LoadPosition()
        {
            CenterBucket();
            if (smoke) return;
            Point location; bool topMost;
            if (settings.TryRead(out location, out topMost)) { Location = location; TopMost = topMost; }
        }
        private void SavePosition()
        {
            if (smoke || !initialized) return;
            settings.Write(Location, TopMost);
        }
        public void Exit() { exiting = true; Stop("exit"); SavePosition(); Close(); }
        protected override void Dispose(bool disposing)
        {
            if (disposing && !resourcesDisposed) {
                resourcesDisposed = true;
                session.Finish(); timer.Dispose();
                if (IsHandleCreated) Native.WTSUnRegisterSessionNotification(Handle);
                tray.Visible = false; tray.Dispose(); menu.Dispose(); contextMenu.Dispose(); overlay.Dispose(); trayIcon.Dispose();
                if (sprite != null) sprite.Dispose(); artwork.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
