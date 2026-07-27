package rr.drawfuns;

import i.IDoomSystem;

/** Delegates an indexed column unchanged while recording its real size. */
public final class MetricColumnFunction
        extends DoomColumnFunction<byte[], byte[]> {
    private final DoomColumnFunction<byte[], byte[]> delegate;
    private final int kind;

    public MetricColumnFunction(
            int screenWidth, int screenHeight, int[] ylookup, int[] columnofs,
            ColVars<byte[], byte[]> vars, byte[] screen, IDoomSystem system,
            DoomColumnFunction<byte[], byte[]> delegate, int kind) {
        super(screenWidth, screenHeight, ylookup, columnofs, vars, screen, system);
        this.delegate = delegate;
        this.kind = kind;
        this.flags = delegate.getFlags();
    }

    @Override
    public void invoke() {
        FrameCommandMetrics.recordColumn(kind, dcvars);
        if (!FrameCommandMetrics.isCaptureOnly()) {
            delegate.invoke(dcvars);
        }
    }
}
