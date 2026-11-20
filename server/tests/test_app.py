import pytest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as api

@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(api, "DB_URL", "")
    monkeypatch.setattr(api, "DB_FILE", str(tmp_path / "test.sqlite3"))
    api.init_db()
    return api.app.test_client()

def register(client, username="tester"):
    response = client.post("/api/register", json={"username": username, "password": "test-password-123"})
    assert response.status_code == 201, response.get_json()
    return response.get_json()["token"]

def auth(token):
    return {"Authorization": "Bearer " + token}

def test_health_and_register_login(client):
    assert client.get("/api/health").status_code == 200
    token = register(client)
    response = client.post("/api/login", json={"username": "tester", "password": "test-password-123"})
    assert response.status_code == 200
    assert response.get_json()["token"]
    assert client.get("/api/me", headers=auth(token)).status_code == 200

def test_daily_reward_only_once_per_day(client):
    token = register(client)
    headers = auth(token)
    first = client.post("/api/currency/daily", headers=headers, json={})
    assert first.status_code == 200
    assert first.get_json()["coins"] == 100
    second = client.post("/api/currency/daily", headers=headers, json={})
    assert second.status_code == 409
    assert client.get("/api/profile", headers=headers).get_json()["coins"] == 100

def test_cosmetic_purchase_and_equip(client):
    token = register(client)
    headers = auth(token)
    with api.db() as conn:
        cur = conn.cursor()
        cur.execute(api.sql("UPDATE wallets SET coins=500 WHERE user_id=(SELECT id FROM users WHERE username=?)"), ("tester",))
    purchase = client.post("/api/shop/buy", headers=headers, json={"cosmetic_id": "forest_cape"})
    assert purchase.status_code == 200
    assert purchase.get_json()["coins"] == 380
    assert client.post("/api/shop/buy", headers=headers, json={"cosmetic_id": "forest_cape"}).status_code == 409
    assert client.post("/api/cosmetics/equip", headers=headers, json={"cosmetic_id": "forest_cape"}).status_code == 200
    assert client.get("/api/profile", headers=headers).get_json()["equipped_cosmetic"] == "forest_cape"

def test_world_invite_shared_save_and_events(client):
    owner = register(client, "owner")
    guest = register(client, "guest")
    owner_headers, guest_headers = auth(owner), auth(guest)
    created = client.post("/api/worlds", headers=owner_headers, json={"name": "Test World", "hosting": "dedicated"})
    assert created.status_code == 201
    wid = created.get_json()["id"]
    invite = client.post(f"/api/worlds/{wid}/invite", headers=owner_headers, json={})
    assert invite.status_code == 200
    assert client.post("/api/worlds/join", headers=guest_headers, json={"code": invite.get_json()["code"]}).status_code == 200
    assert client.put(f"/api/worlds/{wid}", headers=guest_headers, json={"data": {"seed": 123}}).status_code == 200
    assert client.get(f"/api/worlds/{wid}", headers=owner_headers).get_json()["data"]["seed"] == 123
    assert client.post(f"/api/worlds/{wid}/events", headers=guest_headers, json={"event": {"type": "chat", "text": "hello"}}).status_code == 201
    events = client.get(f"/api/worlds/{wid}/events", headers=owner_headers).get_json()["events"]
    assert events and events[0]["event"]["text"] == "hello"

def test_auth_required_and_invalid_payloads(client):
    assert client.get("/api/profile").status_code == 401
    token = register(client)
    headers = auth(token)
    assert client.post("/api/shop/buy", headers=headers, json={"cosmetic_id": "not-real"}).status_code == 404
    assert client.put("/api/worlds/nope", headers=headers, json={"data": []}).status_code == 400


def test_gameplay_rewards_are_idempotent_and_capped(client):
    token = register(client)
    headers = auth(token)
    first = client.post("/api/currency/reward", headers=headers, json={"reward_id": "reward-unique-001", "source": "slime_kill"})
    assert first.status_code == 200
    assert first.get_json()["coins"] == 5
    duplicate = client.post("/api/currency/reward", headers=headers, json={"reward_id": "reward-unique-001", "source": "slime_kill"})
    assert duplicate.status_code == 409
    for index in range(39):
        response = client.post("/api/currency/reward", headers=headers, json={"reward_id": f"slime-reward-{index:04d}", "source": "slime_kill"})
        assert response.status_code == 200
    limited = client.post("/api/currency/reward", headers=headers, json={"reward_id": "slime-reward-over-limit", "source": "slime_kill"})
    assert limited.status_code == 429
    assert client.get("/api/profile", headers=headers).get_json()["coins"] == 200



def test_dev_grants_require_allowlisted_username(client, monkeypatch):
    token = register(client, "builder")
    headers = auth(token)
    assert client.get("/api/dev/status", headers=headers).get_json()["enabled"] is False
    assert client.post("/api/dev/grant", headers=headers, json={"item_id":"wood","quantity":10}).status_code == 403
    monkeypatch.setenv("DEV_ADMIN_USERNAMES", "builder")
    assert client.get("/api/dev/status", headers=headers).get_json()["enabled"] is True
    granted = client.post("/api/dev/grant", headers=headers, json={"item_id":"wood","quantity":10,"coins":250,"cosmetic_id":"forest_cape"})
    assert granted.status_code == 200
    assert granted.get_json()["dev_inventory"]["wood"] == 10
    assert granted.get_json()["granted_quantity"] == 10
    assert granted.get_json()["item_id"] == "wood"
    assert granted.get_json()["coins"] == 250
    assert client.get("/api/profile", headers=headers).get_json()["coins"] == 250
    assert client.post("/api/dev/grant", headers=headers, json={"item_id":"not-real","quantity":1}).status_code == 400
