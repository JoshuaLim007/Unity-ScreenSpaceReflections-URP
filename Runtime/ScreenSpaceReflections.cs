using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
using Unity.Rendering;

namespace LimWorks.Rendering.ScreenSpaceReflections
{
    public struct ScreenSpaceReflectionsSettings
    {
        public float StepStrideLength;
        public float MaxSteps;
        public uint Downsample;
        public uint MinSmoothness;
    }
    [ExecuteAlways]
    public class ScreenSpaceReflections : ScriptableRendererFeature
    {
        public static bool Enabled { get; set; } = true;
        public static void SetSettings(ScreenSpaceReflectionsSettings screenSpaceReflectionsSettings)
        {
            ssrFeatureInstance.Settings = new SSRSettings()
            {
                stepStrideLength = Mathf.Clamp(screenSpaceReflectionsSettings.StepStrideLength, 0.001f, float.MaxValue),
                maxSteps = screenSpaceReflectionsSettings.MaxSteps,
                downSample = screenSpaceReflectionsSettings.Downsample,
                minSmoothness = screenSpaceReflectionsSettings.MinSmoothness,
            };
        }

        [ExecuteAlways]
        public class SsrPass : ScriptableRenderPass
        {
            public RenderTargetIdentifier Source { get; internal set; }
            RenderTargetHandle ReflectionMap;
            RenderTargetHandle tempRenderTarget;

            internal SSRSettings Settings { get; set; }
            float downScaledX;
            float downScaledY;

            public float RenderScale { get; set; }
            public float ScreenHeight { get; set; }
            public float ScreenWidth { get; set; }
            float Scale => Settings.downSample + 1;

            //static RenderTexture tempSource;

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
            {
                base.Configure(cmd, cameraTextureDescriptor);
                ConfigureInput(ScriptableRenderPassInput.Motion | ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Normal);

                cameraTextureDescriptor.colorFormat = RenderTextureFormat.DefaultHDR;
                cameraTextureDescriptor.mipCount = 8;
                cameraTextureDescriptor.autoGenerateMips = true;
                cameraTextureDescriptor.useMipMap = true;

                ReflectionMap.Init("_ReflectedColorMap");

                float downScaler = Scale;
                downScaledX = (ScreenWidth / (float)(downScaler));
                downScaledY = (ScreenHeight / (float)(downScaler));
                cmd.GetTemporaryRT(ReflectionMap.id, Mathf.CeilToInt(downScaledX), Mathf.CeilToInt(downScaledY), 0, FilterMode.Point, RenderTextureFormat.DefaultHDR, RenderTextureReadWrite.Default, 1, false);

                //duplicate source
                cmd.GetTemporaryRT(tempRenderTarget.id, cameraTextureDescriptor, FilterMode.Trilinear);
                cmd.Blit(Source, tempRenderTarget.id);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {

                CommandBuffer commandBuffer = CommandBufferPool.Get("Screen space reflections");

                //calculate reflection
                commandBuffer.Blit(Source, ReflectionMap.id, Settings.SSR_Instance, 0);

                //compose reflection with main texture
                commandBuffer.Blit(tempRenderTarget.id, Source, Settings.SSR_Instance, 1);
                context.ExecuteCommandBuffer(commandBuffer);

                CommandBufferPool.Release(commandBuffer);
            }
            public override void FrameCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(tempRenderTarget.id);
                cmd.ReleaseTemporaryRT(ReflectionMap.id);
            }

        }

        [System.Serializable]
        internal class SSRSettings
        {
            [Min(0.001f)]
            [Tooltip("Raymarch step length (IMPACTS VISUAL QUALITY)")]
            public float stepStrideLength = 0.25f;
            [Tooltip("Maximum length of a raycast (IMPACTS PERFORMANCE) ")]
            public float maxSteps = 32;
            [Tooltip("1 / (value + 1) = resolution scale")]
            public uint downSample = 0;
            [Min(0)]
            [Tooltip("Minimum smoothness value to have ssr work")]
            public float minSmoothness = 0.5f;

            [HideInInspector] public Material SSR_Instance;
            [HideInInspector] public Shader SSRShader;
        }

