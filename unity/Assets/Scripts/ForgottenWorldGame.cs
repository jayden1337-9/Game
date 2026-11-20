using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace ForgottenWorld
{
    public class ForgottenWorldGame : MonoBehaviour
    {
        [Serializable] private class SaveData
        {
            public int coins, wood, stone, gel, crystal, companions;
            public string skin = "Wayfarer";
        }

        private static readonly Color Parchment = new Color(0.88f, 0.79f, 0.61f);
        private static readonly Dictionary<string, Sprite> SpriteCache = new Dictionary<string, Sprite>();
        private readonly string[] skins = { "Wayfarer", "Forest Warden", "Royal Guard", "Frostbound" };
        private SaveData save = new SaveData();
        private Rigidbody2D body;
        private Transform playerTransform;
        private SpriteRenderer playerRenderer;
        private Camera gameCamera;
        private float autosave;
        private bool inventoryOpen;
        private string notice = "Welcome, wayfarer. Explore the Elderwood.";
        private GUIStyle titleStyle, bodyStyle, buttonStyle;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Bootstrap()
        {
            if (FindObjectOfType<ForgottenWorldGame>() != null) return;
            new GameObject("Forgotten World").AddComponent<ForgottenWorldGame>();
        }

        private void Awake()
        {
            Application.targetFrameRate = 60;
            LoadGame();
            BuildCamera();
            BuildWorld();
            BuildPlayer();
            foreach (ForestSlime slime in FindObjectsOfType<ForestSlime>()) slime.Initialize(playerTransform);
            gameObject.AddComponent<AccountClient>();
            BuildStyles();
        }

        private void Update()
        {
            if (body == null) return;
            float move = 0f;
            if (Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.LeftArrow)) move -= 1f;
            if (Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.RightArrow)) move += 1f;
            body.velocity = new Vector2(move * 5.2f, body.velocity.y);
            if ((Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.W) || Input.GetKeyDown(KeyCode.UpArrow)) && Mathf.Abs(body.velocity.y) < 0.05f)
                body.velocity = new Vector2(body.velocity.x, 10.5f);
            if (Input.GetKeyDown(KeyCode.I)) inventoryOpen = !inventoryOpen;
            if (Input.GetKeyDown(KeyCode.E)) GatherNearby();
            if (Input.GetKeyDown(KeyCode.F)) BefriendNearbySlime();

            autosave += Time.deltaTime;
            if (autosave >= 20f) { autosave = 0f; SaveGame(); }
            if (gameCamera != null)
            {
                Vector3 target = new Vector3(playerTransform.position.x, Mathf.Max(2f, playerTransform.position.y + 1.4f), -10f);
                gameCamera.transform.position = Vector3.Lerp(gameCamera.transform.position, target, Time.deltaTime * 4f);
            }
        }

        private void BuildCamera()
        {
            var camObject = new GameObject("Main Camera");
            gameCamera = camObject.AddComponent<Camera>();
            gameCamera.orthographic = true;
            gameCamera.orthographicSize = 6f;
            gameCamera.backgroundColor = new Color(0.31f, 0.40f, 0.40f);
            camObject.tag = "MainCamera";
        }

        private void BuildWorld()
        {
            var world = new GameObject("World - Elderwood");
            for (int x = -90; x <= 90; x++)
            {
                int surface = Mathf.RoundToInt(0.35f * Mathf.Sin(x * 0.11f) + 0.2f * Mathf.Sin(x * 0.037f));
                for (int y = -8; y <= surface; y++)
                {
                    Color c = y == surface ? new Color(0.32f, 0.42f, 0.25f) :
                        y > surface - 3 ? new Color(0.43f, 0.29f, 0.19f) : new Color(0.30f, 0.30f, 0.31f);
                    MakeBlock(world.transform, x, y, c, 0);
                }
                if (x % 13 == 0) MakeTree(world.transform, x, surface + 1);
                if (x % 19 == 7) MakeCrystal(world.transform, x, surface + 1);
                if (x % 17 == 5) MakeSlime(world.transform, x, surface + 1);
            }
            var hill = new GameObject("Distant hills");
            hill.transform.position = new Vector3(0, 1.4f, 5);
            var hillRenderer = hill.AddComponent<SpriteRenderer>();
            hillRenderer.sprite = PixelSprite(new Color(0.24f, 0.34f, 0.31f), 64, 24);
            hill.transform.localScale = new Vector3(35, 4, 1);
        }

        private void MakeTree(Transform parent, int x, int y)
        {
            for (int h = 0; h < 4; h++) MakeBlock(parent, x, y + h, new Color(0.30f, 0.19f, 0.12f), 1, false, h == 0 ? "wood" : null);
            for (int dx = -2; dx <= 2; dx++)
                for (int dy = 3; dy <= 6; dy++)
                    if (Mathf.Abs(dx) + Mathf.Abs(dy - 4) < 4)
                        MakeBlock(parent, x + dx, y + dy, new Color(0.23f, 0.36f, 0.22f), 1, false);
        }

        private void MakeCrystal(Transform parent, int x, int y)
        {
            MakeBlock(parent, x, y, new Color(0.34f, 0.66f, 0.69f), 2, false, "crystal");
            MakeBlock(parent, x, y + 1, new Color(0.45f, 0.78f, 0.78f), 2, false);
        }

        private void MakeSlime(Transform parent, int x, int y)
        {
            var enemy = new GameObject("Elderwood Slime");
            enemy.transform.SetParent(parent);
            enemy.transform.position = new Vector3(x, y + 0.35f, 0);
            var renderer = enemy.AddComponent<SpriteRenderer>();
            renderer.sprite = PixelSprite(new Color(0.40f, 0.63f, 0.34f), 15, 11);
            renderer.sortingOrder = 4;
            enemy.AddComponent<CircleCollider2D>().isTrigger = true;
            enemy.AddComponent<ForestSlime>().Initialize(transform);
        }

        private void MakeBlock(Transform parent, int x, int y, Color color, int sortingOrder, bool solid = true, string resource = null)
        {
            var go = new GameObject(solid ? "Ground tile" : "World prop");
            go.transform.SetParent(parent);
            go.transform.position = new Vector3(x, y, 0);
            var sr = go.AddComponent<SpriteRenderer>();
            sr.sprite = PixelSprite(color);
            sr.sortingOrder = sortingOrder;
            if (solid) go.AddComponent<BoxCollider2D>();
            if (!string.IsNullOrEmpty(resource))
            {
                var trigger = go.AddComponent<BoxCollider2D>();
                trigger.isTrigger = true;
                go.AddComponent<ResourceNode>().resource = resource;
            }
        }

        private void BuildPlayer()
        {
            var go = new GameObject("Player - " + save.skin);
            go.transform.position = new Vector2(0, 3.2f);
            playerTransform = go.transform;
            playerRenderer = go.AddComponent<SpriteRenderer>();
            playerRenderer.sprite = SkinSprite(save.skin);
            playerRenderer.sortingOrder = 5;
            body = go.AddComponent<Rigidbody2D>();
            body.freezeRotation = true;
            body.gravityScale = 3f;
            var collider = go.AddComponent<CapsuleCollider2D>();
            collider.size = new Vector2(0.65f, 1.2f);
        }

        private Sprite PixelSprite(Color color, int width = 16, int height = 16)
        {
            string key = ColorUtility.ToHtmlStringRGBA(color) + "_" + width + "x" + height;
            if (SpriteCache.TryGetValue(key, out Sprite cached)) return cached;
            var texture = new Texture2D(width, height, TextureFormat.RGBA32, false);
            texture.filterMode = FilterMode.Point;
            var pixels = new Color[width * height];
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                {
                    Color pixel = color;
                    if (x == 0 || y == 0) pixel = color * 0.72f;
                    else if (x == width - 1 || y == height - 1) pixel = color * 1.12f;
                    pixels[y * width + x] = pixel;
                }
            texture.SetPixels(pixels);
            texture.Apply();
            Sprite sprite = Sprite.Create(texture, new Rect(0, 0, width, height), new Vector2(0.5f, 0.5f), 16);
            SpriteCache[key] = sprite;
            return sprite;
        }

        private Sprite SkinSprite(string skin)
        {
            const int w = 16, h = 24;
            Color[] pixels = new Color[w * h];
            Color cloth = new Color(0.47f, 0.35f, 0.24f);
            Color trim = new Color(0.72f, 0.55f, 0.29f);
            Color skinTone = new Color(0.78f, 0.59f, 0.42f);
            if (skin == "Forest Warden") { cloth = new Color(0.22f, 0.39f, 0.24f); trim = new Color(0.48f, 0.58f, 0.31f); }
            if (skin == "Royal Guard") { cloth = new Color(0.55f, 0.20f, 0.16f); trim = new Color(0.86f, 0.65f, 0.25f); }
            if (skin == "Frostbound") { cloth = new Color(0.40f, 0.60f, 0.70f); trim = new Color(0.78f, 0.86f, 0.87f); }
            Action<int,int,Color> put = (x,y,color) => { if (x >= 0 && x < w && y >= 0 && y < h) pixels[y*w+x] = color; };
            for (int y=1;y<=6;y++) { for(int x=3;x<=6;x++) put(x,y,new Color(0.22f,0.19f,0.17f)); for(int x=9;x<=12;x++) put(x,y,new Color(0.22f,0.19f,0.17f)); }
            for (int y=7;y<=15;y++) for(int x=2;x<=13;x++) put(x,y,cloth);
            for (int x=2;x<=13;x++) put(x,8,trim);
            for (int y=16;y<=22;y++) for(int x=4;x<=11;x++) put(x,y,skinTone);
            for (int x=3;x<=12;x++) put(x,22,trim);
            for (int x=4;x<=11;x++) put(x,23,skin == "Royal Guard" ? trim : cloth);
            if (skin == "Forest Warden") { for(int x=2;x<=13;x++) put(x,21,trim); put(1,18,cloth); put(14,18,cloth); }
            if (skin == "Royal Guard") { for(int x=3;x<=12;x++) put(x,23,trim); put(7,23,new Color(0.9f,0.78f,0.38f)); }
            if (skin == "Frostbound") { for(int y=17;y<=23;y++) { put(3,y,trim); put(12,y,trim); } }
            return CreatePixelSprite(pixels,w,h);
        }

        private Sprite CreatePixelSprite(Color[] pixels, int width, int height)
        {
            var texture = new Texture2D(width,height,TextureFormat.RGBA32,false);
            texture.filterMode = FilterMode.Point;
            texture.SetPixels(pixels);
            texture.Apply();
            return Sprite.Create(texture,new Rect(0,0,width,height),new Vector2(0.5f,0.5f),16);
        }

        private void GatherNearby()
        {
            ResourceNode[] nodes = FindObjectsOfType<ResourceNode>();
            ResourceNode closest = null;
            float best = 2.5f;
            foreach (ResourceNode node in nodes)
            {
                float distance = Vector2.Distance(playerTransform.position, node.transform.position);
                if (distance < best) { best = distance; closest = node; }
            }
            if (closest == null) { notice = "No resources nearby. Find a tree or crystal cluster."; return; }
            string resource = closest.resource;
            if (resource == "wood") save.wood++;
            else if (resource == "crystal") save.crystal++;
            notice = "Gathered " + resource + ". Wood " + save.wood + "  Crystal " + save.crystal;
            Destroy(closest.gameObject);
            SaveGame();
        }

        private void BefriendNearbySlime()
        {
            ForestSlime[] slimes = FindObjectsOfType<ForestSlime>();
            ForestSlime closest = null;
            float best = 2.2f;
            foreach (ForestSlime slime in slimes)
            {
                float distance = Vector2.Distance(playerTransform.position, slime.transform.position);
                if (distance < best) { best = distance; closest = slime; }
            }
            if (closest == null) { notice = "No friendly slime nearby."; return; }
            if (!closest.Befriend()) { notice = "That slime is already your friend."; return; }
            save.companions++;
            save.gel++;
            notice = "A little slime joined your journey! Companions: " + save.companions;
            SaveGame();
        }

        private void EquipSkin(string skin)
        {
            save.skin = skin;
            if (playerRenderer != null) playerRenderer.sprite = SkinSprite(skin);
            notice = "Equipped " + skin + " outfit";
            SaveGame();
        }

        private void LoadGame()
        {
            string path = Path.Combine(Application.persistentDataPath, "player-save.json");
            if (!File.Exists(path)) return;
            try { save = JsonUtility.FromJson<SaveData>(File.ReadAllText(path)) ?? new SaveData(); }
            catch (Exception ex) { Debug.LogWarning("Save load failed; starting fresh: " + ex.Message); save = new SaveData(); }
        }

        private void SaveGame()
        {
            try { File.WriteAllText(Path.Combine(Application.persistentDataPath, "player-save.json"), JsonUtility.ToJson(save, true)); }
            catch (Exception ex) { Debug.LogWarning("Save failed: " + ex.Message); }
        }

        private void BuildStyles()
        {
            titleStyle = new GUIStyle(GUI.skin.label) { fontSize = 23, fontStyle = FontStyle.Bold, normal = { textColor = Parchment } };
            bodyStyle = new GUIStyle(GUI.skin.label) { fontSize = 14, normal = { textColor = new Color(0.16f,0.13f,0.10f) }, wordWrap = true };
            buttonStyle = new GUIStyle(GUI.skin.button) { fontSize = 13, fontStyle = FontStyle.Bold };
        }

        private void OnGUI()
        {
            if (titleStyle == null) BuildStyles();
            float scale = Mathf.Clamp(Screen.width / 1000f, 0.75f, 1.4f);
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(scale, scale, 1));
            GUI.color = new Color(0.10f, 0.09f, 0.08f, 0.94f);
            GUI.Box(new Rect(14, 14, 430, 92), GUIContent.none);
            GUI.color = Color.white;
            GUI.Label(new Rect(28, 19, 400, 32), "FORGOTTEN WORLD", titleStyle);
            GUI.Label(new Rect(30, 54, 390, 26), "THE ELDERWOOD  •  " + save.coins + " coins  •  " + save.companions + " companions", new GUIStyle(bodyStyle) { normal = { textColor = Parchment } });
            GUI.Label(new Rect(30, 78, 390, 22), "A / D move   SPACE jump   E gather   F befriend   I inventory   U account", new GUIStyle(bodyStyle) { normal = { textColor = Parchment }, fontSize = 11 });
            GUI.Label(new Rect(20, Screen.height / scale - 38, 700, 28), notice, new GUIStyle(bodyStyle) { normal = { textColor = Parchment } });
            if (inventoryOpen)
            {
                GUI.color = Parchment;
                GUI.Box(new Rect(470, 18, 390, 410), GUIContent.none);
                GUI.color = Color.black;
                GUI.Label(new Rect(492, 34, 340, 35), "Adventurer's Satchel", titleStyle);
                GUI.Label(new Rect(492, 78, 340, 24), "Materials   Wood " + save.wood + "   Stone " + save.stone + "   Crystal " + save.crystal + "   Gel " + save.gel, bodyStyle);
                GUI.Label(new Rect(492, 112, 340, 24), "Outfits", bodyStyle);
                for (int i = 0; i < skins.Length; i++)
                    if (GUI.Button(new Rect(492 + (i % 2) * 166, 148 + (i / 2) * 38, 160, 32), skins[i] + (save.skin == skins[i] ? " ✓" : ""), buttonStyle))
                        EquipSkin(skins[i]);
                GUI.Label(new Rect(492, 242, 340, 24), "Companions: " + save.companions, bodyStyle);
                GUI.Label(new Rect(492, 272, 340, 60), "Find gentle forest slimes and press F nearby to befriend them. They will follow you.", bodyStyle);
                if (GUI.Button(new Rect(492, 400, 330, 24), "Close  [I]", buttonStyle)) inventoryOpen = false;
            }
            GUI.matrix = Matrix4x4.identity;
            GUI.color = Color.white;
        }
    }
}
