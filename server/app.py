import os, json, time, secrets, sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from flask import Flask, request, jsonify
from flask_cors import CORS
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from werkzeug.security import generate_password_hash, check_password_hash

app=Flask(__name__)
app.config["SECRET_KEY"]=os.getenv("SECRET_KEY","dev-only-change-me")
CORS(app, origins=os.getenv("CORS_ORIGINS","*").split(","))
signer=URLSafeTimedSerializer(app.config["SECRET_KEY"],salt="fw-auth")
DB_URL=os.getenv("DATABASE_URL","").strip()
DB_FILE=os.getenv("SQLITE_PATH","forgotten_world.db")

@contextmanager
def db():
    if DB_URL:
        import psycopg
        from psycopg.rows import dict_row
        conn=psycopg.connect(DB_URL,row_factory=dict_row)
    else:
        conn=sqlite3.connect(DB_FILE); conn.row_factory=sqlite3.Row
    try:
        yield conn; conn.commit()
    except Exception:
        conn.rollback(); raise
    finally: conn.close()

def sql(q): return q.replace("?","%s") if DB_URL else q
def init_db():
    schema=[
    "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL, banned INTEGER NOT NULL DEFAULT 0, ban_reason TEXT)",
    "CREATE TABLE IF NOT EXISTS worlds (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, name TEXT NOT NULL, hosting TEXT NOT NULL, data TEXT NOT NULL DEFAULT '{}', updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wallets (user_id TEXT PRIMARY KEY, coins INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS dev_inventory (user_id TEXT NOT NULL, item_id TEXT NOT NULL, quantity INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(user_id,item_id))",
    "CREATE TABLE IF NOT EXISTS owned_cosmetics (user_id TEXT NOT NULL, cosmetic_id TEXT NOT NULL, PRIMARY KEY(user_id,cosmetic_id))",
    "CREATE TABLE IF NOT EXISTS equipped_cosmetics (user_id TEXT PRIMARY KEY, cosmetic_id TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS daily_claims (user_id TEXT NOT NULL, claim_date TEXT NOT NULL, PRIMARY KEY(user_id,claim_date))",
    "CREATE TABLE IF NOT EXISTS currency_ledger (reward_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, amount INTEGER NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS world_invites (code TEXT PRIMARY KEY, world_id TEXT NOT NULL, owner_id TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS world_members (world_id TEXT NOT NULL, user_id TEXT NOT NULL, PRIMARY KEY(world_id,user_id))",
    "CREATE TABLE IF NOT EXISTS world_events (id TEXT PRIMARY KEY, world_id TEXT NOT NULL, user_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)"]
    with db() as c:
        cur=c.cursor()
        for q in schema: cur.execute(q)
        admin_name=os.getenv("ADMIN_USERNAME","admin1337").strip()
        admin_password=os.getenv("ADMIN_PASSWORD","")
        if admin_name and admin_password:
            cur.execute(sql("SELECT id FROM users WHERE username=?"),(admin_name,))
            existing=cur.fetchone()
            if existing:
                admin_id=asdict(existing)["id"]
                cur.execute(sql("UPDATE users SET password_hash=? WHERE id=?"),(generate_password_hash(admin_password),admin_id))
            else:
                admin_id=secrets.token_hex(16)
                cur.execute(sql("INSERT INTO users (id,username,password_hash,created_at) VALUES (?,?,?,?)"),(admin_id,admin_name,generate_password_hash(admin_password),datetime.now(timezone.utc).isoformat()))
                cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,0)"),(admin_id,))

def asdict(row):
    if row is None: return None
    return dict(row) if not isinstance(row,dict) else row

def auth():
    h=request.headers.get("Authorization","")
    if not h.startswith("Bearer "): return None
    try: p=signer.loads(h[7:],max_age=60*60*24*30)
    except (BadSignature,SignatureExpired): return None
    with db() as c:
        cur=c.cursor(); cur.execute(sql("SELECT * FROM users WHERE id=?"),(p.get("uid"),))
        return asdict(cur.fetchone())

def player():
    u=auth()
    if not u: return None,(jsonify(error="Authentication required"),401)
    if u["banned"]: return None,(jsonify(error="Account is banned",banned=True,reason=u["ban_reason"]),403)
    return u,None

@app.get("/")
@app.get("/api/health")
def health(): return jsonify(ok=True,service="forgotten-world-api",version="0.1.0")

