/*
 * Behavioral test oracle for Simd Library image I/O.
 *
 * Creates a 4x4 BGR24 image with known pixel values, encodes it to BMP in
 * memory via SimdImageSaveToMemory, then decodes it back with
 * SimdImageLoadFromMemory and verifies that the round-tripped pixel values
 * match the original.  A no-op program (exit 0) would skip the assertions and
 * exit successfully — but the pixel checks below would fail first, so any
 * patch that makes the library a no-op WILL fail this oracle.
 *
 * Exit 0 = all assertions passed.  Non-zero = assertion or API failure.
 */
#include "Simd/SimdLib.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check(const char *expr, int cond)
{
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", expr);
        return 1;
    }
    return 0;
}

#define CHECK(e) do { if (check(#e, (e))) { SimdFree(bmp); SimdFree(loaded); return 1; } } while (0)

int main(void)
{
    /* 4x4 BGR24 image: top-left quadrant red (B=0,G=0,R=255 in BGR → stored as 0,0,255).
     * 'R' pixel = B=0, G=0, R=255  (red in BGR layout)
     * 'K' pixel = B=0, G=0, R=0   (black)
     * Layout (row-major):
     *   R K K K
     *   K R K K
     *   K K K K
     *   K K K K
     */
    const size_t W = 4, H = 4, CH = 3;
    const size_t stride = W * CH;
    uint8_t src[4 * 4 * 3];
    memset(src, 0, sizeof(src));
    /* pixel(0,0): R=255, G=0, B=0  in BGR layout → bytes B G R = 0 0 255 */
    src[0 * stride + 0 * CH + 0] = 0;    /* B */
    src[0 * stride + 0 * CH + 1] = 0;    /* G */
    src[0 * stride + 0 * CH + 2] = 255;  /* R */
    /* pixel(1,1): R=0, G=255, B=0  in BGR layout → bytes B G R = 0 255 0 */
    src[1 * stride + 1 * CH + 0] = 0;
    src[1 * stride + 1 * CH + 1] = 255;
    src[1 * stride + 1 * CH + 2] = 0;

    uint8_t *bmp = NULL;
    uint8_t *loaded = NULL;
    size_t bmp_size = 0;

    /* Encode to BMP (lossless). */
    bmp = SimdImageSaveToMemory(src, stride, W, H,
                                SimdPixelFormatBgr24, SimdImageFileBmp,
                                100, &bmp_size);
    if (!bmp) {
        fprintf(stderr, "FAIL: SimdImageSaveToMemory returned NULL\n");
        return 1;
    }
    if (bmp_size < 10) {
        fprintf(stderr, "FAIL: BMP size implausibly small: %zu\n", bmp_size);
        SimdFree(bmp);
        return 1;
    }

    /* Decode back in BGR24. */
    size_t out_stride = 0, out_w = 0, out_h = 0;
    SimdPixelFormatType out_fmt = SimdPixelFormatBgr24;
    loaded = SimdImageLoadFromMemory(bmp, bmp_size,
                                     &out_stride, &out_w, &out_h, &out_fmt);
    if (!loaded) {
        fprintf(stderr, "FAIL: SimdImageLoadFromMemory returned NULL\n");
        SimdFree(bmp);
        return 1;
    }

    /* Dimension checks. */
    CHECK(out_w == W);
    CHECK(out_h == H);
    CHECK(out_fmt == SimdPixelFormatBgr24);

    /* Pixel (0,0) should still be B=0, G=0, R=255. */
    uint8_t *p00 = loaded + 0 * out_stride + 0 * CH;
    CHECK(p00[0] == 0);    /* B */
    CHECK(p00[1] == 0);    /* G */
    CHECK(p00[2] == 255);  /* R */

    /* Pixel (1,1) should still be B=0, G=255, R=0. */
    uint8_t *p11 = loaded + 1 * out_stride + 1 * CH;
    CHECK(p11[0] == 0);    /* B */
    CHECK(p11[1] == 255);  /* G */
    CHECK(p11[2] == 0);    /* R */

    /* Pixel (0,1) should be black (untouched). */
    uint8_t *p01 = loaded + 0 * out_stride + 1 * CH;
    CHECK(p01[0] == 0);
    CHECK(p01[1] == 0);
    CHECK(p01[2] == 0);

    SimdFree(bmp);
    SimdFree(loaded);
    printf("PASS: BMP round-trip pixel values verified (4x4 BGR24)\n");
    return 0;
}
