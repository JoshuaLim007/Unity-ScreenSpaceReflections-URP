// Upgrade NOTE: commented out 'float3 _WorldSpaceCameraPos', a built-in variable

Shader "Hidden/ssr_shader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Never

        //reflected color and mask only
        Pass
        {
            Name "Linear SSR"

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma enable_d3d11_debug_symbols

            #include "UnityCG.cginc"
			#include "NormalSample.hlsl"
            #include "Common.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                return o;
            }

            uniform sampler2D _CameraDepthTexture;

            uniform sampler2D _MainTex;
            uniform sampler2D _GBuffer2;

            float3 _WorldSpaceViewDir;
            float _RenderScale;
            float stride;
            float numSteps;
            float minSmoothness;
            int iteration;
            #define binaryStepCount 16

            half3 frag(v2f i) : SV_Target
            {
                float rawDepth = tex2D(_CameraDepthTexture, i.uv).r;
                [branch]
                if (rawDepth == 0) {
                    return float4(0, 0, 0, 0);
                }
                float4 gbuff = tex2D(_GBuffer2, i.uv);
                float smoothness = gbuff.w;
                float stepS = smoothstep(minSmoothness, 1, smoothness);
				float3 normal = UnpackNormal(gbuff.xyz);

                float4 clipSpace = float4(i.uv * 2 - 1, rawDepth, 1);
                float4 viewSpacePosition = mul(_InverseProjectionMatrix, clipSpace);
                viewSpacePosition /= viewSpacePosition.w;
                viewSpacePosition.y *= -1;
                float4 worldSpacePosition = mul(_InverseViewMatrix, viewSpacePosition);
                float3 viewDir = normalize(float3(worldSpacePosition.xyz) - _WorldSpaceCameraPos);
                float3 reflectionRay = reflect(viewDir, normal);
                
                float3 reflectionRay_v = mul(_ViewMatrix, float4(reflectionRay,0));
                reflectionRay_v.z *= -1;
                viewSpacePosition.z *= -1;

                float viewReflectDot = saturate(dot(viewDir, reflectionRay));
                float cameraViewReflectDot = saturate(dot(_WorldSpaceViewDir, reflectionRay));

                float thickness = stride * 2;
                float oneMinusViewReflectDot = sqrt(1 - viewReflectDot);
                stride /= oneMinusViewReflectDot;
                thickness /= oneMinusViewReflectDot;


                int hit = 0;
                float maskOut = 1;
                float3 currentPosition = viewSpacePosition.xyz;
                float2 currentScreenSpacePosition = i.uv;

                bool doRayMarch = smoothness > minSmoothness;

                float maxRayLength = numSteps * stride;
                float maxDist = lerp(min(viewSpacePosition.z, maxRayLength), maxRayLength, cameraViewReflectDot);
                float numSteps_f = maxDist / stride;
                numSteps = max(numSteps_f, 0);

                [branch]
                if (doRayMarch) {

                    float3 ray = reflectionRay_v * stride;
                    float depthDelta = 0;

                    [loop]
                    for (int step = 0; step < numSteps; step++)
                    {
                        currentPosition += ray;

                        float currentDepth;
                        float2 screenSpace;

                        float4 uv = mul(_ProjectionMatrix, float4(currentPosition.x, currentPosition.y * -1, currentPosition.z * -1, 1));
                        uv /= uv.w;
                        uv.x *= 0.5f;
                        uv.y *= 0.5f;
                        uv.x += 0.5f;
                        uv.y += 0.5f;

                        [branch]
                        if (uv.x >= 1 || uv.x < 0 || uv.y >= 1 || uv.y < 0) {
                            break;
                        }

                        //sample depth at current screen space
                        float sampledDepth = tex2D(_CameraDepthTexture, uv.xy).r;

                        [branch]
                        //compare the current depth of the current position to the camera depth at the screen space
                        if (abs(rawDepth - sampledDepth) > 0 && sampledDepth != 0) {
                            depthDelta = currentPosition.z - LinearEyeDepth(sampledDepth);

                            [branch]
                            if (depthDelta > 0 && depthDelta < stride * 2) {
                                currentScreenSpacePosition = uv.xy;
                                hit = 1;
                                break;
                            }
                        }
                    }

                    if (depthDelta > thickness) {
                        hit = 0;
                    }

                    
                    int binarySearchSteps = binaryStepCount * hit;

                    [loop]
                    for (int i = 0; i < binaryStepCount; i++)
                    {
                        ray *= .5f;
                        [flatten]
                        if (depthDelta > 0) {
                            currentPosition -= ray;
                        }
                        else if (depthDelta < 0) {
                            currentPosition += ray;
                        }
                        else {
                            break;
                        }

                        float4 uv = mul(_ProjectionMatrix, float4(currentPosition.x, currentPosition.y * -1, currentPosition.z * -1, 1));
                        uv /= uv.w;
                        maskOut = ScreenEdgeMask(uv);
                        uv.x *= 0.5f;
                        uv.y *= 0.5f;
                        uv.x += 0.5f;
                        uv.y += 0.5f;
                        currentScreenSpacePosition = uv;

                        float sd = tex2D(_CameraDepthTexture, uv.xy).r;
                        depthDelta = currentPosition.z - LinearEyeDepth(sd);
                        float minv = 1 / max((oneMinusViewReflectDot * float(i)), 0.001);
                        if (abs(depthDelta) > minv) {
                            hit = 0;
                            break;
                        }
                    }

                    //remove backface intersections
					float3 currentNormal = UnpackNormal(tex2D(_GBuffer2, currentScreenSpacePosition).xyz);
                    float backFaceDot = dot(currentNormal, reflectionRay);
                    [flatten]
                    if (backFaceDot > 0) {
                        hit = 0;
                    }

                }

                float3 deltaDir = viewSpacePosition.xyz - currentPosition;
                float progress = dot(deltaDir, deltaDir) / (maxDist * maxDist);
                progress = smoothstep(0, .5, 1 - progress);

                maskOut *= hit;
                return half3(currentScreenSpacePosition, maskOut * progress);
            }
            ENDCG
        }
    
        //composite
        Pass
        {
            Name "SSR Composite"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma enable_d3d11_debug_symbols

            #include "UnityCG.cginc"
			#include "NormalSample.hlsl"
            #include "Common.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                return o;
            }
            float _RenderScale;
            float minSmoothness;

            uniform sampler2D _GBuffer1;            //metalness color
            uniform sampler2D _ReflectedColorMap;   //contains reflected uv coordinates
            uniform sampler2D _MainTex;             //main screen color
            uniform sampler2D _GBuffer2;            //normals and smoothness
            uniform sampler2D _GBuffer0;             //diffuse color
            uniform sampler2D _CameraDepthTexture;             //diffuse color

            fixed4 frag(v2f i) : SV_Target
            {
                _PaddedScale = 1 / _PaddedScale;
                float4 maint = tex2D(_MainTex, i.uv * _PaddedScale);
                float rawDepth = tex2D(_CameraDepthTexture, i.uv).r;
                [branch]
                if (rawDepth == 0) {
                    return maint;
                }
                float3 worldSpacePosition = getWorldPosition(rawDepth, i.uv);
                float3 viewDir = normalize(float3(worldSpacePosition.xyz) - _WorldSpaceCameraPos);

                //Get screen space normals and smoothness
                float4 normal = tex2D(_GBuffer2, i.uv);
                normal.xyz = UnpackNormal(normal.xyz);
                float stepS = smoothstep(minSmoothness, 1, normal.w);
                float fresnal = 1 - dot(viewDir, -normal);
                normal.xyz = mul(_ViewMatrix, float4(normal.xyz, 0));
                normal.xyz = mul(_ProjectionMatrix, float4(normal.xyz, 0));
                normal.y *= -1;

                //Dither calculation
                float dither;
                //type 0 = use original mask
                //type 1 = dither original mask
                float type;
                [branch]
                if (_DitherMode == 0) {
                    dither = Dither8x8(i.uv.xy * _RenderScale, .5);
                    type = 0;
                }
                else {
                    dither = IGN(i.uv.x * _ScreenParams.x * _RenderScale, i.uv.y * _ScreenParams.y * _RenderScale, _Frame);
                    type = 0;
                }
                dither *= 2;
                dither -= 1;
                //////////////////////

                //Get dithered UV coords
                float stepSSqrd = pow(stepS, 2);
                const float2 uvOffset = normal * lerp(dither * 0.05f, 0, stepSSqrd);
                float3 reflectedUv = tex2D(_ReflectedColorMap, (i.uv + uvOffset * type) * _PaddedScale);
                float maskVal = saturate(reflectedUv.z) * stepS;
                reflectedUv.xy += uvOffset * (1 - type);

                //Get luminance mask for emmissive materials
                float lumin = saturate(RGB2Lum(maint) - 1);
                float luminMask = 1 - lumin;
                luminMask = pow(luminMask, 5);

                //get metal and ao and spec color
                float2 gb1 = tex2D(_GBuffer1, i.uv.xy).ra;     
                float4 specularColor = float4(tex2D(_GBuffer0, i.uv.xy).rgb, 1);     

                //calculate fresnal
                float fresnalMask = 1 - saturate(RGB2Lum(specularColor));
                fresnalMask = lerp(1, fresnalMask, gb1.x);
                fresnal = lerp(1, fresnal * fresnal, fresnalMask);

                //values for metallic blending
                const float lMet = 0.3f;
                const float hMet = 1.0f;
                const float lSpecCol = 0.0;
                const float hSpecCol = 0.6f;

                //values for smoothness blending
                const float blurL = 0.0f;
                const float blurH = 5.0f;
                const float blurPow = 4;

                //mix colors
                specularColor.xyz = lerp(float3(1, 1, 1), specularColor.xyz, lerp(lSpecCol, hSpecCol, gb1.x));

                float fm = clamp(gb1.x, lMet, hMet);
                float ff = 1 - fm;
                float roughnessBlurAmount = lerp(blurL, blurH, 1 - pow(stepS, blurPow));
                float4 reflectedTexture = tex2Dlod(_MainTex, float4(reflectedUv.xy, 0, roughnessBlurAmount));

                float ao = gb1.y;
                float refw = maskVal * ao * fresnal * luminMask;
                
                float4 blendedColor = maint * ff + (reflectedTexture * specularColor) * fm;

                float4 res = lerp(maint, blendedColor, refw);

                return fixed4(res);
            }
            ENDCG
        }
    
        //reflected color and mask only using hi z tracing
        Pass
        {
            Name "HiZ SSR"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma enable_d3d11_debug_symbols
            #define HIZ_START_LEVEL 0           //normally in good code, you can start and 
                                                //stop at higher levels to improve performance, 
                                                //but my code just shits itself, probably due to not making the depth pyramid correctly
            #define HIZ_MAX_LEVEL 10
            #define HIZ_STOP_LEVEL 0

            #include "UnityCG.cginc"
			#include "NormalSample.hlsl"
            #include "Common.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                return o;
            }

            uniform sampler2D _GBuffer2;
            uniform sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            float3 _WorldSpaceViewDir;
            float _RenderScale;
            float numSteps;
            float minSmoothness;
            int iteration;
            int reflectSky;
            float2 crossEpsilon;
            
            //converts uv coords of padded texture to uv coords of unpadded texture
            inline float2 convertUv(float2 uv) {
                return uv * _PaddedScale;
            }
            //converts uv coords of unpadded texture to uv coords of padded texture
            inline float2 deconvertUv(float2 uv) {
                return uv / _PaddedScale;
            }
            inline uint2 getScreenResolution() {
                return _PaddedResolution;
            }
            inline uint2 getLevelResolution(uint index) {
                uint2 res = getScreenResolution();
                res.x = res.x >> index;
                res.y = res.y >> index;
                return res;
            }
            inline float2 scaledUv(float2 uv, uint index) {
                float2 scaledScreen = getLevelResolution(index);
                float2 realScale = scaledScreen.xy / getScreenResolution();
                uv *= realScale;
                return uv;
            }
            inline float sampleDepth(float2 uv, uint index) {
                uv = scaledUv(uv, index);
                return UNITY_SAMPLE_TEX2DARRAY(_DepthPyramid, float3(uv, index));
            }
            inline float2 cross_epsilon() {
                return crossEpsilon;
            }
            inline float2 cell(float2 ray, float2 cell_count) { 
                return floor(ray.xy * cell_count);
            }
            inline float2 cell_count(float level) {
                float2 res = getLevelResolution(level);
                return res;
            }
            inline bool crossed_cell_boundary(float2 cell_id_one, float2 cell_id_two) {
                return !floatEqApprox(cell_id_one.x, cell_id_two.x) || !floatEqApprox(cell_id_one.y, cell_id_two.y);
            }
            inline float minimum_depth_plane(float2 ray, float level) {

                return sampleDepth(ray, level);
            }
            inline float3 intersectDepthPlane(float3 o, float3 d, float t)
            {
                return o + d * t;
            }
            inline float3 intersectCellBoundary(float3 o, float3 d, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset)
            {
                float2 cell_size = 1.0 / cellCount;
                float2 planes = cellIndex / cellCount + cell_size * crossStep;
                float2 solutions = (planes - o) / d.xy;
                float3 intersection_pos = o + d * min(solutions.x, solutions.y);
                
                intersection_pos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);
                return intersection_pos;
            }
            inline float3 hiZTrace(float thickness, float3 p, float3 v, float MaxIterations, out float hit, out float iterations, out bool isSky)
            {
                const int rootLevel = HIZ_MAX_LEVEL; 
                const int endLevel = HIZ_STOP_LEVEL;
                const int startLevel = HIZ_START_LEVEL;
                int level = HIZ_START_LEVEL;

                iterations = 0;
                isSky = false;
                hit = 0;

                [branch]
                if (v.z <= 0) {
                    return float3(0, 0, 0);
                }

                // scale vector such that z is 1.0f (maximum depth)
                float3 d = v.xyz / v.z;

                // get the cell cross direction and a small offset to enter the next cell when doing cell crossing
                float2 crossStep = float2(d.x >= 0.0f ? 1.0f : -1.0f, d.y >= 0.0f ? 1.0f : -1.0f);
                float2 crossOffset = float2(crossStep.xy * cross_epsilon());
                crossStep.xy = saturate(crossStep.xy);

                // set current ray to original screen coordinate and depth
                float3 ray = p.xyz;

                // cross to next cell to avoid immediate self-intersection
                float2 rayCell = cell(ray.xy, cell_count(level));
                ray = intersectCellBoundary(ray, d, rayCell.xy, cell_count(level), crossStep.xy, crossOffset.xy);

                [loop]
                while (level >= endLevel 
                    && iterations < MaxIterations 
                    && ray.x >= 0 && ray.x < 1
                    && ray.y >= 0 && ray.y < 1
                    && ray.z > 0)
                {
                    isSky = false;

                    // get the cell number of the current ray
                    const float2 cellCount = cell_count(level);
                    const float2 oldCellIdx = cell(ray.xy, cellCount);

                    // get the minimum depth plane in which the current ray resides
                    float minZ = minimum_depth_plane(ray.xy, level);

                    // intersect only if ray depth is below the minimum depth plane
                    float3 tmpRay = ray;

                    float min_minus_ray = minZ - ray.z;

                    tmpRay = min_minus_ray > 0 ? intersectDepthPlane(tmpRay, d, min_minus_ray) : tmpRay;
                    // get the new cell number as well
                    const float2 newCellIdx = cell(tmpRay.xy, cellCount);
                    // if the new cell number is different from the old cell number, a cell was crossed
                    [branch]
                    if (crossed_cell_boundary(oldCellIdx, newCellIdx))
                    {
                        // intersect the boundary of that cell instead, and go up a level for taking a larger step next iteration
                        tmpRay = intersectCellBoundary(ray, d, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy); 
                        level = min(rootLevel, level + 2.0f);
                    }
                    else if (level == startLevel) {
                        float minZOffset = (minZ + (1 - p.z) * thickness);
                        isSky = minZ == 1;
                        [branch]
                        if (reflectSky == 0 && isSky) {
                            break;
                        }
                        [flatten]
                        if (tmpRay.z > minZOffset) {
                            tmpRay = intersectCellBoundary(ray, d, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy);
                            level = HIZ_START_LEVEL + 1;
                        }
                    }
                    // go down a level in the hi-z buffer
                    --level;

                    ray.xyz = tmpRay.xyz;
                    ++iterations;
                }
                hit = level < endLevel ? 1 : 0;
                return ray;
            }
            half3 frag(v2f i) : SV_Target
            {
                float2 tempUv = convertUv(i.uv);

                //since we are working with padded textures, we want avoid working on padded pixels
                [branch]
                if (tempUv.x > 1.0f || tempUv.y > 1.0f) {
                    return float4(0, 0, 0, 0);
                }
                float rawDepth = 1 - sampleDepth(i.uv, 0);
                i.uv = tempUv;

                [branch]
                if (rawDepth == 0) {
                    return float4(i.uv, 0, 0);
                }
                float4 gbuff = tex2D(_GBuffer2, i.uv);
                float smoothness = gbuff.w;
                bool doRayMarch = smoothness > minSmoothness;
                [branch]
                if (!doRayMarch) {
                    return float4(i.uv, 0, 0);
                }
				float3 normal = UnpackNormal(gbuff.xyz);
                float4 clipSpace = float4(i.uv * 2 - 1, rawDepth, 1);
                clipSpace.y *= -1;
                float4 viewSpacePosition = mul(_InverseProjectionMatrix, clipSpace);
                viewSpacePosition /= viewSpacePosition.w;
                float4 worldSpacePosition = mul(_InverseViewMatrix, viewSpacePosition);
                float3 viewDir = normalize(float3(worldSpacePosition.xyz) - _WorldSpaceCameraPos);
                float3 reflectionRay_w = reflect(viewDir, normal);
                float3 reflectionRay_v = mul(_ViewMatrix, float4(reflectionRay_w,0));
                float3 vReflectionEndPosInVS = viewSpacePosition + reflectionRay_v * -viewSpacePosition.z;
                float4 vReflectionEndPosInCS = mul(_ProjectionMatrix, float4(vReflectionEndPosInVS.xyz, 1));
                vReflectionEndPosInCS /= vReflectionEndPosInCS.w;
                vReflectionEndPosInCS.z = 1 - (vReflectionEndPosInCS.z);
                clipSpace.z = 1 - (clipSpace.z);

                float3 outReflDirInTS = normalize((vReflectionEndPosInCS - clipSpace).xyz);
                outReflDirInTS.xy *= float2(0.5f, -0.5f);

                //convert to padded space
                outReflDirInTS.xy = deconvertUv(outReflDirInTS.xy);
                float3 outSamplePosInTS = float3(deconvertUv(i.uv), clipSpace.z);

                float ddd = saturate(dot(_WorldSpaceViewDir, reflectionRay_w));
                float thickness = 0.01f * (1 - ddd);

                float hit = 0;
                float mask = smoothstep(0, 0.1f, ddd);

                [branch]
                if (mask == 0) {
                    return float4(i.uv.xy, 0, 0);
                }

                float iterations;
                bool isSky;
                float3 intersectPoint = hiZTrace(thickness, outSamplePosInTS, outReflDirInTS, numSteps, hit, iterations, isSky);
                
                //convert back to unpadded uv
                float2 realIntersectUv = convertUv(intersectPoint.xy);
                float edgeMask = ScreenEdgeMask(realIntersectUv.xy * 2 - 1);

                mask *= hit * edgeMask;
                return half3(intersectPoint.xy, mask);
            }
            ENDCG
        }
    }
}
