package rr.drawfuns;

/**
 * Disabled-by-default presentation command census for the database renderer.
 *
 * The production MLE command encoder uses the same low-level call boundary.
 * Keeping the first integration as a delegating counter proves real command
 * cardinality without changing a single framebuffer write or game-state
 * transition.
 */
public final class FrameCommandMetrics {
    public static final int WALL = 0;
    public static final int MASKED = 1;
    public static final int PLAYER = 2;
    public static final int SKY = 3;
    public static final int FUZZ = 4;
    public static final int TRANSLATED = 5;
    public static final int SPAN = 6;
    private static final int KINDS = 7;
    private static final int COMMAND_BYTES = 28;
    private static final int ASSET_MAGIC = 0x31414346;
    private static final int MAX_ASSETS = 16384;
    private static final int ASSET_HASH_SIZE = 32768;
    private static final int LIVE_ASSET_RESET_AT = 10000;
    private static final int WIDTH = 320;
    private static final int VIEW_HEIGHT = 168;
    private static final int FRAME_HEIGHT = 200;
    private static final int VIEW_PIXELS = WIDTH * VIEW_HEIGHT;
    private static final int FRAME_PIXELS = WIDTH * FRAME_HEIGHT;
    private static final int HUD_PIXELS = FRAME_PIXELS - VIEW_PIXELS;

    private static final long[] calls = new long[KINDS];
    private static final long[] pixels = new long[KINDS];
    private static byte[] commands = new byte[128 * 1024];
    private static int commandLength;
    private static final byte[][] assetSources = new byte[MAX_ASSETS][];
    private static final byte[][] assetColormaps = new byte[MAX_ASSETS][];
    private static final byte[][] assetTranslations = new byte[MAX_ASSETS][];
    private static final int[] assetOffsets = new int[MAX_ASSETS];
    private static final int[] assetLengths = new int[MAX_ASSETS];
    private static final int[] assetHash = new int[ASSET_HASH_SIZE];
    private static final int[] assetHashGenerations =
        new int[ASSET_HASH_SIZE];
    private static int assetHashGeneration = 1;
    private static byte[] assetData = new byte[4 * 1024 * 1024];
    private static int assetDataLength;
    private static int assetCount;
    private static byte[] assetPack;
    private static boolean assetPackDirty;
    private static byte[] liveKinds = new byte[4096];
    private static int[] liveA = new int[4096];
    private static int[] liveB = new int[4096];
    private static int[] liveC = new int[4096];
    private static int[] liveD = new int[4096];
    private static int[] liveE = new int[4096];
    private static int[] liveF = new int[4096];
    private static int[] liveG = new int[4096];
    private static int[] liveH = new int[4096];
    private static int liveCount;
    private static final byte[] emptyViewport = new byte[VIEW_PIXELS];
    private static final byte[] capturedFrame = new byte[FRAME_PIXELS];
    private static final byte[] rowMajorCapturedFrame = new byte[FRAME_PIXELS];
    private static boolean enabled;
    private static boolean captureOnly;
    private static boolean countOnly;
    private static int liveAssetResets;

    private FrameCommandMetrics() {}

    public static void enable() {
        resetAll();
        enabled = true;
    }

    public static void disable() {
        enabled = false;
        captureOnly = false;
    }

    public static boolean isEnabled() {
        return enabled;
    }

    public static void setCaptureOnly(boolean value) {
        if (value && !enabled) {
            throw new IllegalStateException("frame command metrics are disabled");
        }
        captureOnly = value;
    }

    public static boolean isCaptureOnly() {
        return captureOnly;
    }

    public static void setCountOnly(boolean value) {
        countOnly = value;
    }

    public static void reset() {
        for (int index = 0; index < KINDS; index++) {
            calls[index] = 0;
            pixels[index] = 0;
        }
        commandLength = 0;
        liveCount = 0;
    }

