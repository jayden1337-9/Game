#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace ForgottenWorld.Editor
{
    public static class BuildWindows
    {
        public static void Build()
        {
            const string scene = "Assets/Scenes/Main.unity";
            if (!File.Exists(scene)) throw new FileNotFoundException("Main scene is missing", scene);
            Directory.CreateDirectory("Build/Windows");
            var options = new BuildPlayerOptions
            {
                scenes = new[] { scene },
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
