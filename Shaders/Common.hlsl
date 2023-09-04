#ifndef LIMSSR_COMMON_INCLUDED
#define LIMSSR_COMMON_INCLUDED

#pragma multi_compile

inline float ScreenEdgeMask(float2 clipPos) {
    float yDif = 1 - abs(clipPos.y);
    float xDif = 1 - abs(clipPos.x);
    [flatten]
    if (yDif < 0 || xDif < 0) {
        return 0;
    }
    float t1 = smoothstep(0, .2, yDif);
    float t2 = smoothstep(0, .1, xDif);
    return saturate(t2 * t1);
}

const float dither[64] =
{
    0, 32, 8, 40, 2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

//dither noise
inline float Dither8x8(float2 ScreenPosition, float c0)
{
    c0 *= 2;
    float2 uv = ScreenPosition.xy * _ScreenParams.xy;

    uint index = (uint(uv.x) % 8) * 8 + uint(uv.y) % 8;

    float limit = float(dither[index] + 1) / 64.0;
    return saturate(c0 - limit);
}

//interleaved gradient noise
inline float IGN(int pixelX, int pixelY, int frame)
{
    frame = frame % 64; // need to periodically reset frame to avoid numerical issues
    float x = float(pixelX) + 5.588238f * float(frame);
    float y = float(pixelY) + 5.588238f * float(frame);
    return fmod(52.9829189f * fmod(0.06711056f * float(x) + 0.00583715f * float(y), 1.0f), 1.0f);
}

inline uint NextPowerOf2(int value) {
    uint myNumberPowerOfTwo = 2 << firstbithigh(value - 1);
    return myNumberPowerOfTwo;
}
inline bool floatEqApprox(float a, float b) {
    const float eps = 0.00001f;
    return abs(a - b) < eps;
}
#endif