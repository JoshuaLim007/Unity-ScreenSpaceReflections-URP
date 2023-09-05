using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
//using Unity.Rendering;

namespace LimWorks.Rendering.URP.ScreenSpaceReflections
{
    public enum RaytraceModes
    {
        LinearTracing = 0,
        HiZTracing = 1,
    }
    public enum DitherMode
    {
        Dither8x8,
        InterleavedGradient,
    }
    public struct ScreenSpaceReflectionsSettings
    {
        /// <summary>
        /// Only applies when TracingMode is set to LinearTracing. Ray march step length.
        /// </summary>
        public float StepStrideLength;
        /// <summary>
        /// Max steps the SSR will perform.
        /// </summary>
        public float MaxSteps;
        /// <summary>
        /// Only applies when TracingMode is set to LinearTracing. Lowers working resolution.
        /// </summary>
        public uint Downsample;
        /// <summary>
        /// Min smoothness value a material needs in order to show SSR
        /// </summary>
        public float MinSmoothness;
        /// <summary>
        /// Tracing mode for SSR
        /// </summary>
        public RaytraceModes TracingMode;
        /// <summary>
        /// Dithering type for SSR
        /// </summary>
        public DitherMode DitherMode;
    }
    [ExecuteAlways]
    public class LimSSR : ScriptableRendererFeature
    {
        public static ScreenSpaceReflectionsSettings GetSettings()
        {
            return new ScreenSpaceReflectionsSettings()
            {
                Downsample = ssrFeatureInstance.Settings.downSample,
                MaxSteps = ssrFeatureInstance.Settings.maxSteps,
                MinSmoothness = ssrFeatureInstance.Settings.minSmoothness,
                StepStrideLength = ssrFeatureInstance.Settings.stepStrideLength,
                TracingMode = ssrFeatureInstance.Settings.tracingMode,
            };
        }
        public static bool Enabled { get; set; } = true;
        public static void SetSettings(ScreenSpaceReflectionsSettings screenSpaceReflectionsSettings)
        {
            ssrFeatureInstance.Settings = new SSRSettings()
            {
                stepStrideLength = Mathf.Clamp(screenSpaceReflectionsSettings.StepStrideLength, 0.001f, float.MaxValue),
                maxSteps = Mathf.Max(screenSpaceReflectionsSettings.MaxSteps, 8),
                downSample = (uint)Mathf.Clamp(screenSpaceReflectionsSettings.Downsample, 0, 2),
                minSmoothness = Mathf.Clamp01(screenSpaceReflectionsSettings.MinSmoothness),
                SSRShader = ssrFeatureInstance.Settings.SSRShader,
                SSR_Instance = ssrFeatureInstance.Settings.SSR_Instance,
                tracingMode = screenSpaceReflectionsSettings.TracingMode
            };
        }

        [System.Obsolete("Use SetSettings to set tracing mode")]
        public static RaytraceModes TracingMode
        {
            get { return ssrFeatureInstance.Settings.tracingMode; }
            set { ssrFeatureInstance.Settings.tracingMode = value; }
        }

        [ExecuteAlways]
        internal class SsrPass : ScriptableRenderPass
        {
            static int frame = 0;
            public RenderTargetIdentifier Source { get; internal set; }
            int reflectionMapID;
            int tempRenderID;
            int tempPaddedSourceID;

            internal SSRSettings Settings { get; set; }

            internal float RenderScale { get; set; }