@app.post("/api/register")
def register():
    b=request.get_json(silent=True) or {}; name=str(b.get("username","")).strip(); pw=str(b.get("password",""))
    if not 3<=len(name)<=24 or not name.replace("_","").isalnum(): return jsonify(error="Username must be 3-24 letters, numbers or underscores"),400
    if name.casefold()==os.getenv("ADMIN_USERNAME","admin1337").strip().casefold(): return jsonify(error="This username is reserved"),409
    if len(pw)<8: return jsonify(error="Password must be at least 8 characters"),400
    uid=secrets.token_hex(16); now=datetime.now(timezone.utc).isoformat()
    try:
        with db() as c:
            cur=c.cursor(); cur.execute(sql("INSERT INTO users (id,username,password_hash,created_at) VALUES (?,?,?,?)"),(uid,name,generate_password_hash(pw),now))
            cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,0)"),(uid,))
    except Exception: return jsonify(error="Username is already taken"),409
    return jsonify(token=signer.dumps({"uid":uid}),user={"id":uid,"username":name}),201

@app.post("/api/login")
def login():
    b=request.get_json(silent=True) or {}
    with db() as c:
        cur=c.cursor(); cur.execute(sql("SELECT * FROM users WHERE username=?"),(str(b.get("username","")).strip(),)); u=asdict(cur.fetchone())
    if not u or not check_password_hash(u["password_hash"],str(b.get("password",""))): return jsonify(error="Invalid username or password"),401
    if u["banned"]: return jsonify(error="Account is banned",banned=True,reason=u["ban_reason"]),403
    return jsonify(token=signer.dumps({"uid":u["id"]}),user={"id":u["id"],"username":u["username"]})

@app.get("/api/me")
def me():
    u,e=player()
    if e:return e
    return jsonify(id=u["id"],username=u["username"],created_at=u["created_at"])

@app.get("/api/worlds")
def worlds():
    u,e=player()
    if e:return e
    with db() as c:
        cur=c.cursor(); cur.execute(sql("SELECT id,owner_id,name,hosting,updated_at FROM worlds WHERE owner_id=? ORDER BY updated_at DESC"),(u["id"],)); rows=cur.fetchall()
    return jsonify(worlds=[asdict(r) for r in rows])

@app.post("/api/worlds")
def create_world():
    u,e=player()
    if e:return e
    b=request.get_json(silent=True) or {}; name=str(b.get("name","New World")).strip()[:40] or "New World"; hosting=b.get("hosting","dedicated")
    if hosting not in ("dedicated","player"):return jsonify(error="hosting must be dedicated or player"),400
    wid=secrets.token_hex(12); now=datetime.now(timezone.utc).isoformat()
    with db() as c:
        cur=c.cursor(); cur.execute(sql("INSERT INTO worlds (id,owner_id,name,hosting,data,updated_at) VALUES (?,?,?,?,?,?)"),(wid,u["id"],name,hosting,"{}",now))
        cur.execute(sql("INSERT INTO world_members (world_id,user_id) VALUES (?,?)"),(wid,u["id"]))
    return jsonify(id=wid,name=name,hosting=hosting,updated_at=now),201

@app.get("/api/worlds/<wid>")
def get_world(wid):
    u,e=player()
    if e:return e
    with db() as c:
        cur=c.cursor(); cur.execute(sql("SELECT * FROM worlds WHERE id=? AND owner_id=?"),(wid,u["id"])); w=asdict(cur.fetchone())
        if not w and is_world_member(cur,wid,u["id"]):
            cur.execute(sql("SELECT * FROM worlds WHERE id=?"),(wid,)); w=asdict(cur.fetchone())
    if not w:return jsonify(error="World not found"),404
    w["data"]=json.loads(w["data"]); return jsonify(w)

@app.put("/api/worlds/<wid>")
def save_world(wid):
    u,e=player()
    if e:return e
    data=(request.get_json(silent=True) or {}).get("data")
    if not isinstance(data,dict):return jsonify(error="data must be a JSON object"),400
    encoded=json.dumps(data,separators=(",",":"))
    if len(encoded)>1_000_000:return jsonify(error="World save exceeds 1 MB limit"),413
    now=datetime.now(timezone.utc).isoformat()
    with db() as c:
        cur=c.cursor()
        if not is_world_member(cur,wid,u["id"]):return jsonify(error="World not found"),404
        cur.execute(sql("UPDATE worlds SET data=?,updated_at=? WHERE id=?"),(encoded,now,wid))
        if cur.rowcount==0:return jsonify(error="World not found"),404
    return jsonify(ok=True,updated_at=now)

