using UnityEngine;

namespace ForgottenWorld
{
    public sealed class ForestSlime : MonoBehaviour
    {
        private Transform player;
        private bool friendly;
        private float wanderTimer;
        private float direction = 1f;

        public void Initialize(Transform target) { player = target; }

        private void Update()
        {
            if (player == null) return;
            float distance = player.position.x - transform.position.x;
            if (friendly && Mathf.Abs(distance) > 1.5f)
                direction = Mathf.Sign(distance);
            else if (!friendly)
            {
                wanderTimer -= Time.deltaTime;
                if (wanderTimer <= 0f)
                {
                    direction = Random.value > 0.5f ? 1f : -1f;
                    wanderTimer = Random.Range(1.5f, 3.5f);
                }
            }
            else direction = 0f;
            transform.position += Vector3.right * direction * Time.deltaTime * (friendly ? 1.8f : 0.55f);
            if (friendly && Mathf.Abs(distance) < 1.1f) transform.localScale = new Vector3(0.85f, 0.85f, 1f);
            else transform.localScale = Vector3.one;
        }

        public bool Befriend()
        {
            if (friendly) return false;
            friendly = true;
            gameObject.name = "Friendly Forest Slime";
            var renderer = GetComponent<SpriteRenderer>();
            if (renderer != null) renderer.color = new Color(1f, 0.88f, 0.55f);
            return true;
        }
    }
}