            private float PaddedScreenHeight;
            private float PaddedScreenWidth;
            private float ScreenHeight;
            private float ScreenWidth;
            private Vector2 PaddedScale;
            bool IsPadded => Settings.tracingMode == RaytraceModes.HiZTracing;
            private float Scale => Settings.tracingMode == RaytraceModes.HiZTracing ? 1 : Settings.downSample + 1;

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
            {
                base.Configure(cmd, cameraTextureDescriptor);
                Settings.SSR_Instance.SetInt("_Frame", frame);
                if (Settings.ditherType == DitherMode.InterleavedGradient)
                {
                    Settings.SSR_Instance.SetInt("_DitherMode", 1);
                }
                else
                {
                    Settings.SSR_Instance.SetInt("_DitherMode", 0);
                }

                ScreenHeight = cameraTextureDescriptor.height;
                ScreenWidth = cameraTextureDescriptor.width;
                PaddedScreenWidth = Settings.tracingMode == RaytraceModes.HiZTracing ? Mathf.NextPowerOfTwo((int)ScreenWidth) : ScreenWidth / Scale;
                PaddedScreenHeight = Settings.tracingMode == RaytraceModes.HiZTracing ? Mathf.NextPowerOfTwo((int)ScreenHeight) : ScreenHeight / Scale;

                cameraTextureDescriptor.colorFormat = RenderTextureFormat.DefaultHDR;
                cameraTextureDescriptor.mipCount = 8;
                cameraTextureDescriptor.autoGenerateMips = true;
                cameraTextureDescriptor.useMipMap = true;

                reflectionMapID = Shader.PropertyToID("_ReflectedColorMap");

                Vector2 screenResolution = new Vector2(ScreenWidth, ScreenHeight);
                Settings.SSR_Instance.SetVector("_ScreenResolution", screenResolution);
                if (IsPadded)
                {
                    Vector2 paddedResolution = new Vector2(PaddedScreenWidth, PaddedScreenHeight);
                    PaddedScale = paddedResolution / screenResolution;
                    Settings.SSR_Instance.SetVector("_PaddedResolution", paddedResolution);
                    Settings.SSR_Instance.SetVector("_PaddedScale", PaddedScale);
                }
                else
                {
                    Settings.SSR_Instance.SetVector("_PaddedScale", Vector2.one);
                }

                cmd.GetTemporaryRT(reflectionMapID, Mathf.CeilToInt(PaddedScreenWidth), Mathf.CeilToInt(PaddedScreenHeight), 0, FilterMode.Point, RenderTextureFormat.DefaultHDR, RenderTextureReadWrite.Default, 1, false);

                tempRenderID = Shader.PropertyToID("_TempTex");
                cmd.GetTemporaryRT(tempRenderID, cameraTextureDescriptor, FilterMode.Trilinear);

                if (IsPadded)
                {
                    tempPaddedSourceID = Shader.PropertyToID("_TempPaddedSource");
                    cameraTextureDescriptor.width = (int)PaddedScreenWidth;
                    cameraTextureDescriptor.height = (int)PaddedScreenHeight;
                    cmd.GetTemporaryRT(tempPaddedSourceID, cameraTextureDescriptor, FilterMode.Trilinear);
                }
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer commandBuffer = CommandBufferPool.Get("Screen space reflections");
                if (IsPadded)
                {
                    commandBuffer.Blit(Source, tempPaddedSourceID, PaddedScale, Vector2.zero);
                }
                //calculate reflection
                if (Settings.tracingMode == RaytraceModes.HiZTracing)
                {
                    commandBuffer.Blit(tempPaddedSourceID, reflectionMapID, Settings.SSR_Instance, 2);
                }
                else
                {
                    commandBuffer.Blit(Source, reflectionMapID, Settings.SSR_Instance, 0);
                }

                //compose reflection with main texture
                if (IsPadded)
                {
                    commandBuffer.Blit(tempPaddedSourceID, Source, Settings.SSR_Instance, 1);
                }
                else
                {
                    commandBuffer.Blit(Source, tempRenderID);
                    commandBuffer.Blit(tempRenderID, Source, Settings.SSR_Instance, 1);
                }
                
                commandBuffer.ReleaseTemporaryRT(tempRenderID);
                commandBuffer.ReleaseTemporaryRT(reflectionMapID);
                commandBuffer.ReleaseTemporaryRT(tempPaddedSourceID);

                context.ExecuteCommandBuffer(commandBuffer);
                CommandBufferPool.Release(commandBuffer);
            }
            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(tempRenderID);
                cmd.ReleaseTemporaryRT(reflectionMapID);
                cmd.ReleaseTemporaryRT(tempPaddedSourceID);
                frame++;
            }
        }

        [System.Serializable]
        internal class SSRSettings
        {
            public RaytraceModes tracingMode = RaytraceModes.LinearTracing;
            public float stepStrideLength = .03f;
            public float maxSteps = 128;
            public uint downSample = 0;
            public float minSmoothness = 0.5f;
            public bool reflectSky = true;
            public DitherMode ditherType = DitherMode.InterleavedGradient;
            [HideInInspector] public Material SSR_Instance;
            [HideInInspector] public Shader SSRShader;
        }