@app.get("/api/profile")
def profile():
    u,e=player()
    if e:return e
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
        row=asdict(cur.fetchone())
        if not row:
            cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,0)"),(u["id"],))
            coins=0
        else: coins=row["coins"]
        cur.execute(sql("SELECT cosmetic_id FROM owned_cosmetics WHERE user_id=?"),(u["id"],))
        owned=[r["cosmetic_id"] for r in cur.fetchall()]
        cur.execute(sql("SELECT cosmetic_id FROM equipped_cosmetics WHERE user_id=?"),(u["id"],))
        eq=asdict(cur.fetchone())
        cur.execute(sql("SELECT item_id,quantity FROM dev_inventory WHERE user_id=?"),(u["id"],))
        dev_items={r["item_id"]:r["quantity"] for r in cur.fetchall()}
    return jsonify(username=u["username"],coins=coins,owned_cosmetics=owned,equipped_cosmetic=eq["cosmetic_id"] if eq else None,dev_inventory=dev_items)

@app.get("/api/shop")
def shop():
    u,e=player()
    if e:return e
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT cosmetic_id FROM owned_cosmetics WHERE user_id=?"),(u["id"],))
        owned={row["cosmetic_id"] for row in cur.fetchall()}
    return jsonify(items=[{"id":k,**v,"owned":k in owned} for k,v in COSMETICS.items()])

@app.post("/api/shop/buy")
def buy_cosmetic():
    u,e=player()
    if e:return e
    cosmetic_id=str((request.get_json(silent=True) or {}).get("cosmetic_id",""))
    item=COSMETICS.get(cosmetic_id)
    if not item:return jsonify(error="Cosmetic not found"),404
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT cosmetic_id FROM owned_cosmetics WHERE user_id=? AND cosmetic_id=?"),(u["id"],cosmetic_id))
        if cur.fetchone():return jsonify(error="You already own this cosmetic"),409
        cur.execute(sql("UPDATE wallets SET coins=coins-? WHERE user_id=? AND coins>=?"),(item["price"],u["id"],item["price"]))
        if cur.rowcount==0:
            cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
            wallet=asdict(cur.fetchone())
            balance=int(wallet["coins"]) if wallet else 0
            return jsonify(error="Not enough coins",balance=balance,price=item["price"]),409
        cur.execute(sql("INSERT INTO owned_cosmetics (user_id,cosmetic_id) VALUES (?,?) ON CONFLICT(user_id,cosmetic_id) DO NOTHING"),(u["id"],cosmetic_id))
        if cur.rowcount==0:
            cur.execute(sql("UPDATE wallets SET coins=coins+? WHERE user_id=?"),(item["price"],u["id"]))
            return jsonify(error="You already own this cosmetic"),409
        cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
        balance=int(asdict(cur.fetchone())["coins"])
    return jsonify(ok=True,cosmetic_id=cosmetic_id,coins=balance)

@app.post("/api/cosmetics/equip")
def equip_cosmetic():
    u,e=player()
    if e:return e
    cosmetic_id=str((request.get_json(silent=True) or {}).get("cosmetic_id",""))
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT cosmetic_id FROM owned_cosmetics WHERE user_id=? AND cosmetic_id=?"),(u["id"],cosmetic_id))
        if not cur.fetchone():return jsonify(error="You do not own this cosmetic"),403
        cur.execute(sql("SELECT user_id FROM equipped_cosmetics WHERE user_id=?"),(u["id"],))
        if cur.fetchone():cur.execute(sql("UPDATE equipped_cosmetics SET cosmetic_id=? WHERE user_id=?"),(cosmetic_id,u["id"]))
        else:cur.execute(sql("INSERT INTO equipped_cosmetics (user_id,cosmetic_id) VALUES (?,?)"),(u["id"],cosmetic_id))
    return jsonify(ok=True,equipped_cosmetic=cosmetic_id)