        SsrPass renderPass = null;
        internal static ScreenSpaceReflections ssrFeatureInstance;
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
            Settings.SSRFragmentShader.SetFloat("_RenderScale", renderingData.cameraData.renderScale);
#endif
            Settings.SSR_Instance.SetMatrix("_InverseProjectionMatrix", projectionMatrix.inverse);
            Settings.SSR_Instance.SetMatrix("_ProjectionMatrix", projectionMatrix);
            Settings.SSR_Instance.SetMatrix("_InverseViewMatrix", viewMatrix.inverse);
            Settings.SSR_Instance.SetMatrix("_ViewMatrix", viewMatrix);
            Settings.SSR_Instance.SetVector("_WorldSpaceViewDir", renderingData.cameraData.camera.transform.forward);

            renderingData.cameraData.camera.depthTextureMode |= (DepthTextureMode.MotionVectors | DepthTextureMode.Depth | DepthTextureMode.DepthNormals);
            float renderscale = renderingData.cameraData.isSceneViewCamera ? 1 : renderingData.cameraData.renderScale;

            renderPass.RenderScale = renderscale;
            renderPass.ScreenHeight = renderingData.cameraData.camera.pixelHeight * renderscale;
            renderPass.ScreenWidth = renderingData.cameraData.camera.pixelWidth * renderscale;
            renderPass.Source = renderer.cameraColorTarget;

            Settings.SSR_Instance.SetFloat("stride", Settings.stepStrideLength);
            Settings.SSR_Instance.SetFloat("numSteps", Settings.maxSteps);
            Settings.SSR_Instance.SetFloat("minSmoothness", Settings.minSmoothness);
            renderer.EnqueuePass(renderPass);
        }

        class PersistantRT
        {
            public RenderTexture[] rt { get; private set; }
            public float previousScreenWidth { get; private set; }
            public float previousScreenHeight { get; private set; }

            int amount;

            public bool HasNull()
            {
                for (int i = 0; i < amount; i++)
                {
                    if (rt[i] == null)
                    {
                        return true;
                    }
                }
                return false;
            }

            public void ReleaseRt()
            {
                for (int i = 0; i < amount; i++)
                {
                    if (rt[i] != null)
                    {
                        rt[i].Release();
                    }
                }
            }
            IList<RenderTextureFormat> renderTextureFormats;
            ~PersistantRT()
            {
                ReleaseRt();
            }
            public PersistantRT(int amount = 1, IList<RenderTextureFormat> textureFormats = null)
            {
                Debug.Log("creating rt");

                this.amount = amount;
                this.renderTextureFormats = textureFormats;
                rt = new RenderTexture[amount];
                for (int i = 0; i < amount; i++)
                {
                    if (textureFormats != null)
                    {
                        rt[i] = new RenderTexture(Screen.width, Screen.height, 0, textureFormats[i]);
                    }
                    else
                    {
                        rt[i] = new RenderTexture(Screen.width, Screen.height, 0, RenderTextureFormat.DefaultHDR);
                    }
                    rt[i].enableRandomWrite = true;
                }
            }
            public void Tick(float screenWidth, float screenHeight)
            {
                if (previousScreenWidth != screenWidth || previousScreenHeight != screenHeight)
                {
                    Debug.Log("readjusting rt");
                    ReleaseRt();
                    for (int i = 0; i < amount; i++)
                    {
                        if (renderTextureFormats != null)
                        {
                            rt[i] = new RenderTexture((int)screenWidth, (int)screenHeight, 0, renderTextureFormats[i]);
                        }
                        else
                        {
                            rt[i] = new RenderTexture((int)screenWidth, (int)screenHeight, 0, RenderTextureFormat.DefaultHDR);
                        }
                        rt[i].enableRandomWrite = true;
                    }
                    previousScreenWidth = screenWidth;
                    previousScreenHeight = screenHeight;
                }
            }
        }

        private bool GetMaterial()
        {
            if (Settings.SSR_Instance != null)
            {
                return true;
            }

            if (Settings.SSRShader == null)
            {
                Settings.SSRShader = Shader.Find("Hidden/SSR_v3");
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
