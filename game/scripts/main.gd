extends Node2D

const TILE := 32
const WORLD_WIDTH := 420
const WORLD_HEIGHT := 80
const GRAVITY := 1100.0
const SPEED := 260.0
const JUMP := -430.0

var player_pos := Vector2(420, 260)
var velocity := Vector2.ZERO
var camera_offset := Vector2.ZERO
var blocks: Dictionary = {}
var inventory := {"grass": 0, "dirt": 24, "stone": 0, "wood": 0, "gel": 0, "copper": 0, "crystal": 0, "ice": 0, "sand": 0, "relic": 0, "herb": 0, "rune": 0}
var equipment := {"weapon": "Wooden Sword", "head": "None", "chest": "Cloth Tunic", "legs": "None", "accessory": "None"}
var recipes := {
    "Wooden Sword": {"wood": 8},
    "Wooden Helmet": {"wood": 12},
    "Wooden Chestplate": {"wood": 20},
    "Wooden Boots": {"wood": 10},
    "Copper Blade": {"copper": 12, "wood": 4},
    "Copper Helmet": {"copper": 10},
    "Copper Chestplate": {"copper": 18},
    "Copper Boots": {"copper": 12},
    "Lucky Charm": {"copper": 6, "gel": 8}
}
var craft_names := ["Wooden Sword", "Wooden Helmet", "Wooden Chestplate", "Wooden Boots", "Copper Blade", "Copper Helmet", "Copper Chestplate", "Copper Boots", "Lucky Charm"]
var enemies: Array[Dictionary] = []
var remote_players: Dictionary = {}
var remote_player_seen: Dictionary = {}
var coins := 0
var selected_slot := 0
var hotbar := ["dirt", "stone", "wood", "grass"]
var biome := "Forest"
var status_text := "A/D move | SPACE jump | LMB mine | RMB place | J attack | C craft"
var show_crafting := false
var show_inventory := false
var show_cosmetics := false
var show_quests := false
var visited_biomes: Dictionary = {}
var quest_progress := {"wood": 0, "crystal": 0, "relic": 0, "biomes": 0, "runes": 0}
var quest_claimed: Dictionary = {}
var quest_definitions := {
    "woodcutter": {"label": "Helpful Hands", "goal": "wood", "target": 20, "reward": 30, "description": "Gather 20 wood"},
    "crystal_seeker": {"label": "Bright Discoveries", "goal": "crystal", "target": 12, "reward": 45, "description": "Gather 12 crystals"},
    "relic_hunter": {"label": "Lost History", "goal": "relic", "target": 8, "reward": 75, "description": "Find 8 ancient relics"},
    "wanderer": {"label": "World Wanderer", "goal": "biomes", "target": 5, "reward": 100, "description": "Visit 5 different biomes"},
    "guardian_trial": {"label": "Ancient Guardian Trial", "goal": "runes", "target": 3, "reward": 150, "description": "Recover three ancient runes"}
}
var owned_cosmetics := ["None"]
var equipped_cosmetic := "None"
var account_owned_cosmetics: Array = []
var account_equipped_cosmetic := "None"
var cosmetic_prices := {"Forest Cape": 35, "Royal Crown": 90, "Slime Buddy": 70}
var cosmetic_recipes := {"Leaf Crown": {"leaves": 12, "wood": 2}, "Wooden Mask": {"wood": 8}, "Slime Hat": {"gel": 6}}
var player_health := 100
var attack_cooldown := 0.0
var world_seed := 0
var autosave_elapsed := 0.0
const AUTOSAVE_SECONDS := 30.0

func _ready() -> void:
    randomize()
    if not _load_game():
        world_seed = randi()
        _generate_world()
        _spawn_enemies()
    var account_ui = get_node_or_null("AccountUI")
    if account_ui != null:
        account_ui.world_event_received.connect(_on_world_event)
        account_ui.world_loaded.connect(_apply_shared_world)
    update_discord_presence()
    queue_redraw()

func update_discord_presence() -> void:
    var presence := get_node_or_null("DiscordPresence")
    if presence == null:
        return
    var world_label := "Solo World"
    var account_ui := get_node_or_null("AccountUI")
    if account_ui != null and not str(account_ui.active_world_name).is_empty():
        world_label = str(account_ui.get("active_world_name"))
    presence.call("update_presence", biome, world_label)

