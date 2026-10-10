using System;
using System.Threading;
using System.Windows.Forms;

namespace CursorWasher
{
    internal static class Program
    {
        internal const string ReopenEventName = @"Local\CursorWasher.Windows.Reopen";
        [STAThread]
        public static int Main(string[] args)
        {
            bool smoke = false;
#if DIAGNOSTICS
            smoke = Array.IndexOf(args, "--smoke") >= 0;
#endif
            try {
#if DIAGNOSTICS
                if (args.Length == 2 && args[0] == "--render-preview") { PreviewRenderer.Render(args[1]); return 0; }
#endif
                bool created;
                using (EventWaitHandle reopen = new EventWaitHandle(false, EventResetMode.AutoReset, ReopenEventName))
                using (Mutex mutex = new Mutex(true, @"Local\CursorWasher.Windows.SafeMode", out created)) {
                    if (!created) { if (smoke) return 1; reopen.Set(); return 0; }
                    Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                    Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                    using (BucketWindow window = new BucketWindow(smoke)) {
                        ThreadExceptionEventHandler handler = delegate(object sender, ThreadExceptionEventArgs e) {
                            window.Stop("exception", false); Log.Write("error " + e.Exception); Environment.ExitCode = 1;
                            if (!smoke) MessageBox.Show("Не удалось продолжить анимацию. Курсор возвращён. " + e.Exception.Message, "CursorWasher");
                            window.Exit();
                        };
                        Application.ThreadException += handler;
                        RegisteredWaitHandle listener = null;
                        window.Shown += delegate {
                            listener = ThreadPool.RegisterWaitForSingleObject(reopen, delegate {
                                try { window.BeginInvoke(new Action(window.Reopen)); }
                                catch (InvalidOperationException) { /* Window is closing. */ }
                            }, null, Timeout.Infinite, false);
                        };
                        try { Application.Run(window); }
                        finally { if (listener != null) listener.Unregister(null); Application.ThreadException -= handler; if (!window.IsDisposed) window.Stop("finally", false); }
                    }
                    mutex.ReleaseMutex();
                }
                return Environment.ExitCode;
            } catch (Exception ex) {
                Log.Write("fatal " + ex);
                if (!smoke && args.Length == 0) MessageBox.Show("Не удалось запустить CursorWasher. " + ex.Message, "CursorWasher");
                return 1;
            }
        }
    }
}