@app.post("/api/currency/daily")
def daily_currency():
    u,e=player()
    if e:return e
    today=datetime.now(timezone.utc).date().isoformat()
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("INSERT INTO daily_claims (user_id,claim_date) VALUES (?,?) ON CONFLICT(user_id,claim_date) DO NOTHING"),(u["id"],today))
        if cur.rowcount==0:return jsonify(error="Daily reward already claimed",claimed=False),409
        cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
        wallet=asdict(cur.fetchone())
        if not wallet:
            cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,100)"),(u["id"],))
            balance=100
        else:
            cur.execute(sql("UPDATE wallets SET coins=coins+100 WHERE user_id=?"),(u["id"],))
            balance=wallet["coins"]+100
    return jsonify(ok=True,reward=100,coins=balance)


@app.post("/api/currency/reward")
def currency_reward():
    u,e=player()
    if e:return e
    body=request.get_json(silent=True) or {}
    reward_id=str(body.get("reward_id","")).strip()
    source=str(body.get("source",""))
    rewards={"slime_kill":5}
    if not 8<=len(reward_id)<=80:return jsonify(error="Invalid reward identifier"),400
    if source not in rewards:return jsonify(error="Unknown reward source"),400
    amount=rewards[source]
    today=datetime.now(timezone.utc).date().isoformat()
    start=today+"T00:00:00"
    now=datetime.now(timezone.utc).isoformat()
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT reward_id FROM currency_ledger WHERE reward_id=?"),(reward_id,))
        if cur.fetchone():return jsonify(error="Reward already processed"),409
        cur.execute(sql("SELECT COALESCE(SUM(amount),0) AS total FROM currency_ledger WHERE user_id=? AND created_at>=?"),(u["id"],start))
        earned=int(asdict(cur.fetchone())["total"])
        if earned+amount>200:return jsonify(error="Daily gameplay coin limit reached",daily_limit=200),429
        cur.execute(sql("INSERT INTO currency_ledger (reward_id,user_id,amount,source,created_at) VALUES (?,?,?,?,?)"),(reward_id,u["id"],amount,source,now))
        cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,?) ON CONFLICT(user_id) DO UPDATE SET coins=wallets.coins+excluded.coins"),(u["id"],amount))
        cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
        balance=int(asdict(cur.fetchone())["coins"])
    return jsonify(ok=True,reward=amount,coins=balance),200



# Developer-only test grants. Configure DEV_ADMIN_USERNAMES as a comma-separated
# allowlist in the server environment; never trust a client-side toggle.
DEV_ITEMS = {"grass", "dirt", "stone", "wood", "gel", "copper", "crystal", "ice", "sand", "relic", "herb", "rune", "leaves"}

def is_dev_admin(user):
    allowed={name.strip().casefold() for name in os.getenv("DEV_ADMIN_USERNAMES", "").split(",") if name.strip()}
    allowed.add(os.getenv("ADMIN_USERNAME","admin1337").strip().casefold())
    return bool(user["username"]) and user["username"].casefold() in allowed

@app.get("/api/dev/status")
def dev_status():
    u,e=player()
    if e:return e
    return jsonify(enabled=is_dev_admin(u))

@app.post("/api/dev/grant")
def dev_grant():
    u,e=player()
    if e:return e
    if not is_dev_admin(u):return jsonify(error="Developer access is not enabled for this account"),403
    body=request.get_json(silent=True) or {}
    item_id=str(body.get("item_id", ""))
    quantity=body.get("quantity", 0)
    coins=body.get("coins", 0)
    cosmetic_id=str(body.get("cosmetic_id", ""))
    if not isinstance(quantity,int) or isinstance(quantity,bool) or not 0<=quantity<=999:
        return jsonify(error="Item quantity must be between 0 and 999"),400
    if not isinstance(coins,int) or isinstance(coins,bool) or not 0<=coins<=100000:
        return jsonify(error="Coin grant must be between 0 and 100000"),400
    if item_id and item_id not in DEV_ITEMS:return jsonify(error="Unknown item"),400
    if cosmetic_id and cosmetic_id not in COSMETICS:return jsonify(error="Unknown cosmetic"),400
    if not item_id and not coins and not cosmetic_id:return jsonify(error="Choose an item, coins, or cosmetic to grant"),400
    with db() as c:
        cur=c.cursor()
        if item_id and quantity:
            cur.execute(sql("INSERT INTO dev_inventory (user_id,item_id,quantity) VALUES (?,?,?) ON CONFLICT(user_id,item_id) DO UPDATE SET quantity=dev_inventory.quantity+excluded.quantity"),(u["id"],item_id,quantity))
        if coins:
            cur.execute(sql("INSERT INTO wallets (user_id,coins) VALUES (?,?) ON CONFLICT(user_id) DO UPDATE SET coins=wallets.coins+excluded.coins"),(u["id"],coins))
        if cosmetic_id:
            cur.execute(sql("INSERT INTO owned_cosmetics (user_id,cosmetic_id) VALUES (?,?) ON CONFLICT(user_id,cosmetic_id) DO NOTHING"),(u["id"],cosmetic_id))
        cur.execute(sql("SELECT coins FROM wallets WHERE user_id=?"),(u["id"],))
        wallet=asdict(cur.fetchone())
        cur.execute(sql("SELECT item_id,quantity FROM dev_inventory WHERE user_id=?"),(u["id"],))
        items={row["item_id"]:row["quantity"] for row in cur.fetchall()}
    return jsonify(ok=True,coins=wallet["coins"] if wallet else 0,dev_inventory=items,item_id=item_id,granted_quantity=quantity,cosmetic_id=cosmetic_id or None)


