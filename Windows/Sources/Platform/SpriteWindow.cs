using System;
using System.Drawing;
using System.Windows.Forms;

namespace CursorWasher
{
    // A native HWND avoids WinForms' implicit owner activation during Form handle
    // creation. No control, form visibility or input-focus lifecycle is involved.
    internal sealed class SpriteWindow : NativeWindow, IDisposable
    {
        public bool TopMost { get; set; }
        public void Attach(IntPtr owner)
        {
            CreateHandle(new CreateParams {
                Caption = "CursorWasher animation", Parent = owner,
                Style = unchecked((int)0x80000000), ExStyle = 0x080800A0,
                Width = 1, Height = 1
            });
        }
        public void PresentSprite(CursorSprite sprite, Frame frame, double scale, Point bucketOrigin)
        {
            Point offset;
            using (Bitmap image = CursorRenderer.RenderSurface(sprite, frame, scale, out offset))
                LayeredWindow.PresentTo(Handle, image, new Point(bucketOrigin.X + offset.X, bucketOrigin.Y + offset.Y));
            // Form.Show() may activate an owner even with ShowWithoutActivation.
            // Keep this passive HWND out of the Forms visibility/activation path.
            Native.SetWindowPos(Handle, new IntPtr(TopMost ? -1 : -2), 0, 0, 0, 0, 0x0010 | 0x0001 | 0x0002 | 0x0040);
        }
        public void Hide() { if (Handle != IntPtr.Zero) Native.ShowWindow(Handle, 0); }
        public void Dispose() { if (Handle != IntPtr.Zero) DestroyHandle(); }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x21) { m.Result = new IntPtr(3); return; }
            base.WndProc(ref m);
        }
    }
}
