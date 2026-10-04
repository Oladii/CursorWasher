using System;
using System.Drawing;
using System.IO;
using System.Text;

namespace CursorWasher
{
    internal static class CursorFileTests
    {
        public static void Run(Action<bool, string> check)
        {
            byte[] multi = Directory(32, 128, 48);
            CursorImageSource image = CursorImageSource.Select(multi);
            check(image != null && image.Width == 128 && image.Bits[0] == 1, "CUR uses the largest actual directory image, regardless of order");
            byte[] first = Directory(32), second = Directory(64, 128);
            image = CursorImageSource.Select(Animation(first, second, 1));
            check(image != null && image.Width == 128, "ANI follows the first sequence entry and selects its largest representation");
            image = CursorImageSource.Select(Animation(first, second, 0));
            check(image != null && image.Width == 32, "ANI does not substitute a different frame merely for its resolution");
            check(CursorImageSource.Select(Animation(first, second, 2)) == null, "Invalid ANI sequence falls back safely");
            byte[] bad = (byte[])multi.Clone(); for (int i = 0; i < 4; i++) bad[6 + 12 + i] = 255;
            check(CursorImageSource.Select(bad) == null, "CUR image offsets cannot escape the source buffer");
            byte[] ani = Animation(first, second, 1);
            for (int size = 0; size < ani.Length; size++) {
                byte[] truncated = new byte[size]; Buffer.BlockCopy(ani, 0, truncated, 0, size);
                check(CursorImageSource.Select(truncated) == null, "Truncated ANI does not yield an unrelated or partial frame");
            }
            string cursors = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Cursors");
            foreach (string file in new[] { "aero_arrow.cur", "aero_working.ani", "aero_busy.ani" }) {
                string path = Path.Combine(cursors, file);
                if (!File.Exists(path)) continue;
                CursorImageSource original = CursorImageSource.Read(path);
                using (Bitmap pixels = CursorSprite.LoadDetailedFile(path)) {
                    check(original != null && pixels != null, "Native Windows CUR/ANI image decodes: " + file);
                    check(pixels.Width == original.Width && pixels.Height == original.Height, "Detailed image keeps original dimensions: " + file);
                    Console.WriteLine("CURSOR SOURCE: " + file + " " + pixels.Width + "x" + pixels.Height);
                }
            }
        }
        private static byte[] Directory(params int[] sizes)
        {
            using (MemoryStream stream = new MemoryStream()) using (BinaryWriter writer = new BinaryWriter(stream)) {
                writer.Write((ushort)0); writer.Write((ushort)2); writer.Write((ushort)sizes.Length);
                for (int i = 0; i < sizes.Length; i++) {
                    writer.Write((byte)sizes[i]); writer.Write((byte)sizes[i]); writer.Write((ushort)0);
                    writer.Write((ushort)0); writer.Write((ushort)0); writer.Write((uint)4); writer.Write((uint)(6 + sizes.Length * 16 + i * 4));
                }
                for (int i = 0; i < sizes.Length; i++) writer.Write(i);
                return stream.ToArray();
            }
        }
        private static byte[] Chunk(string tag, byte[] payload)
        {
            using (MemoryStream stream = new MemoryStream()) using (BinaryWriter writer = new BinaryWriter(stream)) {
                writer.Write(Encoding.ASCII.GetBytes(tag)); writer.Write((uint)payload.Length); writer.Write(payload);
                if ((payload.Length & 1) != 0) writer.Write((byte)0);
                return stream.ToArray();
            }
        }
        private static byte[] Animation(byte[] first, byte[] second, uint sequence)
        {
            byte[] frames;
            using (MemoryStream stream = new MemoryStream()) using (BinaryWriter writer = new BinaryWriter(stream)) {
                writer.Write(Encoding.ASCII.GetBytes("fram")); writer.Write(Chunk("icon", first)); writer.Write(Chunk("icon", second)); frames = stream.ToArray();
            }
            using (MemoryStream stream = new MemoryStream()) using (BinaryWriter writer = new BinaryWriter(stream)) {
                writer.Write(Encoding.ASCII.GetBytes("ACON")); writer.Write(Chunk("seq ", BitConverter.GetBytes(sequence))); writer.Write(Chunk("LIST", frames));
                return Chunk("RIFF", stream.ToArray());
            }
        }
    }
}
