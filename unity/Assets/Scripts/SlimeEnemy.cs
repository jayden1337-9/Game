using UnityEngine;

namespace ForgottenWorld
{
    public sealed class SlimeEnemy : MonoBehaviour
    {
        private Transform target;
        private int health = 2;
        private float wanderTimer;
        private float direction = 1f;

        public void Initialize(Transform player) { target = player; }

        private void Update()
        {
            if (target == null) return;
            float distance = target.position.x - transform.position.x;
            if (Mathf.Abs(distance) < 7f)
                direction = Mathf.Sign(distance);
            else
            {
                wanderTimer -= Time.deltaTime;
                if (wanderTimer <= 0f)
                {
                    direction = Random.value > 0.5f ? 1f : -1f;
                    wanderTimer = Random.Range(1.5f, 3.5f);
                }
            }
            transform.position += Vector3.right * direction * Time.deltaTime * 0.7f;
        }

        public void TakeHit(int damage)
        {
            health -= Mathf.Max(1, damage);
            transform.localScale = new Vector3(1.2f, 0.75f, 1f);
            CancelInvoke(nameof(ResetSquash));
            Invoke(nameof(ResetSquash), 0.12f);
            if (health <= 0)
            {
                ForgottenWorldGame owner = FindObjectOfType<ForgottenWorldGame>();
                if (owner != null) owner.SendMessage("OnSlimeDefeated", SendMessageOptions.DontRequireReceiver);
                Destroy(gameObject);
            }
        }

        private void ResetSquash()
        {
            if (this != null) transform.localScale = Vector3.one;
        }
    }
}