    public static void resetAll() {
        reset();
        for (int index = 0; index < assetCount; index++) {
            assetSources[index] = null;
            assetColormaps[index] = null;
            assetTranslations[index] = null;
        }
        resetAssetRegistry();
        liveAssetResets = 0;
        captureOnly = false;
        countOnly = false;
    }

    public static void beginLiveFrame() {
        reset();
        if (assetCount >= LIVE_ASSET_RESET_AT) {
            resetAssetRegistry();
            liveAssetResets++;
        }
    }

    public static void recordColumn(int kind, ColVars<byte[], byte[]> vars) {
        if (!enabled) return;
        int count = vars.dc_yh - vars.dc_yl + 1;
        if (count <= 0) return;
        calls[kind]++;
        pixels[kind] += count;
        if (countOnly) return;
        int asset = kind == FUZZ ? 0xffff : asset(
            vars.dc_source, vars.dc_colormap,
            kind == TRANSLATED ? vars.dc_translation : null);
        ensureLive();
        int live = liveCount++;
        liveKinds[live] = (byte) kind;
        liveA[live] = vars.dc_x;
        liveB[live] = vars.dc_yl;
        liveC[live] = vars.dc_yh;
        liveD[live] = vars.dc_iscale;
        liveE[live] = vars.dc_texturemid
            + (vars.dc_yl - vars.centery) * vars.dc_iscale;
        liveF[live] = vars.dc_texheight;
        liveG[live] = vars.dc_source_ofs;
        liveH[live] = asset == 0xffff ? -1 : assetOffsets[asset];
        ensureCommand(COMMAND_BYTES);
        int at = commandLength;
        commands[at] = (byte) kind;
        commands[at + 1] = 0;
        putU16(commands, at + 2, vars.dc_x);
        putU16(commands, at + 4, vars.dc_yl);
        putU16(commands, at + 6, vars.dc_yh);
        putI32(commands, at + 8, vars.dc_iscale);
        putI32(commands, at + 12, vars.dc_texturemid);
        putI32(commands, at + 16, vars.dc_texheight);
        putI32(commands, at + 20, vars.dc_source_ofs);
        putU16(commands, at + 24, vars.centery);
        putU16(commands, at + 26, asset);
        commandLength += COMMAND_BYTES;
    }

    public static void recordSpan(SpanVars<byte[], byte[]> vars) {
        if (!enabled) return;
        int count = vars.ds_x2 - vars.ds_x1 + 1;
        if (count <= 0) return;
        calls[SPAN]++;
        pixels[SPAN] += count;
        if (countOnly) return;
        int asset = asset(vars.ds_source, vars.ds_colormap, null);
        ensureLive();
        int live = liveCount++;
        liveKinds[live] = (byte) SPAN;
        liveA[live] = vars.ds_x1;
        liveB[live] = vars.ds_x2;
        liveC[live] = vars.ds_y;
        liveD[live] = vars.ds_xfrac;
        liveE[live] = vars.ds_yfrac;
        liveF[live] = vars.ds_xstep;
        liveG[live] = vars.ds_ystep;
        liveH[live] = assetOffsets[asset];
        ensureCommand(COMMAND_BYTES);
        int at = commandLength;
        commands[at] = (byte) SPAN;
        commands[at + 1] = 0;
        putU16(commands, at + 2, vars.ds_x1);
        putU16(commands, at + 4, vars.ds_x2);
        putU16(commands, at + 6, vars.ds_y);
        putI32(commands, at + 8, vars.ds_xfrac);
        putI32(commands, at + 12, vars.ds_yfrac);
        putI32(commands, at + 16, vars.ds_xstep);
        putI32(commands, at + 20, vars.ds_ystep);
        putU16(commands, at + 24, asset);
        putU16(commands, at + 26, 0);
        commandLength += COMMAND_BYTES;
    }