func _generate_world() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = world_seed
    for x in range(WORLD_WIDTH):
        var surface_y := 13 + int(round(sin(float(x) * 0.12) * 2.0 + rng.randf_range(-1.0, 1.0)))
        var region := _biome_for_x(x)
        for y in range(surface_y, WORLD_HEIGHT):
            var depth := y - surface_y
            var kind := "grass" if depth == 0 else ("dirt" if depth < 6 else "stone")
            if region == "Mushroom Fields" and depth == 0:
                kind = "mushroom_soil"
            elif region == "Crystal Caverns" and depth > 5:
                kind = "crystal_stone" if rng.randf() < 0.22 else "stone"
            elif region == "Frostreach" and depth == 0:
                kind = "ice"
            elif region == "Ashlands" and depth == 0:
                kind = "ash"
            elif region == "Sunken Ruins" and depth == 0:
                kind = "sand"
            if depth > 8 and rng.randf() < 0.025:
                continue
            if depth > 9 and depth < 30 and rng.randf() < 0.018:
                kind = "copper"
            if region == "Crystal Caverns" and depth > 7 and rng.randf() < 0.035:
                kind = "crystal"
            if region == "Sunken Ruins" and depth > 3 and rng.randf() < 0.012:
                kind = "relic"
            if region == "Mushroom Fields" and depth == 1 and rng.randf() < 0.025:
                kind = "herb"
            blocks[Vector2i(x, y)] = kind
        blocks[Vector2i(x, WORLD_HEIGHT - 1)] = "stone"
        if region == "Forest" and x % 17 == 8:
            _make_tree(x, surface_y - 1)
        elif region == "Mushroom Fields" and x % 19 == 4:
            blocks[Vector2i(x, surface_y - 1)] = "mushroom"
            blocks[Vector2i(x, surface_y - 2)] = "mushroom_cap"
        elif region == "Crystal Caverns" and x % 13 == 5:
            _make_crystal_cluster(x, surface_y - 1)
        elif region == "Frostreach" and x % 21 == 7:
            _make_frost_tree(x, surface_y - 1)
        elif region == "Sunken Ruins" and x % 23 == 9:
            _make_ruin(x, surface_y - 1)
        if x % 91 == 35:
            _make_ruin(x, surface_y - 1)

func _biome_for_x(region: int) -> String:
    if region < 70:
        return "Forest"
    if region < 140:
        return "Mushroom Fields"
    if region < 210:
        return "Crystal Caverns"
    if region < 280:
        return "Frostreach"
    if region < 350:
        return "Ashlands"
    return "Sunken Ruins"

func _make_crystal_cluster(x: int, y: int) -> void:
    for offset in range(3):
        blocks[Vector2i(x + offset - 1, y - offset)] = "crystal"

func _make_frost_tree(x: int, y: int) -> void:
    for h in range(5):
        blocks[Vector2i(x, y - h)] = "ice"
    for dx in range(-2, 3):
        for dy in range(-5, -2):
            if abs(dx) + abs(dy + 4) < 4:
                blocks[Vector2i(x + dx, y + dy)] = "snow"

func _make_tree(x: int, y: int) -> void:
    for h in range(4):
        blocks[Vector2i(x, y - h)] = "wood"
    for dx in range(-2, 3):
        for dy in range(-6, -2):
            if abs(dx) + abs(dy + 4) < 4:
                blocks[Vector2i(x + dx, y + dy)] = "leaves"

func _make_ruin(x: int, y: int) -> void:
    for dx in range(-4, 5):
        blocks[Vector2i(x + dx, y)] = "ancient_brick"
        if abs(dx) == 4:
            for dy in range(1, 5):
                blocks[Vector2i(x + dx, y + dy)] = "ancient_brick"
    blocks[Vector2i(x, y - 1)] = "relic"
    blocks[Vector2i(x - 2, y - 1)] = "rune"
    blocks[Vector2i(x + 2, y - 1)] = "rune"

func _spawn_enemies() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    for i in range(28):
        var x := rng.randi_range(8, WORLD_WIDTH - 8)
        var ground := _surface_at(x)
        var region := _biome_for_x(x)
        var enemy_kind := "Slime"
        if region == "Mushroom Fields": enemy_kind = "Fungus"
        elif region == "Crystal Caverns": enemy_kind = "Crystal Mote"
        elif region == "Frostreach": enemy_kind = "Frost Wisp"
        elif region == "Ashlands": enemy_kind = "Ash Slime"
        elif region == "Sunken Ruins": enemy_kind = "Sand Beetle"
        enemies.append({"pos": Vector2(x * TILE, ground * TILE - 18), "hp": 35, "speed": rng.randf_range(25.0, 55.0), "kind": enemy_kind})

