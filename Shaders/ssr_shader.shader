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
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local TEMPORAL

            #include "UnityCG.cginc"

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

            float4x4 _InverseProjectionMatrix;
            float4x4 _InverseViewMatrix;
            float4x4 _ProjectionMatrix;
            float4x4 _ViewMatrix;

            uniform sampler2D _MainTex;
            uniform sampler2D _GBuffer2; //normals and smoothness

            float3 _WorldSpaceViewDir;
            float _RenderScale;
            float stride;
            float numSteps;
            float minSmoothness;
            int iteration;

            inline float ScreenEdgeMask(float2 clipPos) {
                float yDif = 1 - abs(clipPos.y);
                float xDif = 1 - abs(clipPos.x);
                [flatten]
                if (yDif < 0 || xDif < 0) {
                    return 0;
                }
                float t1 = smoothstep(0, .25, yDif);
                float t2 = smoothstep(0, .1, xDif);
                return saturate(t2 * t1);
            }
            //inline float IGN(int pixelX, int pixelY, int frame)
            //{
            //    frame = frame % 64; // need to periodically reset frame to avoid numerical issues
            //    float x = float(pixelX) + 5.588238f * float(frame);
            //    float y = float(pixelY) + 5.588238f * float(frame);
            //    return fmod(52.9829189f * fmod(0.06711056f * float(x) + 0.00583715f * float(y), 1.0f), 1.0f);
            //}
            float4 frag(v2f i) : SV_Target
            {
                float rawDepth = tex2D(_CameraDepthTexture, i.uv).r;
                [branch]
                if (rawDepth == 0) {
                    return float4(0, 0, 0, 0);
                }
                float4 gbuff = tex2D(_GBuffer2, i.uv);
                float smoothness = gbuff.w;
                float stepS = smoothstep(minSmoothness, 1, smoothness);
                float3 normal = normalize(gbuff.xyz);

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

                float normalViewDot = dot(normal, -viewDir);
                float viewReflectDot = saturate(dot(viewDir, reflectionRay));
                float cameraViewReflectDot = saturate(dot(_WorldSpaceViewDir, reflectionRay));

                float thickness = stride * 2;
                float oneMinusViewReflectDot = sqrt(1 - viewReflectDot);
                stride /= oneMinusViewReflectDot;
                thickness /= oneMinusViewReflectDot;


                int d = 0;
                int hit = 0;
                float maskOut = 1;
                float3 currentPosition = viewSpacePosition.xyz;
                float2 currentScreenSpacePosition = i.uv;

                bool doRayMarch = smoothness > minSmoothness;

                float maxRayLength = numSteps * stride;
                float maxDist = lerp(min(viewSpacePosition.z, maxRayLength), maxRayLength, cameraViewReflectDot);
                float numSteps_f = maxDist / stride;
                numSteps = max(round(numSteps_f),0);

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
                            if (depthDelta > 0) {
                                currentScreenSpacePosition = uv.xy;
                                hit = 1;
                                break;
                            }
                        }
                    }

                    if (depthDelta > thickness) {
                        hit = 0;
                    }

                    const int stepCount = 16;
                    int binarySearchSteps = stepCount * hit;

                    [loop]
                    for (int i = 0; i < binarySearchSteps; i++)
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
                        float minv = 1 / (oneMinusViewReflectDot * float(i));
                        if (abs(depthDelta) > minv) {
                            hit = 0;
                            break;
                        }
                    }

                    //remove backface intersections
                    float3 currentNormal = tex2D(_GBuffer2, currentScreenSpacePosition).xyz;
                    float backFaceDot = dot(currentNormal, reflectionRay);
                    [flatten]
                    if (backFaceDot > 0) {
                        hit = 0;
                    }

                }

                float3 deltaDir = viewSpacePosition.xyz - currentPosition;
                float progress = dot(deltaDir, deltaDir) / (maxDist * maxDist);
                progress = smoothstep(0, .5, 1 - progress);

                float pf = pow(smoothness, 4);
                float fresnal = lerp(pf, 1.0, pow(viewReflectDot, 1 / pf));
                maskOut *= stepS * hit * fresnal;

                return float4(currentScreenSpacePosition, stepS, maskOut * progress);
            }
            ENDCG
        }
    
        //composite
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local TEMPORAL

            #include "UnityCG.cginc"

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
            inline float Dither8x8(float2 ScreenPosition, float c0)
            {
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

                float2 uv = ScreenPosition.xy * _ScreenParams.xy;

                uint index = (uint(uv.x) % 8) * 8 + uint(uv.y) % 8;

                float limit = float(dither[index] + 1) / 64.0;
                return (c0 - limit) * 0.5 + 0.5;
            }
            


            uniform sampler2D _GBuffer1; //metalness color
            uniform sampler2D _ReflectedColorMap;   //contains reflected uv coordinates
            uniform sampler2D _MainTex;     //main screen color
            uniform sampler2D _GBuffer2; //normals and smoothness
            float4x4 _InverseProjectionMatrix;
            float4x4 _InverseViewMatrix;
            float4x4 _ProjectionMatrix;
            float4x4 _ViewMatrix;

            float4 frag(v2f i) : SV_Target
            {
                float dither = Dither8x8(i.uv.xy * _RenderScale, 0);
                float ditherDiry = ((floor(i.uv.y * _RenderScale * _ScreenParams.y)) % 2) * 2 - 1;

                float4 maint = tex2D(_MainTex, i.uv);
                float4 reflectedUv = tex2D(_ReflectedColorMap, i.uv);
                float4 normal = tex2D(_GBuffer2, i.uv);
                normal = mul(_ViewMatrix, float4(normal.xyz,0));
                normal = mul(_ProjectionMatrix, float4(normal.xyz,0));
                normal.y *= -1;

                float stepS = reflectedUv.z;

                reflectedUv += normal * lerp(dither * 0.05f, 0, stepS) * ditherDiry;

                float maskVal = saturate(reflectedUv.w);

                float lumin = Luminance(maint);
                lumin -= 1;
                lumin = saturate(lumin);

                float4 gb1 = tex2D(_GBuffer1, i.uv.xy);     

                float fm = clamp(gb1.r, .3, 1);     //smoothness and metalness
                fm = clamp(fm, 0, 1 - lumin);
                float ff = 1 - fm;

                float4 reflectedTexture = tex2Dlod(_MainTex, float4(reflectedUv.xy,0, lerp(0, 4, 1 - stepS)));

                float ao = gb1.a;
                float refw = maskVal * ao;
                float4 res = lerp(maint, maint * ff + reflectedTexture * fm, refw);

                //return reflectedUv;
                return res;
            }
            ENDCG
        }
    
        //reflected color and mask only using hi z tracing
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #define HIZ_START_LEVEL 0
            #define HIZ_MAX_LEVEL 10
            #define HIZ_STOP_LEVEL 0
            #define MAX_ITERATIONS 256

            #include "UnityCG.cginc"

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

            float4x4 _InverseProjectionMatrix;
            float4x4 _InverseViewMatrix;
            float4x4 _ProjectionMatrix;
            float4x4 _ViewMatrix;

            UNITY_DECLARE_TEX2DARRAY(_DepthPyramid);
            uniform Buffer<float2> _DepthPyramidScales;
            uniform sampler2D _GBuffer2;
            uniform sampler2D _CameraDepthTexture;
            uniform sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            float3 _WorldSpaceViewDir;
            float _RenderScale;
            float stride;
            float numSteps;
            float minSmoothness;
            int iteration;
            int reflectSky;

            float2 getResolution(int index) {
                float scale = exp2(index);
                float2 scaledScreen = _ScreenParams.xy / scale;
                //scaledScreen.xy = max(floor(scaledScreen.xy), float2(1,1));
                return scaledScreen.xy;
            }
            inline float2 scaledUv(float2 uv, int index) {
                float2 scaledScreen = getResolution(index);
                float2 realScale = scaledScreen.xy / _ScreenParams.xy;
                uv *= realScale;
                return uv;
            }
            inline float SampleDepth(float2 uv, int index) {
                uv = scaledUv(uv, index);
                return UNITY_SAMPLE_TEX2DARRAY(_DepthPyramid, float3(uv, index));
            }
            inline float2 cross_epsilon() {
                //float2 scale = _ScreenParams.xy / getResolution(HIZ_START_LEVEL + 1);
                //return float2(_MainTex_TexelSize.xy * scale);
                return float2(1 / _ScreenParams.xy / 128);
            }
            inline float2 cell(float2 ray, float2 cell_count) { 
                return floor(ray.xy * cell_count);
            }
            inline float2 cell_count(float level) {
                float2 res = getResolution(level);
                return res; //_ScreenParams.xy / exp2(level);
            }
            inline bool crossed_cell_boundary(float2 cell_id_one, float2 cell_id_two) {
                return (int)cell_id_one.x != (int)cell_id_two.x || (int)cell_id_one.y != (int)cell_id_two.y;
            }
            inline float minimum_depth_plane(float2 ray, float level, float2 cell_count) {

                return SampleDepth(ray, level);
            }
            inline float3 intersectDepthPlane(float3 o, float3 d, float t)
            {
                return o + d * t;
            }
            inline float3 intersectCellBoundary(float3 o, float3 d, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset, float iteration)
            {
                float2 cell_size = 1.0 / cellCount;
                float2 planes = cellIndex / cellCount + cell_size * crossStep;
                float2 solutions = (planes - o) / d.xy;
                float3 intersection_pos = o + d * min(solutions.x, solutions.y);
                crossOffset.xy *= 50;
                intersection_pos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);
                return intersection_pos;

                //float2 cell_size = 1.0 / cellCount;
                //float2 planes = cellIndex / cellCount + cell_size * crossStep + crossOffset * 50;
                //float2 solutions = (planes - o.xy) / d.xy;
                //float3 intersection_pos = o + d * min(solutions.x, solutions.y);
                //return intersection_pos;
            }


            float3 hiZTrace(float3 p, float3 v, out float hit, out float iterations, out bool isSky)
            {
                const float rootLevel = HIZ_MAX_LEVEL; 
                float level = HIZ_START_LEVEL;

                iterations = 0;
                isSky = false;
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

                ray = intersectCellBoundary(ray, d, rayCell.xy, cell_count(level), crossStep.xy, crossOffset.xy, 0);

                [loop]
                while (level >= HIZ_STOP_LEVEL && iterations < MAX_ITERATIONS)
                {
                    // get the cell number of the current ray
                    const float2 cellCount = cell_count(level);
                    const float2 oldCellIdx = cell(ray.xy, cellCount);

                    // get the minimum depth plane in which the current ray resides
                    float minZ = minimum_depth_plane(ray.xy, level, rootLevel);

                    // intersect only if ray depth is below the minimum depth plane
                    float3 tmpRay = ray;

                    [branch]
                    if (v.z > 0) {
                        float min_minus_ray = minZ - ray.z;

                        tmpRay = min_minus_ray > 0 ? intersectDepthPlane(tmpRay, d, min_minus_ray) : tmpRay;
                        // get the new cell number as well
                        const float2 newCellIdx = cell(tmpRay.xy, cellCount);
                        // if the new cell number is different from the old cell number, a cell was crossed
                        if (crossed_cell_boundary(oldCellIdx, newCellIdx))
                        {
                            // intersect the boundary of that cell instead, and go up a level for taking a larger step next iteration
                            tmpRay = intersectCellBoundary(ray, d, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy, iterations); //// NOTE added .xy to o and d arguments
                            level = min(HIZ_MAX_LEVEL, level + 2.0f);
                        }
                        else if(level == HIZ_START_LEVEL) {
                            float minZOffset = (minZ + (_ProjectionParams.y * 0.0025) / LinearEyeDepth(1 - p.z));

                            isSky = minZ == 1 ? true : false;

                            [branch]
                            if (tmpRay.z > minZOffset || (reflectSky == 0 && isSky)) {
                                break;
                            }
                        }
                    }
                    else if(v.z < minZ) {
                        tmpRay = intersectCellBoundary(ray, d, oldCellIdx, cellCount, crossStep, crossOffset, iterations);
                        level = min(HIZ_MAX_LEVEL, level + 2.0f);
                    }
                    
                    // go down a level in the hi-z buffer
                    --level;

                    ray.xyz = tmpRay.xyz;
                    ++iterations;
                }
                hit = level < HIZ_STOP_LEVEL ? 1 : 0;
                return ray;
            }

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

            float4 frag(v2f i) : SV_Target
            {

                float rawDepth = tex2D(_CameraDepthTexture, i.uv).r;

                [branch]
                if (rawDepth == 0) {
                    return float4(i.uv.xy, 0, 0);
                }
                float4 gbuff = tex2D(_GBuffer2, i.uv);
                float smoothness = gbuff.w;
                bool doRayMarch = smoothness > minSmoothness;
                [branch]
                if (!doRayMarch) {
                    return float4(i.uv.xy, 0, 0);
                }
                float stepS = smoothstep(minSmoothness, 1, smoothness);
                float3 normal = normalize(gbuff.xyz);

                float4 clipSpace = float4(i.uv * 2 - 1, rawDepth, 1);
                clipSpace.y *= -1;

                float4 viewSpacePosition = mul(_InverseProjectionMatrix, clipSpace);
                viewSpacePosition /= viewSpacePosition.w;
                float4 worldSpacePosition = mul(_InverseViewMatrix, viewSpacePosition);
                float3 viewDir = normalize(float3(worldSpacePosition.xyz) - _WorldSpaceCameraPos);
                float3 reflectionRay_w = reflect(viewDir, normal);
                float3 reflectionRay_v = mul(_ViewMatrix, float4(reflectionRay_w,0));


                float3 vReflectionEndPosInVS = viewSpacePosition + reflectionRay_v * (viewSpacePosition.z * -1);
                float4 vReflectionEndPosInCS = mul(_ProjectionMatrix, float4(vReflectionEndPosInVS.xyz, 1));
                vReflectionEndPosInCS /= vReflectionEndPosInCS.w;


                vReflectionEndPosInCS.z = 1 - (vReflectionEndPosInCS.z);
                clipSpace.z = 1 - (clipSpace.z);

                float3 outReflDirInTS = normalize((vReflectionEndPosInCS - clipSpace).xyz);
                outReflDirInTS.xy *= float2(0.5f, -0.5f);
                float3 outSamplePosInTS = float3(i.uv, clipSpace.z);

                float viewNormalDot = dot(-viewDir, normal);
                float viewReflectDot = 1 - saturate(dot(-viewDir, reflectionRay_w));
                float ddd = saturate(dot(_WorldSpaceViewDir, reflectionRay_w));

                float hit = 0;
                float mask = smoothstep(0, 0.1f, ddd);

                [branch]
                if (mask == 0) {
                    return float4(i.uv.xy, 0, 0);
                }

                float iterations;
                bool isSky;
                float3 intersectPoint = hiZTrace(outSamplePosInTS, outReflDirInTS, hit, iterations, isSky);
                float edgeMask = ScreenEdgeMask(intersectPoint.xy * 2 - 1);
                mask *= hit * edgeMask;

                //remove backface intersections
                float3 currentNormal = tex2D(_GBuffer2, intersectPoint.xy).xyz;
                float backFaceDot = dot(currentNormal, reflectionRay_w);
                mask = backFaceDot > 0 && !isSky ? 0 : mask;

                //float4 color = tex2D(_MainTex, intersectPoint.xy);
                return float4(intersectPoint.xy, stepS, mask * stepS);
                //return float4(SampleDepth(i.uv, 7),0,0,0);
                //return float4(mcolor * (1 - mask) + color * mask);
                //return float4(mask,0,0,0);
                //return float4(iterations / MAX_ITERATIONS,0,0,0);
            }
            ENDCG
        }
    }
}
