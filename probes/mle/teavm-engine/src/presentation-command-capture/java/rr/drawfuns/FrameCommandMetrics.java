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

    private static final long[] calls = new long[KINDS];
    private static final long[] pixels = new long[KINDS];
    private static byte[] commands = new byte[128 * 1024];
    private static int commandLength;
    private static final byte[][] assetSources = new byte[MAX_ASSETS][];
    private static final byte[][] assetColormaps = new byte[MAX_ASSETS][];
    private static final byte[][] assetTranslations = new byte[MAX_ASSETS][];
    private static final int[] assetOffsets = new int[MAX_ASSETS];
    private static final int[] assetLengths = new int[MAX_ASSETS];
    private static byte[] assetData = new byte[4 * 1024 * 1024];
    private static int assetDataLength;
    private static int assetCount;
    private static byte[] assetPack;
    private static boolean assetPackDirty;
    private static boolean enabled;

    private FrameCommandMetrics() {}

    public static void enable() {
        resetAll();
        enabled = true;
    }

    public static void disable() {
        enabled = false;
    }

    public static boolean isEnabled() {
        return enabled;
    }

    public static void reset() {
        for (int index = 0; index < KINDS; index++) {
            calls[index] = 0;
            pixels[index] = 0;
        }
        commandLength = 0;
    }

    public static void resetAll() {
        reset();
        for (int index = 0; index < assetCount; index++) {
            assetSources[index] = null;
            assetColormaps[index] = null;
            assetTranslations[index] = null;
        }
        assetDataLength = 0;
        assetCount = 0;
        assetPack = null;
        assetPackDirty = true;
    }

    public static void recordColumn(int kind, ColVars<byte[], byte[]> vars) {
        if (!enabled) return;
        int count = vars.dc_yh - vars.dc_yl + 1;
        if (count <= 0) return;
        calls[kind]++;
        pixels[kind] += count;
        int asset = kind == FUZZ ? 0xffff : asset(
            vars.dc_source, vars.dc_colormap,
            kind == TRANSLATED ? vars.dc_translation : null);
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
        int asset = asset(vars.ds_source, vars.ds_colormap, null);
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
        for (int index = 0; index < assetCount; index++) {
            if (assetSources[index] == source
                    && assetColormaps[index] == colormap
                    && assetTranslations[index] == translation) {
                return index;
            }
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
        assetPackDirty = true;
        return id;
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
