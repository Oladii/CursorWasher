using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CursorWasher
{
    internal class LayeredWindow : Form
    {
        public LayeredWindow()
        {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual; AutoScaleMode = AutoScaleMode.None;
            Text = "CursorWasher";
#if INSPECTION
            // Only the inspection build exposes a taskbar window so UI inspection
            // tools that omit tool windows can target the real widget.
            ShowInTaskbar = true;
#endif
        }
        protected override CreateParams CreateParams
        {
            get {
                CreateParams p = base.CreateParams; p.ExStyle |= 0x80000 | 0x80;
#if INSPECTION
                p.ExStyle &= ~0x80;
#endif
                return p;
            }
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        public void Present(Bitmap bitmap, Point destination)
        { PresentTo(Handle, bitmap, destination); }
        internal static void PresentTo(IntPtr window, Bitmap bitmap, Point destination)
        {
            IntPtr screen = Native.GetDC(IntPtr.Zero), memory = IntPtr.Zero, handle = IntPtr.Zero, previous = IntPtr.Zero;
            try {
                memory = Native.CreateCompatibleDC(screen);
                handle = bitmap.GetHbitmap(Color.FromArgb(0));
                previous = Native.SelectObject(memory, handle);
                Native.Point target = new Native.Point(destination.X, destination.Y), source = new Native.Point(0, 0);
                Native.Size size = new Native.Size(bitmap.Width, bitmap.Height);
                Native.Blend blend = new Native.Blend { Operation = 0, Flags = 0, Alpha = 255, Format = 1 };
                if (!Native.UpdateLayeredWindow(window, screen, ref target, ref size, memory, ref source, 0, ref blend, 2)) throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally {
                if (previous != IntPtr.Zero) Native.SelectObject(memory, previous);
                if (handle != IntPtr.Zero) Native.DeleteObject(handle);
                if (memory != IntPtr.Zero) Native.DeleteDC(memory);
                if (screen != IntPtr.Zero) Native.ReleaseDC(IntPtr.Zero, screen);
            }
        }
    }
}
