using System;
using System.Windows.Forms;

namespace CursorWasher
{
    internal static class WidgetMenu
    {
        public static ContextMenuStrip Create(bool context, Action toggle, Action hide, Action bringToFront,
            Action sendToBack, Action quit, Action opening, Func<bool> visible, Func<bool> front)
        {
            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem visibility = Item("Hide Bucket", context ? hide : toggle);
            ToolStripMenuItem foreground = Item("Bring to Front", bringToFront);
            ToolStripMenuItem background = Item("Send to Back", sendToBack);
            if (!context) { menu.Items.Add(visibility); menu.Items.Add(new ToolStripSeparator()); }
            menu.Items.Add(foreground); menu.Items.Add(background); menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(context ? visibility : Item("Quit", quit));
            menu.Opening += delegate {
                opening();
                visibility.Text = context || visible() ? "Hide Bucket" : "Show Bucket";
                foreground.Checked = front(); background.Checked = !front();
            };
            return menu;
        }
        private static ToolStripMenuItem Item(string text, Action action)
        { ToolStripMenuItem item = new ToolStripMenuItem(text); item.Click += delegate { action(); }; return item; }
    }
}
