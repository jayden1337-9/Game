#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace ForgottenWorld.Editor
{
    public static class BuildWindows
    {
        public static void Build()
        {
            const string scenePath = "Assets/Scenes/Main.unity";
            Directory.CreateDirectory("Assets/Scenes");
            PlayerSettings.activeInputHandler = ActiveInputHandler.InputManager;
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            scene.name = "ForgottenWorld";
            EditorSceneManager.SaveScene(scene, scenePath);
            AssetDatabase.Refresh();

            Directory.CreateDirectory("Build/Windows");
            var options = new BuildPlayerOptions
            {
                scenes = new[] { scenePath },
                locationPathName = "Build/Windows/ForgottenWorld.exe",
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None
            };
            BuildReport report = BuildPipeline.BuildPlayer(options);
            if (report.summary.result != BuildResult.Succeeded)
                throw new System.Exception("Windows build failed: " + report.summary.result);
            Debug.Log("Forgotten World Windows build complete: " + report.summary.totalSize + " bytes");
        }
    }
}
#endif
