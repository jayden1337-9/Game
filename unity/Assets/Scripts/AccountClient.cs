using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace ForgottenWorld
{
    public sealed class AccountClient : MonoBehaviour
    {
        [Serializable] private class Credentials { public string username; public string password; }
        [Serializable] private class AuthResponse { public string token; public User user; public string error; }
        [Serializable] private class User { public string id; public string username; }
        [Serializable] private class Profile { public string username; public int coins; public string[] owned_cosmetics; public string equipped_cosmetic; }
        private string serverUrl = "https://YOUR-WISPBYTE-URL";
        private string username = "";
        private string password = "";
        private string token = "";
        private string status = "Not signed in";
        private string profileSummary = "";
        private bool open;
        private bool busy;

        private void Awake()
        {
            serverUrl = PlayerPrefs.GetString("fw_server_url", serverUrl);
            token = PlayerPrefs.GetString("fw_account_token", "");
            username = PlayerPrefs.GetString("fw_username", "");
            if (!string.IsNullOrEmpty(token)) StartCoroutine(LoadProfile());
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.U)) open = !open;
        }

        private void OnGUI()
        {
            if (!open) return;
            float scale = Mathf.Clamp(Screen.width / 1000f, 0.75f, 1.4f);
            Matrix4x4 previous = GUI.matrix;
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(scale, scale, 1));
            GUI.color = new Color(0.86f, 0.77f, 0.59f, 0.98f);
            GUI.Box(new Rect(250, 95, 490, 390), GUIContent.none);
            GUI.color = new Color(0.17f, 0.13f, 0.10f);
            GUI.Label(new Rect(275, 112, 420, 34), "Guild Account", new GUIStyle(GUI.skin.label) { fontSize = 24, fontStyle = FontStyle.Bold });
            GUI.Label(new Rect(275, 153, 420, 22), "Server URL", GUI.skin.label);
            serverUrl = GUI.TextField(new Rect(275, 176, 430, 28), serverUrl);
            GUI.Label(new Rect(275, 210, 420, 22), "Username", GUI.skin.label);
            username = GUI.TextField(new Rect(275, 233, 430, 28), username);
            GUI.Label(new Rect(275, 267, 420, 22), "Password", GUI.skin.label);
            password = GUI.PasswordField(new Rect(275, 290, 430, 28), password, '*');
            GUI.enabled = !busy;
            if (GUI.Button(new Rect(275, 330, 205, 34), "Sign in")) StartCoroutine(Auth(false));
            if (GUI.Button(new Rect(500, 330, 205, 34), "Create account")) StartCoroutine(Auth(true));
            if (GUI.Button(new Rect(275, 374, 430, 30), "Refresh profile")) StartCoroutine(LoadProfile());
            GUI.enabled = true;
            GUI.Label(new Rect(275, 414, 430, 54), status + (string.IsNullOrEmpty(profileSummary) ? "" : "\n" + profileSummary), new GUIStyle(GUI.skin.label) { wordWrap = true });
            if (GUI.Button(new Rect(275, 455, 430, 22), "Close  [U]")) open = false;
            GUI.matrix = previous;
            GUI.color = Color.white;
        }

        private IEnumerator Auth(bool register)
        {
            if (busy) yield break;
            serverUrl = serverUrl.Trim().TrimEnd('/');
            if (!serverUrl.StartsWith("https://") && !serverUrl.StartsWith("http://"))
            {
                status = "Enter a valid server URL.";
                yield break;
            }
            if (string.IsNullOrWhiteSpace(username) || string.IsNullOrEmpty(password))
            {
                status = "Enter your username and password.";
                yield break;
            }
            busy = true;
            PlayerPrefs.SetString("fw_server_url", serverUrl);
            var payload = JsonUtility.ToJson(new Credentials { username = username.Trim(), password = password });
            using (var request = new UnityWebRequest(serverUrl + (register ? "/api/register" : "/api/login"), "POST"))
            {
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(payload);
                request.uploadHandler = new UploadHandlerRaw(bytes);
                request.downloadHandler = new DownloadHandlerBuffer();
                request.SetRequestHeader("Content-Type", "application/json");
                yield return request.SendWebRequest();
                if (request.result != UnityWebRequest.Result.Success)
                    status = "Account request failed: " + (request.downloadHandler == null ? request.error : request.downloadHandler.text);
                else
                {
                    AuthResponse response = JsonUtility.FromJson<AuthResponse>(request.downloadHandler.text);
                    if (response != null && !string.IsNullOrEmpty(response.token))
                    {
                        token = response.token;
                        PlayerPrefs.SetString("fw_account_token", token);
                        PlayerPrefs.SetString("fw_username", username.Trim());
                        PlayerPrefs.Save();
                        status = "Signed in as " + username.Trim();
                        yield return LoadProfile();
                    }
                    else status = response != null ? response.error : "Invalid server response.";
                }
            }
            busy = false;
        }

        private IEnumerator LoadProfile()
        {
            if (busy || string.IsNullOrEmpty(token)) yield break;
            serverUrl = serverUrl.Trim().TrimEnd('/');
            busy = true;
            using (var request = UnityWebRequest.Get(serverUrl + "/api/profile"))
            {
                request.downloadHandler = new DownloadHandlerBuffer();
                request.SetRequestHeader("Authorization", "Bearer " + token);
                yield return request.SendWebRequest();
                if (request.result != UnityWebRequest.Result.Success)
                {
                    status = "Profile unavailable: " + request.error;
                    if (request.responseCode == 401 || request.responseCode == 403)
                    {
                        token = "";
                        PlayerPrefs.DeleteKey("fw_account_token");
                    }
                }
                else
                {
                    Profile profile = JsonUtility.FromJson<Profile>(request.downloadHandler.text);
                    if (profile != null)
                    {
                        status = "Connected as " + profile.username;
                        profileSummary = "Wallet: " + profile.coins + " coins";
                    }
                    else status = "Could not read profile.";
                }
            }
            busy = false;
        }
    }
}
