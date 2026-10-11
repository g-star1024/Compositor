#include "DeepPixels.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>

// Runs `body` over rows split into a few bands a core, all at once.
static void deep_rows(size_t height, void (^body)(size_t first, size_t last)) {
    size_t bands = height < 64 ? 1 : 32, size = (height + bands - 1) / bands;
    dispatch_apply(bands, DISPATCH_APPLY_AUTO, ^(size_t band) {
        size_t first = band * size, last = first + size < height ? first + size : height;
        if (first < last) body(first, last);
    });
}

static inline long deep_alpha8(uint16_t alpha) { return lroundf((float)alpha * (255.0f / 65535.0f)); }

// A channel's 8-bit value rounded down, kept within the pixel's alpha (premultiplied colors never pass it).
static inline long deep_down(uint16_t value, long alpha) {
    long down = (long)floorf((float)value * (255.0f / 65535.0f));
    return down > alpha ? alpha : down;
}

void deep_split(const uint16_t *deep, size_t deepStride, uint8_t *out, size_t stride, size_t width, size_t height,
                int step) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)deep + y * deepStride);
            uint8_t *o = out + y * stride;
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                long alpha = deep_alpha8(p[3]);
                for (int c = 0; c < 3; ++c) {
                    long value = deep_down(p[c], alpha) + step;
                    o[x * 4 + c] = (uint8_t)(value > alpha ? alpha : value);
                }
                o[x * 4 + 3] = (uint8_t)alpha;
            }
        }
    });
}

void deep_merge(const uint16_t *deep, size_t deepStride, const uint8_t *lowResult, const uint8_t *nearResult,
                const uint8_t *farResult, size_t stride, uint16_t *out, size_t outStride, size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)deep + y * deepStride);
            const uint8_t *lo = lowResult + y * stride, *ne = nearResult + y * stride, *fa = farResult + y * stride;
            uint16_t *o = (uint16_t *)((uint8_t *)out + y * outStride);
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                long alpha = deep_alpha8(p[3]);
                float outAlpha = (float)lo[x * 4 + 3] * 257.0f;
                for (int c = 0; c < 3; ++c) {
                    long down = deep_down(p[c], alpha);
                    // How far past `low` the color is, in 8-bit steps (under one), and the real gaps to `near` and
                    // `far`, which alpha may have shortened.
                    float past = fminf(1, fmaxf(0, (float)p[c] * (255.0f / 65535.0f) - (float)down));
                    long nearGap = (down + 1 > alpha ? alpha : down + 1) - down;
                    long farGap = (down + 4 > alpha ? alpha : down + 4) - down;
                    float l = lo[x * 4 + c], change = (float)ne[x * 4 + c] - l;
                    float value = l;
                    if (nearGap > 0 && (fabsf(change) >= 2 || farGap == nearGap)) value = l + change * past;
                    else if (farGap > 0) value = l + ((float)fa[x * 4 + c] - l) / (float)farGap * past;
                    float scaled = value * 257.0f;
                    o[x * 4 + c] = (uint16_t)lroundf(scaled < 0 ? 0 : scaled > outAlpha ? outAlpha : scaled);
                }
                o[x * 4 + 3] = (uint16_t)lroundf(outAlpha);
            }
        }
    });
}

void deep_take_painted(uint16_t *deep, size_t deepStride, const uint8_t *painted, const uint8_t *base, size_t stride,
                       size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *d = (uint16_t *)((uint8_t *)deep + y * deepStride);
            const uint8_t *p = painted + y * stride, *b = base + y * stride;
            for (size_t x = 0; x < width * 4; x += 4) {
                if (p[x] == b[x] && p[x + 1] == b[x + 1] && p[x + 2] == b[x + 2] && p[x + 3] == b[x + 3]) continue;
                for (int c = 0; c < 4; ++c) d[x + c] = (uint16_t)(p[x + c] * 257);
            }
        }
    });
}
