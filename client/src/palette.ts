export type Palette = Uint8Array<ArrayBuffer>;

export function createPalette(bytes: Uint8Array<ArrayBuffer>): Palette {
  if (bytes.length !== 256 * 3) throw new TypeError('palette byte length is invalid');
  return new Uint8Array(bytes);
}

export function applyPalette(indices: Uint8Array<ArrayBuffer>, palette: Palette): Uint8ClampedArray<ArrayBuffer> {
  if (indices.length !== 320 * 200 || palette.length !== 256 * 3) {
    throw new TypeError('palette input dimensions are invalid');
  }
  const rgba = new Uint8ClampedArray(indices.length * 4);
  for (let index = 0; index < indices.length; index += 1) {
    const source = indices[index]! * 3;
    const target = index * 4;
    rgba[target] = palette[source]!;
    rgba[target + 1] = palette[source + 1]!;
    rgba[target + 2] = palette[source + 2]!;
    rgba[target + 3] = 255;
  }
  return rgba;
}
