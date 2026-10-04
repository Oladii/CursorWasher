using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace CursorWasher
{
    internal sealed class CursorImageSource
    {
        public int Width, Height;
        public byte[] Bits;
        public static CursorImageSource Read(string path)
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 32 * 1024 * 1024) return null;
            return Select(File.ReadAllBytes(path));
        }
        internal static CursorImageSource Select(byte[] bytes)
        {
            if (bytes.Length < 6) return null;
            if (Tag(bytes, 0) != "RIFF") return DirectoryImage(bytes, 0, bytes.Length);
            if (bytes.Length < 12 || Tag(bytes, 8) != "ACON") return null;
            long end = 8L + UInt(bytes, 4);
            if (end > bytes.Length || end < 12) return null;
            List<int[]> frames = new List<int[]>(); uint firstFrame = 0;
            for (long at = 12; at + 8 <= end;) {
                int position = (int)at; uint length = UInt(bytes, position + 4); long next = at + 8 + length;
                if (next > end) return null;
                string tag = Tag(bytes, position);
                if (tag == "seq ") { if (length < 4) return null; firstFrame = UInt(bytes, position + 8); }
                if (tag == "LIST" && length >= 4 && Tag(bytes, position + 8) == "fram") {
                    for (long child = at + 12; child + 8 <= next;) {
                        int offset = (int)child; uint size = UInt(bytes, offset + 4); long childEnd = child + 8 + size;
                        if (childEnd > next) return null;
                        if (Tag(bytes, offset) == "icon") frames.Add(new[] { offset + 8, (int)size });
                        child = childEnd + (size & 1);
                    }
                }
                at = next + (length & 1);
            }
            // DrawIconEx(step=0), used for the native snapshot, obeys this same
            // sequence. Pick a detailed representation of THAT frame, not some
            // unrelated later frame that happens to have more pixels.
            if (firstFrame >= frames.Count) return null;
            int[] frame = frames[(int)firstFrame];
            return DirectoryImage(bytes, frame[0], frame[1]);
        }
        private static CursorImageSource DirectoryImage(byte[] data, int start, int length)
        {
            if (length < 6 || start < 0 || (long)start + length > data.Length || Word(data, start) != 0) return null;
            int type = Word(data, start + 2), count = Word(data, start + 4);
            if ((type != 1 && type != 2) || count < 1 || count > 256 || 6 + count * 16 > length) return null;
            CursorImageSource best = null;
            for (int i = 0; i < count; i++) {
                int at = start + 6 + i * 16;
                int width = data[at] == 0 ? 256 : data[at], height = data[at + 1] == 0 ? 256 : data[at + 1];
                uint size = UInt(data, at + 8), offset = UInt(data, at + 12);
                if (size == 0 || offset < 6 + count * 16 || (long)offset + size > length) return null;
                if (best != null && best.Width * best.Height >= width * height) continue;
                byte[] bits = new byte[(int)size]; Buffer.BlockCopy(data, start + (int)offset, bits, 0, bits.Length);
                best = new CursorImageSource { Width = width, Height = height, Bits = bits };
            }
            return best;
        }
        private static ushort Word(byte[] bytes, int at) { return BitConverter.ToUInt16(bytes, at); }
        private static uint UInt(byte[] bytes, int at) { return BitConverter.ToUInt32(bytes, at); }
        private static string Tag(byte[] bytes, int at) { return Encoding.ASCII.GetString(bytes, at, 4); }
    }
}
