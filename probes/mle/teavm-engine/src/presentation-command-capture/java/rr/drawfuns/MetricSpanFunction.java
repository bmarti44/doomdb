package rr.drawfuns;

import i.IDoomSystem;

/** Delegates an indexed visplane span unchanged while recording its size. */
public final class MetricSpanFunction extends DoomSpanFunction<byte[], byte[]> {
    private final DoomSpanFunction<byte[], byte[]> delegate;

    public MetricSpanFunction(
            int screenWidth, int screenHeight, int[] ylookup, int[] columnofs,
            SpanVars<byte[], byte[]> vars, byte[] screen, IDoomSystem system,
            DoomSpanFunction<byte[], byte[]> delegate) {
        super(screenWidth, screenHeight, ylookup, columnofs, vars, screen, system);
        this.delegate = delegate;
    }

    @Override
    public void invoke() {
        FrameCommandMetrics.recordSpan(dsvars);
        delegate.invoke(dsvars);
    }
}
