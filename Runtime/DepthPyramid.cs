using System;
using System.Collections;
using System.Dynamic;
using System.Runtime.ConstrainedExecution;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using static UnityEngine.XR.XRDisplaySubsystem;

namespace LimWorks.Rendering.URP.ScreenSpaceReflections
{
    public class DepthPyramid : ScriptableRendererFeature
    {
        const int buffersize = 11;

        class DepthPyramidPass : ScriptableRenderPass
        {
            internal Settings settings { get; set; }
            const int Threads = 8;
            struct TargetSlice
            {
                internal int slice;
                internal Vector2 resolution;
                internal Vector2 scale;
                public static implicit operator int(TargetSlice target)
                {
                    return target.slice;
                }
            }

            int finalDepthPyramid;

            TargetSlice[] tempSlices;
            //float2[] tempScale;
            //ComputeBuffer sliceScaleBuffer;


            //public void Dispose()
            //{
            //    sliceScaleBuffer.Release();
            //}

            // This method is called before executing the render pass.
            // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
            // When empty this render pass will render to the active camera render target.
            // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
            // The render pipeline will ensure target setup and clearing happens in a performant manner.
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                if (tempSlices == null)
                {
                    tempSlices = new TargetSlice[buffersize];
                    //tempScale = new float2[buffersize];
                    //sliceScaleBuffer = new ComputeBuffer(buffersize, sizeof(float) * 2, ComputeBufferType.Constant, ComputeBufferMode.Dynamic);
                }
                float width = renderingData.cameraData.cameraTargetDescriptor.width;
                float height = renderingData.cameraData.cameraTargetDescriptor.height;

                for (int i = 0; i < buffersize; i++)
                {
                    float d = Mathf.Pow(2, i);
                    tempSlices[i].resolution.x = Mathf.Max(MathF.Floor(width / d), 1);
                    tempSlices[i].resolution.y = Mathf.Max(MathF.Floor(height / d), 1);
                    tempSlices[i].slice = i;
                    tempSlices[i].scale.x = tempSlices[i].resolution.x / width;
                    tempSlices[i].scale.y = tempSlices[i].resolution.y / height;

                    //tempScale[i] = tempSlices[i].scale;
                    //Debug.Log(tempSlices[i].resolution + "_x" + tempSlices[i].scale);
                    //Debug.Log(tempSlices[i].resolution);
                }

                //sliceScaleBuffer.SetData(tempScale);
                //Shader.SetGlobalConstantBuffer("_DepthPyramidScales", sliceScaleBuffer, 0, tempScale.Length);
#if UNITY_2022_1_OR_NEWER
                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraColorTargetHandle);
#else
                ConfigureTarget(renderingData.cameraData.renderer.cameraColorTarget, renderingData.cameraData.renderer.cameraDepthTarget);
#endif
            }
            void SetComputeShader(CommandBuffer cmd, RenderTargetIdentifier tArray, int sSlice, int dSlice, float sW, float sH, float dW, float dH)
            {
                cmd.SetComputeTextureParam(settings.shader, 0, "source", tArray);
                cmd.SetComputeFloatParam(settings.shader, "sx", sW);
                cmd.SetComputeFloatParam(settings.shader, "sy", sH);
                cmd.SetComputeFloatParam(settings.shader, "dx", dW);
                cmd.SetComputeFloatParam(settings.shader, "dy", dH);
                cmd.SetComputeIntParam(settings.shader, "sSlice", sSlice);
                cmd.SetComputeIntParam(settings.shader, "dSlice", dSlice);
            }