func _surface_at(x: int) -> int:
    for y in range(WORLD_HEIGHT):
        if blocks.has(Vector2i(x, y)):
            return y
    return 14

func _physics_process(delta: float) -> void:
    autosave_elapsed += delta
    if autosave_elapsed >= AUTOSAVE_SECONDS:
        autosave_elapsed = 0.0
        _save_game()
    var direction := Input.get_axis("ui_left", "ui_right")
    if Input.is_key_pressed(KEY_A): direction = -1.0
    elif Input.is_key_pressed(KEY_D): direction = 1.0
    velocity.x = direction * SPEED
    velocity.y += GRAVITY * delta
    if Input.is_key_pressed(KEY_SPACE) and _on_ground(): velocity.y = JUMP
    player_pos.x += velocity.x * delta
    if _solid(Vector2(player_pos.x, player_pos.y + 18)): player_pos.x -= velocity.x * delta
    player_pos.y += velocity.y * delta
    if _solid(Vector2(player_pos.x, player_pos.y + 18)):
        if velocity.y > 0: player_pos.y = floor((player_pos.y + 18) / TILE) * TILE - 18
        velocity.y = 0
    player_pos.x = clamp(player_pos.x, 16.0, WORLD_WIDTH * TILE - 16.0)
    camera_offset = player_pos - get_viewport_rect().size / 2.0
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    var now_seconds := Time.get_ticks_msec() / 1000.0
    for remote_id in remote_players.keys():
        if now_seconds - float(remote_player_seen.get(remote_id, 0.0)) > 5.0:
            remote_players.erase(remote_id)
            remote_player_seen.erase(remote_id)
    _update_enemies(delta)
    var region := int(player_pos.x / TILE)
    var next_biome := _biome_for_x(region)
    if next_biome != biome:
        biome = next_biome
        update_discord_presence()
    if not visited_biomes.has(biome):
        _record_biome_visit(biome)
    queue_redraw()

func _on_world_event(event_data: Dictionary) -> void:
    var payload: Dictionary = event_data.get("event", {})
    if payload.get("type", "") == "tile_update":
        var cell := Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
        if payload.get("remove", false):
            blocks.erase(cell)
        else:
            blocks[cell] = str(payload.get("kind", "dirt"))
        return
    if payload.get("type", "") != "player_state":
        return
    var remote_id := str(event_data.get("user_id", ""))
    if remote_id.is_empty():
        return
    remote_players[remote_id] = Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
    remote_player_seen[remote_id] = Time.get_ticks_msec() / 1000.0

func _update_enemies(delta: float) -> void:
    for enemy in enemies:
        var p: Vector2 = enemy["pos"]
        var dx := player_pos.x - p.x
        if absf(dx) < 420.0:
            p.x += signf(dx) * float(enemy["speed"]) * delta
            if absf(dx) < 28.0 and randf() < delta * 0.35:
                player_health = maxi(0, player_health - 4)
        enemy["pos"] = p

func _on_ground() -> bool:
    return _solid(Vector2(player_pos.x, player_pos.y + 20))

