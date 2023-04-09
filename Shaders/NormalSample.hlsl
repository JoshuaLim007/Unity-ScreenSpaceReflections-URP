#ifndef LIMSSR_NORMAL_SAMPLE_INCLUDED
#define LIMSSR_NORMAL_SAMPLE_INCLUDED

#pragma multi_compile _ _GBUFFER_NORMALS_OCT

//#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

// Unpack 2 float of 12bit packed into a 888
float2 Unpack888UIntToFloat2(uint3 x)
{
				// 8 bit in lo, 4 bit in hi
    uint hi = x.z >> 4;
    uint lo = x.z & 15;
    uint2 cb = x.xy | uint2(lo << 8, hi << 8);

    return cb / 4095.0;
}

			// Unpack 2 float of 12bit packed into a 888
float2 Unpack888ToFloat2(float3 x)
{
    uint3 i = (uint3) (x * 255.5); // +0.5 to fix precision error on iOS
    return Unpack888UIntToFloat2(i);
}
float3 UnpackNormalOctQuadEncode(float2 f)
{
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));

				//float2 val = 1.0 - abs(n.yx);
				//n.xy = (n.zz < float2(0.0, 0.0) ? (n.xy >= 0.0 ? val : -val) : n.xy);

				// Optimized version of above code:
    float t = max(-n.z, 0.0);
    n.xy += n.xy >= 0.0 ? -t.xx : t.xx;

    return normalize(n);
}

float3 UnpackNormal(float3 normal)
{
#if defined(_GBUFFER_NORMALS_OCT)
    float2 remappedOctNormalWS = Unpack888ToFloat2(normal); // values between [ 0,  1]
    float2 octNormalWS = remappedOctNormalWS.xy * 2.0 - 1.0;    // values between [-1, +1]
    normal = UnpackNormalOctQuadEncode(octNormalWS);
#else
    normal = normalize(normal);
#endif
    
    return normal;
}

#endif