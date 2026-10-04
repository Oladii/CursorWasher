using System;

namespace CursorWasher
{
    internal interface ILocalCursor
    {
        void HideInWindow();
        void RestoreInWindow();
    }

    // There is deliberately no display-counter ownership here. Win32 SetCursor(NULL)
    // is applied only while our client area owns mouse input, never globally.
    internal sealed class CursorSession
    {
        private readonly ILocalCursor driver;
        public bool IsWashing { get; private set; }
        public CursorSession(ILocalCursor driver) { this.driver = driver; }
        public bool Begin(bool active, bool pointerOverBucket)
        {
            if (IsWashing || !active || !pointerOverBucket) return false;
            IsWashing = true;
            try { driver.HideInWindow(); }
            catch { IsWashing = false; driver.RestoreInWindow(); throw; }
            return true;
        }
        public bool Apply(bool active, bool pointerOverBucket)
        {
            if (!IsWashing) return false;
            if (!active || !pointerOverBucket) { Finish(); return false; }
            driver.HideInWindow();
            return true;
        }
        public void Finish()
        {
            if (!IsWashing) return;
            IsWashing = false;
            driver.RestoreInWindow();
        }
    }
}