func _solid(p: Vector2) -> bool:
    return blocks.has(Vector2i(floori(p.x / TILE), floori(p.y / TILE)))

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_C: show_crafting = not show_crafting
        if event.keycode == KEY_I: show_inventory = not show_inventory
        if event.keycode == KEY_M: show_cosmetics = not show_cosmetics
        if event.keycode == KEY_Q: show_quests = not show_quests
        if show_crafting and event.keycode >= KEY_1 and event.keycode <= KEY_9 and event.keycode - KEY_1 < craft_names.size():
            _craft(craft_names[event.keycode - KEY_1])
        if show_cosmetics and event.keycode >= KEY_1 and event.keycode <= KEY_3:
            _craft_cosmetic(["Leaf Crown", "Wooden Mask", "Slime Hat"][event.keycode - KEY_1])
        elif show_cosmetics and event.keycode >= KEY_4 and event.keycode <= KEY_6:
            _buy_cosmetic(["Forest Cape", "Royal Crown", "Slime Buddy"][event.keycode - KEY_4])
        if event.keycode >= KEY_1 and event.keycode <= KEY_4: selected_slot = event.keycode - KEY_1
        if event.keycode == KEY_J: _attack()
        if event.keycode == KEY_E: _equip_best()
    if event is InputEventMouseButton and event.pressed:
        var world_mouse := get_global_mouse_position() + camera_offset
        var cell := Vector2i(floori(world_mouse.x / TILE), floori(world_mouse.y / TILE))
        if event.button_index == MOUSE_BUTTON_LEFT:
            if blocks.has(cell) and Vector2(cell * TILE).distance_to(player_pos) < 150.0:
                var kind: String = blocks[cell]
                blocks.erase(cell)
                inventory[kind] = inventory.get(kind, 0) + 1
                _record_gather(kind)
                if kind == "wood": coins += 1
                var account_ui = get_node_or_null("AccountUI")
                if account_ui != null:
                    account_ui.broadcast_world_event({"type": "tile_update", "x": cell.x, "y": cell.y, "remove": true})
                status_text = "Mined " + kind
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            var kind: String = hotbar[selected_slot]
            if not blocks.has(cell) and Vector2(cell * TILE).distance_to(player_pos) < 150.0 and inventory.get(kind, 0) > 0:
                blocks[cell] = kind
                inventory[kind] -= 1
                var account_ui = get_node_or_null("AccountUI")
                if account_ui != null:
                    account_ui.broadcast_world_event({"type": "tile_update", "x": cell.x, "y": cell.y, "kind": kind, "remove": false})
                status_text = "Placed " + kind
        queue_redraw()

func _attack() -> void:
    if attack_cooldown > 0.0: return
    attack_cooldown = 0.45
    var damage := 22 if equipment["weapon"] == "Wooden Sword" else (38 if equipment["weapon"] == "Copper Blade" else 8)
    for i in range(enemies.size() - 1, -1, -1):
        var enemy: Dictionary = enemies[i]
        if Vector2(enemy["pos"]).distance_to(player_pos) < 76.0:
            enemy["hp"] = int(enemy["hp"]) - damage
            if enemy["hp"] <= 0:
                enemies.remove_at(i)
                inventory["gel"] += 1
                var account_ui = get_node_or_null("AccountUI")
                if account_ui != null and account_ui.has_method("is_signed_in") and account_ui.is_signed_in():
                    account_ui.claim_enemy_reward()
                else:
                    coins += 5
            else:
                enemies[i] = enemy
            break

func _craft(item: String) -> void:
    if not recipes.has(item): return
    var cost: Dictionary = recipes[item]
    for material in cost:
        if inventory.get(material, 0) < cost[material]:
            status_text = "Not enough " + material
            return
    for material in cost:
        inventory[material] -= cost[material]
    if item == "Wooden Sword" or item == "Copper Blade":
        equipment["weapon"] = item
    elif item.ends_with("Helmet"):
        equipment["head"] = item
    elif item.ends_with("Chestplate"):
        equipment["chest"] = item
    elif item.ends_with("Boots"):
        equipment["legs"] = item
    elif item == "Lucky Charm":
        equipment["accessory"] = item
    status_text = "Crafted " + item

func _craft_cosmetic(item: String) -> void:
    var cost: Dictionary = cosmetic_recipes[item]
    for material in cost:
        if inventory.get(material, 0) < cost[material]:
            status_text = "Need more " + material
            return
    for material in cost: inventory[material] -= cost[material]
    owned_cosmetics.append(item)
    equipped_cosmetic = item
    status_text = "Made and equipped " + item

func _buy_cosmetic(item: String) -> void:
    if item in owned_cosmetics:
        equipped_cosmetic = item
        status_text = "Equipped " + item
        return
    var price: int = cosmetic_prices[item]
    if coins < price:
        status_text = "Need %d more coins" % (price - coins)
        return
    coins -= price
    owned_cosmetics.append(item)
    equipped_cosmetic = item
    status_text = "Bought " + item

func _equip_best() -> void:
    if inventory.get("copper", 0) >= 12:
        _craft("Copper Blade")
    elif inventory.get("wood", 0) >= 8:
        _craft("Wooden Sword")

