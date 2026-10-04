namespace CursorWasher
{
    internal sealed class WashClickSequence
    {
        private double? firstRelease;
        public void Begin(double timestamp) { firstRelease = timestamp; }
        public bool ConsumeInitialDoubleClick(int clickCount, double timestamp, double interval)
        {
            double? start = firstRelease; firstRelease = null;
            return start.HasValue && clickCount == 2 && timestamp >= start.Value && timestamp - start.Value <= interval;
        }
        public void Cancel() { firstRelease = null; }
    }
}