            // Here you can implement the rendering logic.
            // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
            // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
            // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                float width = renderingData.cameraData.cameraTargetDescriptor.width;
                float height = renderingData.cameraData.cameraTargetDescriptor.height;
                var cmd = CommandBufferPool.Get("Init Depth Pyramid");
                finalDepthPyramid = Shader.PropertyToID("_DepthPyramid");
                cmd.GetTemporaryRTArray(finalDepthPyramid, (int)width, (int)height, buffersize, 0, FilterMode.Point, RenderTextureFormat.RFloat, RenderTextureReadWrite.Linear, 1, true);
                cmd.SetComputeTextureParam(settings.shader, 1, "source", finalDepthPyramid);
                cmd.DispatchCompute(settings.shader, 1, Mathf.CeilToInt(width / Threads), Mathf.CeilToInt(height / Threads), 1);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);

                cmd = CommandBufferPool.Get("Calculate Depth Pyramid");
                cmd.SetExecutionFlags(CommandBufferExecutionFlags.AsyncCompute);
                for (int i = 0; i < buffersize - 1; i++)
                {
                    //calculate high z depth for the next scaled down buffer
                    SetComputeShader(cmd,
                        finalDepthPyramid,
                        tempSlices[i],
                        tempSlices[i + 1],
                        tempSlices[i].resolution.x,
                        tempSlices[i].resolution.y,
                        tempSlices[i + 1].resolution.x,
                        tempSlices[i + 1].resolution.y
                        );

                    int xGroup = Mathf.Max(Mathf.CeilToInt(tempSlices[i + 1].resolution.x / Threads), 1);
                    int yGroup = Mathf.Max(Mathf.CeilToInt(tempSlices[i + 1].resolution.y / Threads), 1);
                    cmd.DispatchCompute(settings.shader, 0, xGroup, yGroup, 1);
                }
                context.ExecuteCommandBufferAsync(cmd, ComputeQueueType.Background);
                CommandBufferPool.Release(cmd);

#if UNITY_EDITOR
                if (settings.ShowDebug)
                {
                    cmd = CommandBufferPool.Get("Debug Depth Pyramid");
                    int debug = Mathf.Clamp(settings.DebugSlice, 0, buffersize - 1);
#if UNITY_2022_1_OR_NEWER
                    cmd.Blit(finalDepthPyramid, colorAttachmentHandle, Vector2.one * tempSlices[debug].scale, Vector2.zero, debug, 0);
#else
                    cmd.Blit(finalDepthPyramid, colorAttachment, Vector2.one * tempSlices[debug].scale, Vector2.zero, debug, 0);
#endif
                    context.ExecuteCommandBuffer(cmd);
                    CommandBufferPool.Release(cmd);
                }
#endif

            }
            public override void FrameCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(finalDepthPyramid);
            }
        }

        [System.Serializable]
        internal struct Settings
        {
            [HideInInspector] internal ComputeShader shader;
            [SerializeField] internal bool ShowDebug;
            [Range(0, buffersize)]
            [SerializeField] internal int DebugSlice;
        }


        [SerializeField] internal ComputeShader depthPyramidShader;
        [SerializeField] Settings settings = new Settings();
        DepthPyramidPass m_ScriptablePass;

        /// <inheritdoc/>
        public override void Create()
        {
            m_ScriptablePass = new DepthPyramidPass();
            // Configures where the render pass should be injected.
            m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingGbuffer;
            if (settings.ShowDebug)
            {
                m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
            }
        }
        protected override void Dispose(bool disposing)
        {
            //m_ScriptablePass.Dispose();
            m_ScriptablePass = null;
        }

        // Here you can inject one or multiple render passes in the renderer.
        // This method is called when setting up the renderer once per-camera.
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled)
            {
                return;
            }
            settings.shader = depthPyramidShader;
            m_ScriptablePass.settings = this.settings;
#if UNITY_EDITOR && UNITY_2022_1_OR_NEWER
            var d = UnityEngine.Rendering.Universal.UniversalRenderPipelineDebugDisplaySettings.Instance.AreAnySettingsActive;
            if (!d)
            {
                renderer.EnqueuePass(m_ScriptablePass);
            }
#else
            renderer.EnqueuePass(m_ScriptablePass);
#endif
        }
    }
}