func _draw() -> void:
    var view := get_viewport_rect().size
    # Storybook sky: layered dusk-blue with distant rolling hills.
    draw_rect(Rect2(Vector2.ZERO, view), Color("#9aa9a0"))
    draw_rect(Rect2(Vector2(0, 0), Vector2(view.x, view.y * 0.48)), Color("#a9b9b0"))
    draw_rect(Rect2(Vector2(0, view.y * 0.48), Vector2(view.x, view.y * 0.52)), Color("#c4b99b"))
    for i in range(5):
        var cloud_x := fposmod(float(i * 317) - camera_offset.x * 0.12, view.x + 260.0) - 130.0
        var cloud_y := 76.0 + float((i * 47) % 115)
        draw_rect(Rect2(Vector2(cloud_x, cloud_y), Vector2(76, 13)), Color("#d8d5c5", 0.52))
        draw_rect(Rect2(Vector2(cloud_x + 18, cloud_y - 8), Vector2(42, 18)), Color("#e4dfce", 0.58))
    for i in range(9):
        var hill_x := float(i) * 190.0 - fposmod(camera_offset.x * 0.22, 190.0)
        var hill_color := Color("#788d78") if i % 2 == 0 else Color("#84927b")
        draw_colored_polygon(PackedVector2Array([Vector2(hill_x - 100, 390), Vector2(hill_x + 45, 215 + float(i % 3) * 18), Vector2(hill_x + 210, 390)]), hill_color)
    var left: int = maxi(0, int(camera_offset.x / TILE) - 2)
    var right: int = mini(WORLD_WIDTH, int((camera_offset.x + view.x) / TILE) + 3)
    var top: int = maxi(0, int(camera_offset.y / TILE) - 2)
    var bottom: int = mini(WORLD_HEIGHT, int((camera_offset.y + view.y) / TILE) + 3)
    for x in range(left, right + 1):
        for y in range(top, bottom + 1):
            var cell := Vector2i(x, y)
            if not blocks.has(cell):
                continue
            var kind: String = str(blocks[cell])
            var color := Color("#708b55")
            if kind == "dirt": color = Color("#886448")
            elif kind == "stone": color = Color("#77776b")
            elif kind == "wood": color = Color("#765237")
            elif kind == "leaves": color = Color("#526f43")
            elif kind == "copper": color = Color("#a96f4c")
            elif kind == "ash": color = Color("#665d59")
            elif kind == "mushroom": color = Color("#d4c4a4")
            elif kind == "mushroom_cap": color = Color("#956b82")
            elif kind == "mushroom_soil": color = Color("#68745b")
            elif kind == "crystal": color = Color("#76b7b0")
            elif kind == "crystal_stone": color = Color("#586f75")
            elif kind == "ice": color = Color("#b7c9c4")
            elif kind == "snow": color = Color("#e1e1d2")
            elif kind == "sand": color = Color("#c9b27b")
            elif kind == "relic": color = Color("#c49a50")
            elif kind == "ancient_brick": color = Color("#897b65")
            elif kind == "rune": color = Color("#7fb4a3")
            elif kind == "herb": color = Color("#8eaa69")
            if cell.x >= 140 and cell.x < 280 and kind == "grass": color = Color("#7d956d")
            if cell.x >= 280 and kind == "grass": color = Color("#9a8068")
            var rect := Rect2(Vector2(cell * TILE) - camera_offset, Vector2(TILE, TILE))
            draw_rect(rect, color)
            draw_rect(Rect2(rect.position, Vector2(TILE, 4)), color.lightened(0.16))
            draw_rect(Rect2(rect.position + Vector2(0, TILE - 4), Vector2(TILE, 4)), color.darkened(0.22))
            draw_rect(rect, Color("#352f2a", 0.35), false, 1.0)
            var detail_seed := absi(cell.x * 92821 + cell.y * 68917)
            if kind in ["grass", "dirt", "stone", "sand", "ancient_brick"]:
                var mark := Vector2(rect.position.x + 5 + detail_seed % 17, rect.position.y + 7 + (detail_seed / 7) % 15)
                draw_rect(Rect2(mark, Vector2(4, 3)), color.lightened(0.2))
                if kind == "ancient_brick":
                    draw_line(rect.position + Vector2(0, 16), rect.position + Vector2(TILE, 16), Color("#4c443b", 0.42), 1.0)
                    draw_line(rect.position + Vector2(16, 0), rect.position + Vector2(16, 16), Color("#4c443b", 0.32), 1.0)
    # Distant foliage silhouettes add depth without changing world collision.
    for i in range(12):
        var tree_x := fposmod(float(i * 173) - camera_offset.x * 0.48, view.x + 100.0) - 50.0
        draw_rect(Rect2(Vector2(tree_x + 18, 330), Vector2(9, 78)), Color("#554c3d"))
        draw_circle(Vector2(tree_x + 22, 319), 27, Color("#52694d"))
        draw_circle(Vector2(tree_x + 5, 331), 18, Color("#617653"))
    for remote_id in remote_players:
        var remote_pos: Vector2 = remote_players[remote_id] - camera_offset
        draw_rect(Rect2(remote_pos - Vector2(10, 24), Vector2(20, 36)), Color("#7895a1"))
        draw_rect(Rect2(remote_pos - Vector2(8, 28), Vector2(16, 12)), Color("#d1b18a"))
        draw_string(ThemeDB.fallback_font, remote_pos + Vector2(-28, -34), "Guest", HORIZONTAL_ALIGNMENT_LEFT, 60, 10, Color("#f4e8d0"))
    for enemy in enemies:
        var ep: Vector2 = enemy["pos"] - camera_offset
        var enemy_color := Color("#72965c")
        if enemy["kind"] == "Fungus": enemy_color = Color("#a786a2")
        elif enemy["kind"] == "Ash Slime": enemy_color = Color("#a87561")
        elif enemy["kind"] == "Crystal Mote": enemy_color = Color("#78b8b5")
        elif enemy["kind"] == "Frost Wisp": enemy_color = Color("#c4d7d0")
        elif enemy["kind"] == "Sand Beetle": enemy_color = Color("#b99b63")
        draw_circle(ep + Vector2(0, 2), 14, Color("#3e3a32", 0.35))
        draw_circle(ep, 13, enemy_color)
        draw_rect(Rect2(ep + Vector2(-7, -3), Vector2(4, 4)), Color("#302c29"))
        draw_rect(Rect2(ep + Vector2(3, -3), Vector2(4, 4)), Color("#302c29"))
        draw_arc(ep, 13, PI, TAU, 16, enemy_color.lightened(0.3), 2.0)
    var p := player_pos - camera_offset
    var visual_cosmetic := account_equipped_cosmetic if account_equipped_cosmetic != "None" else equipped_cosmetic
    draw_rect(Rect2(p + Vector2(-12, 15), Vector2(24, 5)), Color("#3e392f", 0.35))
    draw_rect(Rect2(p - Vector2(9, 11), Vector2(18, 26)), Color("#665b4a"))
    draw_rect(Rect2(p - Vector2(8, 23), Vector2(16, 14)), Color("#d6b58d"))
    draw_rect(Rect2(p - Vector2(10, 7), Vector2(20, 5)), Color("#8c6045"))
    draw_rect(Rect2(p - Vector2(8, -9), Vector2(16, 5)), Color("#4c493c"))
    draw_rect(Rect2(p - Vector2(7, 25), Vector2(14, 5)), Color("#8b6b45"))
    if visual_cosmetic.find("Cape") >= 0:
        draw_rect(Rect2(p + Vector2(-13, -8), Vector2(6, 25)), Color("#5b7049"))
    elif visual_cosmetic.find("Crown") >= 0 or visual_cosmetic.find("Hat") >= 0:
        draw_rect(Rect2(p + Vector2(-8, -30), Vector2(16, 6)), Color("#c5a45d"))
    elif visual_cosmetic == "Slime Buddy":
        draw_circle(p + Vector2(23, 7), 8, Color("#7fa36a"))
    # Framed parchment HUD.
    _draw_old_panel(Rect2(Vector2(18, 18), Vector2(535, 145)))
    draw_string(ThemeDB.fallback_font, Vector2(38, 47), "FORGOTTEN WORLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#463b2d"))
    draw_string(ThemeDB.fallback_font, Vector2(38, 70), "A field journal  /  " + biome, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#74634b"))
    draw_string(ThemeDB.fallback_font, Vector2(38, 96), "HEALTH  %d     COINS  %d" % [player_health, coins], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4d4435"))
    draw_string(ThemeDB.fallback_font, Vector2(38, 119), "Dirt %d   Stone %d   Wood %d   Copper %d   Gel %d" % [inventory.dirt, inventory.stone, inventory.wood, inventory.copper, inventory.gel], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#675a46"))
    draw_string(ThemeDB.fallback_font, Vector2(38, 145), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#79684f"))
    draw_string(ThemeDB.fallback_font, Vector2(18, view.y - 83), "FIELD PACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f1e4c7"))
    for i in range(hotbar.size()):
        var x := 24 + i * 54
        _draw_old_panel(Rect2(Vector2(x, view.y - 68), Vector2(48, 48)), i == selected_slot)
        draw_string(ThemeDB.fallback_font, Vector2(x + 8, view.y - 38), str(inventory.get(hotbar[i], 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#453b2d"))
        draw_string(ThemeDB.fallback_font, Vector2(x + 8, view.y - 54), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#8c7755"))
    if show_crafting:
        _draw_old_panel(Rect2(Vector2(550, 100), Vector2(390, 340)))
        draw_string(ThemeDB.fallback_font, Vector2(570, 130), "THE WORKBENCH  /  C TO CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#493c2c"))
        for i in range(craft_names.size()):
            draw_string(ThemeDB.fallback_font, Vector2(570, 160 + i * 27), "%d.  %s" % [i + 1, craft_names[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 420), "Choose a recipe with keys 1-9", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#827052"))
    if show_cosmetics:
        _draw_old_panel(Rect2(Vector2(550, 100), Vector2(390, 270)))
        draw_string(ThemeDB.fallback_font, Vector2(570, 130), "THE TAILOR'S STALL  /  M TO CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#493c2c"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 164), "1  Leaf Crown  -  12 leaves, 2 wood", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 190), "2  Wooden Mask  -  8 wood", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 216), "3  Slime Hat  -  6 gel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 250), "4  Forest Cape  -  35 coins", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#75603d"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 276), "5  Royal Crown  -  90 coins", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#75603d"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 302), "6  Slime Buddy  -  70 coins", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#75603d"))
    if show_quests:
        _draw_old_panel(Rect2(Vector2(550, 100), Vector2(430, 230)))
        draw_string(ThemeDB.fallback_font, Vector2(570, 130), "ADVENTURER'S JOURNAL  /  Q TO CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#493c2c"))
        var quest_y := 164
        for quest_id in quest_definitions:
            var quest: Dictionary = quest_definitions[quest_id]
            var goal: String = str(quest["goal"])
            var current := int(quest_progress.get(goal, 0))
            var target := int(quest["target"])
            var line := "%s  %d/%d  -  %d coins" % [quest["label"], mini(current, target), target, quest["reward"]]
            if quest_claimed.get(quest_id, false): line += "  COMPLETE"
            draw_string(ThemeDB.fallback_font, Vector2(570, quest_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#887044") if quest_claimed.get(quest_id, false) else Color("#5b4c38"))
            quest_y += 30
    if show_inventory:
        _draw_old_panel(Rect2(Vector2(550, 360), Vector2(390, 150)))
        draw_string(ThemeDB.fallback_font, Vector2(570, 390), "TRAVELLER'S EQUIPMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#493c2c"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 420), "Weapon: " + equipment["weapon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 446), "Head: " + equipment["head"] + "  /  Chest: " + equipment["chest"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))
        draw_string(ThemeDB.fallback_font, Vector2(570, 472), "Legs: " + equipment["legs"] + "  /  Accessory: " + equipment["accessory"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#5b4c38"))

func _draw_old_panel(rect: Rect2, highlighted: bool = false) -> void:
    draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color("#302b24", 0.34))
    draw_rect(rect, Color("#d7c7a3"))
    draw_rect(Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8)), Color("#e8dcc0"))
    draw_rect(rect, Color("#8d7652"), false, 2.0)
    draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size - Vector2(10, 10)), Color("#b19a70"), false, 1.0)
    if highlighted:
        draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), Color("#c5a45d"), false, 2.0)


func _record_gather(kind: String) -> void:
    var quest_key := ""
    if kind == "wood": quest_key = "wood"
    elif kind == "crystal": quest_key = "crystal"
    elif kind == "relic": quest_key = "relic"
    elif kind == "rune": quest_key = "runes"
    if quest_key.is_empty():
        return
    quest_progress[quest_key] = int(quest_progress.get(quest_key, 0)) + 1
    _check_quest_rewards()

func _record_biome_visit(name: String) -> void:
    if visited_biomes.has(name):
        return
    visited_biomes[name] = true
    quest_progress["biomes"] = visited_biomes.size()
    status_text = "Discovered " + name
    _check_quest_rewards()

func _check_quest_rewards() -> void:
    for quest_id in quest_definitions:
        if quest_claimed.get(quest_id, false):
            continue
        var quest: Dictionary = quest_definitions[quest_id]
        var goal: String = str(quest["goal"])
        if int(quest_progress.get(goal, 0)) >= int(quest["target"]):
            quest_claimed[quest_id] = true
            coins += int(quest["reward"])
            status_text = "Journal complete: " + str(quest["label"]) + " (+" + str(quest["reward"]) + " coins)"

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _save_game()

func _save_game() -> void:
    var saved_blocks: Array[Dictionary] = []
    for cell in blocks:
        saved_blocks.append({"x": cell.x, "y": cell.y, "kind": str(blocks[cell])})
    var saved_enemies: Array[Dictionary] = []
    for enemy in enemies:
        var pos: Vector2 = enemy["pos"]
        saved_enemies.append({"x": pos.x, "y": pos.y, "hp": enemy["hp"], "speed": enemy["speed"], "kind": enemy["kind"]})
    var data := {
        "version": 1,
        "seed": world_seed,
        "player_x": player_pos.x,
        "player_y": player_pos.y,
        "health": player_health,
        "coins": coins,
        "inventory": inventory,
        "equipment": equipment,
        "owned_cosmetics": owned_cosmetics,
        "equipped_cosmetic": equipped_cosmetic,
        "quest_progress": quest_progress,
        "quest_claimed": quest_claimed,
        "visited_biomes": visited_biomes,
        "blocks": saved_blocks,
        "enemies": saved_enemies
    }
    var file := FileAccess.open("user://world_save.json", FileAccess.WRITE)
    if file == null:
        status_text = "Save failed: " + error_string(FileAccess.get_open_error())
        return
    file.store_string(JSON.stringify(data))
    file.close()
    status_text = "World saved"

func _load_game() -> bool:
    if not FileAccess.file_exists("user://world_save.json"):
        return false
    var file := FileAccess.open("user://world_save.json", FileAccess.READ)
    if file == null:
        status_text = "Save could not be opened"
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not parsed is Dictionary:
        status_text = "Save file is invalid"
        return false
    var data: Dictionary = parsed
    if int(data.get("version", 0)) != 1:
        status_text = "Save version is not supported"
        return false
    world_seed = int(data.get("seed", randi()))
    _generate_world()
    blocks.clear()
    for entry in data.get("blocks", []):
        if entry is Dictionary:
            var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
            blocks[cell] = str(entry.get("kind", "dirt"))
    player_pos = Vector2(float(data.get("player_x", 420.0)), float(data.get("player_y", 260.0)))
    player_health = clampi(int(data.get("health", 100)), 0, 100)
    coins = maxi(0, int(data.get("coins", 0)))
    inventory = data.get("inventory", inventory)
    equipment = data.get("equipment", equipment)
    owned_cosmetics = data.get("owned_cosmetics", ["None"])
    equipped_cosmetic = str(data.get("equipped_cosmetic", "None"))
    quest_progress = data.get("quest_progress", quest_progress)
    quest_claimed = data.get("quest_claimed", quest_claimed)
    visited_biomes = data.get("visited_biomes", visited_biomes)
    enemies.clear()
    for entry in data.get("enemies", []):
        if entry is Dictionary:
            enemies.append({"pos": Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))), "hp": int(entry.get("hp", 35)), "speed": float(entry.get("speed", 35.0)), "kind": str(entry.get("kind", "Slime"))})
    status_text = "World loaded"
    return true


func _serialize_world() -> Dictionary:
    var saved_blocks: Array = []
    for cell in blocks:
        saved_blocks.append([cell.x, cell.y, str(blocks[cell])])
    return {"version": 1, "seed": world_seed, "blocks": saved_blocks}

func _apply_shared_world(data: Dictionary) -> void:
    if int(data.get("version", 0)) != 1:
        status_text = "Shared world version is unsupported"
        return
    world_seed = int(data.get("seed", world_seed))
    blocks.clear()
    for entry in data.get("blocks", []):
        if entry is Array and entry.size() >= 3:
            blocks[Vector2i(int(entry[0]), int(entry[1]))] = str(entry[2])
    status_text = "Shared world loaded"
    queue_redraw()