    public static String snapshot() {
        return "wallCalls=" + calls[WALL] + "|wallPixels=" + pixels[WALL]
            + "|maskedCalls=" + calls[MASKED] + "|maskedPixels=" + pixels[MASKED]
            + "|playerCalls=" + calls[PLAYER] + "|playerPixels=" + pixels[PLAYER]
            + "|skyCalls=" + calls[SKY] + "|skyPixels=" + pixels[SKY]
            + "|fuzzCalls=" + calls[FUZZ] + "|fuzzPixels=" + pixels[FUZZ]
            + "|translatedCalls=" + calls[TRANSLATED]
            + "|translatedPixels=" + pixels[TRANSLATED]
            + "|spanCalls=" + calls[SPAN] + "|spanPixels=" + pixels[SPAN];
    }

    public static int commandLength() {
        return commandLength;
    }

    public static int liveCommandCount() {
        return liveCount;
    }

    public static int liveAssetResetCount() {
        return liveAssetResets;
    }

    /**
     * Raster the freshly captured viewport and append Mocha's authentic HUD.
     *
     * The viewport is retained column-major so the interpreted inner column
     * loop writes contiguous bytes.  The final 32 rows remain row-major.
     * This is an explicit wire encoding: the browser transposes the first
     * 53,760 bytes while copying the already-rendered HUD unchanged.
     */
    public static byte[] renderCapturedFrame(byte[] originalFrame) {
        if (originalFrame == null || originalFrame.length != FRAME_PIXELS) {
            throw new IllegalStateException("captured frame is unavailable");
        }
        System.arraycopy(emptyViewport, 0, capturedFrame, 0, VIEW_PIXELS);
        for (int command = 0; command < liveCount; command++) {
            int kind = liveKinds[command] & 255;
            if (kind == SPAN) {
                drawLiveSpan(command);
            } else if (kind == FUZZ) {
                throw new IllegalStateException(
                    "live fuzz raster requires its separately gated path");
            } else if (kind <= TRANSLATED) {
                drawLiveColumn(command);
            } else {
                throw new IllegalStateException("unknown live raster command");
            }
        }
        System.arraycopy(
            originalFrame, VIEW_PIXELS, capturedFrame, VIEW_PIXELS, HUD_PIXELS);
        return capturedFrame;
    }

    public static byte[] capturedFrameChunk(int offset, int length) {
        if (offset < 0 || length < 0 || length > 32767
                || offset + length > capturedFrame.length) {
            throw new IllegalArgumentException(
                "captured frame chunk outside framebuffer");
        }
        byte[] result = new byte[length];
        System.arraycopy(capturedFrame, offset, result, 0, length);
        return result;
    }

    public static int prepareCapturedFrameRowMajor() {
        int output = 0;
        for (int y = 0; y < VIEW_HEIGHT; y++) {
            for (int x = 0; x < WIDTH; x++) {
                rowMajorCapturedFrame[output++] =
                    capturedFrame[x * VIEW_HEIGHT + y];
            }
        }
        System.arraycopy(capturedFrame, VIEW_PIXELS,
            rowMajorCapturedFrame, VIEW_PIXELS, HUD_PIXELS);
        return FRAME_PIXELS;
    }

    public static byte[] capturedFrameRowMajorChunk(int offset, int length) {
        if (offset < 0 || length < 0 || length > 32767
                || offset + length > rowMajorCapturedFrame.length) {
            throw new IllegalArgumentException(
                "row-major frame chunk outside framebuffer");
        }
        byte[] result = new byte[length];
        System.arraycopy(rowMajorCapturedFrame, offset, result, 0, length);
        return result;
    }

    public static byte[] commandChunk(int offset, int length) {
        if (offset < 0 || length < 0 || length > 32767
                || offset + length > commandLength) {
            throw new IllegalArgumentException("command chunk outside frame");
        }
        byte[] result = new byte[length];
        System.arraycopy(commands, offset, result, 0, length);
        return result;
    }

    public static int assetCount() {
        return assetCount;
    }

    public static int assetPackLength() {
        buildAssetPack();
        return assetPack.length;
    }