# Lightweight polling-based multiplayer relay. Clients poll events after their last cursor.
def is_world_member(cur, wid, uid):
    cur.execute(sql("SELECT user_id FROM world_members WHERE world_id=? AND user_id=?"),(wid,uid))
    if cur.fetchone() is not None:return True
    cur.execute(sql("SELECT id FROM worlds WHERE id=? AND owner_id=?"),(wid,uid))
    return cur.fetchone() is not None

@app.post("/api/worlds/<wid>/invite")
def create_world_invite(wid):
    u,e=player()
    if e:return e
    code=secrets.token_urlsafe(8)
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT id FROM worlds WHERE id=? AND owner_id=?"),(wid,u["id"]))
        if not cur.fetchone():return jsonify(error="World not found"),404
        cur.execute(sql("INSERT INTO world_invites (code,world_id,owner_id) VALUES (?,?,?)"),(code,wid,u["id"]))
    return jsonify(code=code)

@app.post("/api/worlds/join")
def join_world():
    u,e=player()
    if e:return e
    code=str((request.get_json(silent=True) or {}).get("code",""))
    with db() as c:
        cur=c.cursor()
        cur.execute(sql("SELECT world_id FROM world_invites WHERE code=?"),(code,))
        invite=asdict(cur.fetchone())
        if not invite:return jsonify(error="Invalid invite code"),404
        wid=invite["world_id"]
        cur.execute(sql("INSERT INTO world_members (world_id,user_id) VALUES (?,?) ON CONFLICT(world_id,user_id) DO NOTHING"),(wid,u["id"]))
        cur.execute(sql("SELECT id,name,hosting FROM worlds WHERE id=?"),(wid,))
        world=asdict(cur.fetchone())
    return jsonify(world=world),200

@app.route("/api/worlds/<wid>/events",methods=["GET","POST"])
def world_events(wid):
    u,e=player()
    if e:return e
    with db() as c:
        cur=c.cursor()
        if not is_world_member(cur,wid,u["id"]):return jsonify(error="You are not a member of this world"),403
        if request.method=="POST":
            payload=(request.get_json(silent=True) or {}).get("event")
            if not isinstance(payload,dict):return jsonify(error="event must be an object"),400
            encoded=json.dumps(payload,separators=(",",":"))
            if len(encoded)>4096:return jsonify(error="Event too large"),413
            event_id=secrets.token_hex(12)
            now=datetime.now(timezone.utc).isoformat()
            cur.execute(sql("INSERT INTO world_events (id,world_id,user_id,payload,created_at) VALUES (?,?,?,?,?)"),(event_id,wid,u["id"],encoded,now))
            return jsonify(id=event_id,created_at=now),201
        after=request.args.get("after","")
        cur.execute(sql("SELECT id,user_id,payload,created_at FROM world_events WHERE world_id=? AND created_at>? AND user_id<>? ORDER BY created_at ASC LIMIT 100"),(wid,after,u["id"]))
        rows=[asdict(row) for row in cur.fetchall()]
    for row in rows:row["event"]=json.loads(row.pop("payload"))
    return jsonify(events=rows)


# Initialize at import time so both `python app.py` and WSGI servers (Gunicorn) work.
init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
