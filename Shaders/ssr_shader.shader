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

            float4 frag(v2f i) : SV_Target
            {



                float rawDepth = tex2D(_CameraDepthTexture, i.uv).r;
                [branch]
                if (Linear01Depth(rawDepth) == 1) {
                    return float4(0, 0, 0, 0);
                }
                float4 gbuff = tex2D(_GBuffer2, i.uv);
                float smoothness = gbuff.w;
                float stepS = smoothstep(minSmoothness, 1, smoothness);
                gbuff = tex2D(_GBuffer2, i.uv);
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

                stride /= sqrt(1 - viewReflectDot);
                thickness /= sqrt(1 - viewReflectDot);


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

                    const int stepCount = 8;
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
                        if (abs(depthDelta) > 1 / float(i)) {
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

                [flatten]
                if (hit == 0) {
                    maskOut = 0;
                }
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
                float ditherDiry = ((int(i.uv.y * _RenderScale * _ScreenParams.y)) % 2) * 2 - 1;

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
    }
}