    public static byte[] assetPackChunk(int offset, int length) {
        buildAssetPack();
        if (offset < 0 || length < 0 || length > 32767
                || offset + length > assetPack.length) {
            throw new IllegalArgumentException("asset chunk outside pack");
        }
        byte[] result = new byte[length];
        System.arraycopy(assetPack, offset, result, 0, length);
        return result;
    }

    private static int asset(
            byte[] source, byte[] colormap, byte[] translation) {
        if (source == null || colormap == null || colormap.length < 256) {
            throw new IllegalStateException("invalid presentation asset");
        }
        int slot = assetHashSlot(source, colormap, translation);
        while (assetHashGenerations[slot] == assetHashGeneration) {
            int index = assetHash[slot] - 1;
            if (assetSources[index] == source
                    && assetColormaps[index] == colormap
                    && assetTranslations[index] == translation) {
                return index;
            }
            slot = (slot + 1) & (ASSET_HASH_SIZE - 1);
        }
        if (assetCount >= MAX_ASSETS) {
            throw new IllegalStateException("presentation asset limit");
        }
        int id = assetCount++;
        assetSources[id] = source;
        assetColormaps[id] = colormap;
        assetTranslations[id] = translation;
        assetOffsets[id] = assetDataLength;
        assetLengths[id] = source.length;
        ensureAsset(source.length);
        for (int index = 0; index < source.length; index++) {
            int sample = source[index] & 255;
            if (translation != null) sample = translation[sample] & 255;
            assetData[assetDataLength++] = colormap[sample];
        }
        assetHash[slot] = id + 1;
        assetHashGenerations[slot] = assetHashGeneration;
        assetPackDirty = true;
        return id;
    }

    private static void resetAssetRegistry() {
        assetDataLength = 0;
        assetCount = 0;
        assetPack = null;
        assetPackDirty = true;
        assetHashGeneration++;
        if (assetHashGeneration == 0) {
            for (int index = 0; index < assetHashGenerations.length; index++) {
                assetHashGenerations[index] = 0;
            }
            assetHashGeneration = 1;
        }
    }

    private static int assetHashSlot(
            byte[] source, byte[] colormap, byte[] translation) {
        int hash = System.identityHashCode(source);
        hash = hash * 31 + System.identityHashCode(colormap);
        hash = hash * 31
            + (translation == null ? 0 : System.identityHashCode(translation));
        hash ^= hash >>> 16;
        return hash & (ASSET_HASH_SIZE - 1);
    }

    private static void drawLiveColumn(int command) {
        int x = liveA[command];
        int yl = liveB[command];
        int yh = liveC[command];
        int fracStep = liveD[command];
        int frac = liveE[command];
        int textureHeight = liveF[command];
        int sourceOffset = liveG[command];
        int source = liveH[command];
        if (x < 0 || x >= WIDTH || yl < 0 || yl > yh || yh >= VIEW_HEIGHT
                || source < 0) {
            throw new IllegalStateException("live column outside framebuffer");
        }
        int output = x * VIEW_HEIGHT + yl;
        int count = yh - yl + 1;
        int heightMask = textureHeight - 1;
        if ((textureHeight & heightMask) != 0) {
            int wrap = textureHeight << 16;
            if (wrap <= 0) {
                throw new IllegalStateException("invalid live texture height");
            }
            if (frac < 0) {
                while ((frac += wrap) < 0) {
                    // Match Mocha's fixed-point normalization exactly.
                }
            } else {
                while (frac >= wrap) frac -= wrap;
            }
            while (count-- > 0) {
                capturedFrame[output++] = assetData[source + (frac >> 16)];
                frac += fracStep;
                if (frac >= wrap) frac -= wrap;
            }
        } else {
            while (count-- > 0) {
                int sample = sourceOffset + ((frac >> 16) & heightMask);
                capturedFrame[output++] = assetData[source + sample];
                frac += fracStep;
            }
        }
    }

