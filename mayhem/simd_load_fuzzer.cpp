/*
 * Fuzzing harness for Simd Library image loading.
 * Exercises SimdImageLoadFromMemory with various output pixel formats.
 *
 * Ported from the original mayhemheroes/Simd harness (which used Test::View::Load;
 * that function is a thin wrapper around SimdImageLoadFromMemory).  Using the public
 * C API directly avoids pulling in the internal Test-framework headers.
 */
#include "Simd/SimdLib.h"

#include <stdint.h>
#include <stdlib.h>

extern "C"
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 5)
        return 0;

    static const SimdPixelFormatType kFormats[] = {
        SimdPixelFormatGray8,
        SimdPixelFormatBgr24,
        SimdPixelFormatBgra32,
        SimdPixelFormatRgb24
    };
    static const int kNumFormats = (int)(sizeof(kFormats) / sizeof(kFormats[0]));

    for (int i = 0; i < kNumFormats; ++i) {
        size_t stride = 0, width = 0, height = 0;
        SimdPixelFormatType fmt = kFormats[i];
        uint8_t *pixels = SimdImageLoadFromMemory(data, size,
                                                   &stride, &width, &height, &fmt);
        if (pixels)
            SimdFree(pixels);
    }
    return 0;
}