        internal SsrPass renderPass = null;
        internal static LimSSR ssrFeatureInstance;
        [SerializeField] SSRSettings Settings = new SSRSettings();

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled || !Enabled)
            {
                return;
            }

            if(!GetMaterial())
            {
                Debug.LogError("Cannot find ssr shader!");
                return;
            }

#if UNITY_2022_1_OR_NEWER
#else
            SetMaterialProperties(in renderingData);
            renderPass.Source = renderer.cameraColorTarget;
#endif
            Settings.SSR_Instance.SetVector("_WorldSpaceViewDir", renderingData.cameraData.camera.transform.forward);

            renderingData.cameraData.camera.depthTextureMode |= (DepthTextureMode.MotionVectors | DepthTextureMode.Depth | DepthTextureMode.DepthNormals);
            float renderscale = renderingData.cameraData.isSceneViewCamera ? 1 : renderingData.cameraData.renderScale;

            renderPass.RenderScale = renderscale;

            Settings.SSR_Instance.SetFloat("stride", Settings.stepStrideLength);
            Settings.SSR_Instance.SetFloat("numSteps", Settings.maxSteps);
            Settings.SSR_Instance.SetFloat("minSmoothness", Settings.minSmoothness);
            Settings.SSR_Instance.SetInt("reflectSky", Settings.reflectSky ? 1 : 0);
#if UNITY_EDITOR && UNITY_2022_1_OR_NEWER
            var d = UnityEngine.Rendering.Universal.UniversalRenderPipelineDebugDisplaySettings.Instance.AreAnySettingsActive;
            if (!d)
            {
                renderer.EnqueuePass(renderPass);
            }
#else
            renderer.EnqueuePass(renderPass);
#endif
        }

#if UNITY_2022_1_OR_NEWER
        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled || !Enabled)
            {
                return;
            }
            if (!GetMaterial())
            {
                Debug.LogError("Cannot find ssr shader!");
                return;
            }

            SetMaterialProperties(in renderingData);
            renderPass.Source = renderer.cameraColorTargetHandle;
        }
#endif
        //Called from SetupRenderPasses in urp 13+ (2022.1+). called from AddRenderPasses in URP 12 (2021.3)
        void SetMaterialProperties(in RenderingData renderingData)
        {
            var projectionMatrix = renderingData.cameraData.GetGPUProjectionMatrix();
            var viewMatrix = renderingData.cameraData.GetViewMatrix();

#if UNITY_EDITOR
            if (renderingData.cameraData.isSceneViewCamera)
            {
                Settings.SSR_Instance.SetFloat("_RenderScale", 1);
            }
            else
            {
                Settings.SSR_Instance.SetFloat("_RenderScale", renderingData.cameraData.renderScale);
            }
#else
            Settings.SSR_Instance.SetFloat("_RenderScale", renderingData.cameraData.renderScale);
#endif
            Settings.SSR_Instance.SetMatrix("_InverseProjectionMatrix", projectionMatrix.inverse);
            Settings.SSR_Instance.SetMatrix("_ProjectionMatrix", projectionMatrix);
            Settings.SSR_Instance.SetMatrix("_InverseViewMatrix", viewMatrix.inverse);
            Settings.SSR_Instance.SetMatrix("_ViewMatrix", viewMatrix);
        }


        private bool GetMaterial()
        {
            if (Settings.SSR_Instance != null)
            {
                return true;
            }

            if (Settings.SSRShader == null)
            {
                Settings.SSRShader = Shader.Find("Hidden/ssr_shader");
                if (Settings.SSRShader == null)
                {
                    return false;
                }
            }

            Settings.SSR_Instance = CoreUtils.CreateEngineMaterial(Settings.SSRShader);

            return Settings.SSR_Instance != null;
        }
        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(Settings.SSR_Instance);
        }
        public override void Create()
        {
            ssrFeatureInstance = this;
            renderPass = new SsrPass()
            {
                renderPassEvent = RenderPassEvent.AfterRenderingTransparents,
                Settings = this.Settings
            };
            GetMaterial();
        }
    }
}