    private static void drawLiveSpan(int command) {
        int x1 = liveA[command];
        int x2 = liveB[command];
        int y = liveC[command];
        int xfrac = liveD[command];
        int yfrac = liveE[command];
        int xstep = liveF[command];
        int ystep = liveG[command];
        int source = liveH[command];
        if (x1 < 0 || x1 > x2 || x2 >= WIDTH || y < 0 || y >= VIEW_HEIGHT
                || source < 0) {
            throw new IllegalStateException("live span outside framebuffer");
        }
        int output = x1 * VIEW_HEIGHT + y;
        for (int x = x1; x <= x2; x++) {
            int spot = ((yfrac >> 10) & 4032) + ((xfrac >> 16) & 63);
            capturedFrame[output] = assetData[source + spot];
            output += VIEW_HEIGHT;
            xfrac += xstep;
            yfrac += ystep;
        }
    }

    private static void buildAssetPack() {
        if (!assetPackDirty && assetPack != null) return;
        int header = 12 + assetCount * 8;
        assetPack = new byte[header + assetDataLength];
        putI32(assetPack, 0, ASSET_MAGIC);
        putI32(assetPack, 4, assetCount);
        putI32(assetPack, 8, assetDataLength);
        for (int index = 0; index < assetCount; index++) {
            putI32(assetPack, 12 + index * 8, header + assetOffsets[index]);
            putI32(assetPack, 16 + index * 8, assetLengths[index]);
        }
        System.arraycopy(
            assetData, 0, assetPack, header, assetDataLength);
        assetPackDirty = false;
    }

    private static void ensureCommand(int extra) {
        if (commandLength + extra <= commands.length) return;
        int length = commands.length;
        while (length < commandLength + extra) length *= 2;
        byte[] replacement = new byte[length];
        System.arraycopy(commands, 0, replacement, 0, commandLength);
        commands = replacement;
    }

    private static void ensureLive() {
        if (liveCount < liveKinds.length) return;
        int length = liveKinds.length * 2;
        byte[] kinds = new byte[length];
        int[] a = new int[length];
        int[] b = new int[length];
        int[] c = new int[length];
        int[] d = new int[length];
        int[] e = new int[length];
        int[] f = new int[length];
        int[] g = new int[length];
        int[] h = new int[length];
        System.arraycopy(liveKinds, 0, kinds, 0, liveCount);
        System.arraycopy(liveA, 0, a, 0, liveCount);
        System.arraycopy(liveB, 0, b, 0, liveCount);
        System.arraycopy(liveC, 0, c, 0, liveCount);
        System.arraycopy(liveD, 0, d, 0, liveCount);
        System.arraycopy(liveE, 0, e, 0, liveCount);
        System.arraycopy(liveF, 0, f, 0, liveCount);
        System.arraycopy(liveG, 0, g, 0, liveCount);
        System.arraycopy(liveH, 0, h, 0, liveCount);
        liveKinds = kinds;
        liveA = a;
        liveB = b;
        liveC = c;
        liveD = d;
        liveE = e;
        liveF = f;
        liveG = g;
        liveH = h;
    }

    private static void ensureAsset(int extra) {
        if (assetDataLength + extra <= assetData.length) return;
        int length = assetData.length;
        while (length < assetDataLength + extra) length *= 2;
        byte[] replacement = new byte[length];
        System.arraycopy(assetData, 0, replacement, 0, assetDataLength);
        assetData = replacement;
    }

    private static void putU16(byte[] target, int offset, int value) {
        target[offset] = (byte) value;
        target[offset + 1] = (byte) (value >>> 8);
    }

    private static void putI32(byte[] target, int offset, int value) {
        target[offset] = (byte) value;
        target[offset + 1] = (byte) (value >>> 8);
        target[offset + 2] = (byte) (value >>> 16);
        target[offset + 3] = (byte) (value >>> 24);
    }
}
