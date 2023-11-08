using LimWorks.Rendering.URP.ScreenSpaceReflections;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace LimWorksEditor.Rendering.ScreenSpaceReflections
{
    [CustomEditor(typeof(LimSSR))]
    public class LimSSREditor : Editor
    {
        private SerializedProperty m_StepStrideLength;
        private SerializedProperty m_MaxSteps;
        private SerializedProperty m_Downsample;
        private SerializedProperty m_MinSmoothness;
        bool HasInit = false;
        private SerializedProperty m_TracingMode;
        private SerializedProperty m_ReflectSky;
        private SerializedProperty m_DitherType;

        private struct Styles
        {
            public static GUIContent TracingMode = EditorGUIUtility.TrTextContent("Trace Mode", "Linear Tracing: Uses less memory at the cost of performance and visual quality. HiZ Tracing: Higher visual quality and performance at the cost of memory.");

            public static GUIContent Downsample =       EditorGUIUtility.TrTextContent("Downsample", "1 / (value + 1) = resolution scale. Higher values increase performance at the cost of visual quality.");
            public static GUIContent StepStrideLength = EditorGUIUtility.TrTextContent("Step Length", "Raymarch step length (IMPACTS VISUAL QUALITY).");
            public static GUIContent MaxSteps =         EditorGUIUtility.TrTextContent("Max Steps", "Maximum length of a raycast (IMPACTS PERFORMANCE).");
            public static GUIContent ReflectSky =         EditorGUIUtility.TrTextContent("Reflect Sky", "Considers the sky as part of the reflection.");
            public static GUIContent MinSmoothness =    EditorGUIUtility.TrTextContent("Min Smoothness", "Minimum smoothness value needed for SSR to be applied.");
            public static GUIContent DitherType =    EditorGUIUtility.TrTextContent("Dither Type", "Dithering Type. Interleaved Gradient for TAA. 8x8 for everything else.");

            public static GUIContent NormalQuality = new GUIContent("Normal Quality", "The number of depth texture samples that Unity takes when computing the normals. Low:1 sample, Medium: 5 samples, High: 9 samples.");
        }
        void Init()
        {
            SerializedProperty settings = serializedObject.FindProperty("Settings");
            m_StepStrideLength = settings.FindPropertyRelative("stepStrideLength");
            m_MaxSteps = settings.FindPropertyRelative("maxSteps");
            m_Downsample = settings.FindPropertyRelative("downSample");
            m_MinSmoothness = settings.FindPropertyRelative("minSmoothness");
            m_TracingMode = settings.FindPropertyRelative("tracingMode");
            m_ReflectSky = settings.FindPropertyRelative("reflectSky");
            m_DitherType = settings.FindPropertyRelative("ditherType");
        }
        bool AssetHasDepthPyramid()
        {
            var pipeline = GraphicsSettings.renderPipelineAsset;
            FieldInfo propertyInfo = pipeline.GetType().GetField("m_RendererDataList", BindingFlags.Instance | BindingFlags.NonPublic);
            var _scriptableRendererData = ((ScriptableRendererData[])propertyInfo?.GetValue(pipeline))?[0];
            var renderObjects = _scriptableRendererData.rendererFeatures;

            bool hasDepthPyramid = false;
            for (int i = 0; i < renderObjects.Count; i++)
            {
                if (renderObjects[i].GetType() == typeof(DepthPyramid))
                {
                    hasDepthPyramid = true;
                    break;
                }
            }
            return hasDepthPyramid;
        }

        public override void OnInspectorGUI()
        {
            if (!HasInit)
            {
                HasInit = true;
                Init();
            }

            EditorGUILayout.PropertyField(m_TracingMode, Styles.TracingMode);
            EditorGUILayout.PropertyField(m_MinSmoothness, Styles.MinSmoothness);
            EditorGUILayout.PropertyField(m_Downsample, Styles.Downsample);

            if (m_TracingMode.enumValueIndex == 0) {
                EditorGUILayout.PropertyField(m_StepStrideLength, Styles.StepStrideLength);
                m_StepStrideLength.floatValue = Mathf.Max(m_StepStrideLength.floatValue, .0001f);
                EditorGUILayout.PropertyField(m_MaxSteps, Styles.MaxSteps);
                m_MaxSteps.floatValue = Mathf.Max(m_MaxSteps.floatValue, 8);
            }
            else
            {
                if (!AssetHasDepthPyramid())
                {
                    var name = typeof(DepthPyramid).FullName;
                    Debug.LogError("Current tracing mode requires " + name + ". Add " + name + " as a render feature.");
                }
                EditorGUILayout.PropertyField(m_MaxSteps, Styles.MaxSteps);
                m_MaxSteps.floatValue = Mathf.Max(Mathf.Floor(m_MaxSteps.floatValue), 8);
                EditorGUILayout.PropertyField(m_ReflectSky, Styles.ReflectSky);
            }
            EditorGUILayout.PropertyField(m_DitherType, Styles.DitherType);
            m_MinSmoothness.floatValue = Mathf.Clamp01(m_MinSmoothness.floatValue);

        }
    }
}
