class_name CoopHost
extends Node
## The host's side of a multiplayer session, a child of the Dungeon: it shows the other players (RemoteAvatars in
## co-op, ghost opponents in the arena), applies what clients do to monsters, sends everybody a snapshot
## of the world ~15 times a second and keeps the arena score. See Net for the whole picture.
##
## Snapshot: {e: [[net_id, monster_id, variant, x, y, hp, max_hp, aura, boss, effect kinds]],
##            p: [[peer, x, y, aim_x, aim_y, hp, max_hp, flags]], door: bool, t: run text, boss: net id,
##            score: {peer: kills}}

var dungeon: Node2D
var avatars: Dictionary = {}   # peer -> RemoteAvatar (co-op) or Enemy ghost (arena)
var scores: Dictionary = {}    # arena: peer -> kills
var arena := false

var _enemies: Dictionary = {}  # net id -> Enemy
var _timer := 0.0
var _last_state: Dictionary = {}  # peer -> last position update (time), to notice a silent peer


static func attach(world: Node2D) -> CoopHost:
	var host := CoopHost.new()
	host.dungeon = world
	host.arena = String(Net.session.get("kind", "coop")) == "arena"
	world.add_child(host)
	return host


func _ready() -> void:
	Net.host_node = self
	if not Game.loot_dropped.is_connected(_on_loot):
		Game.loot_dropped.connect(_on_loot)
	for peer in Net.roster:
		if int(peer) != 1:
			_make_avatar(int(peer))
		scores[int(peer)] = 0


func _exit_tree() -> void:
	if Net.host_node == self:
		Net.host_node = null


func _make_avatar(peer: int) -> void:
	var info: Dictionary = Net.roster.get(peer, {})
	var parent: Node = dungeon.get_parent()
	if arena:
		avatars[peer] = PvpGhost.make(parent, peer, info)
		return
	var avatar := RemoteAvatar.new()
	avatar.setup(peer, info)
	parent.add_child(avatar)
	avatars[peer] = avatar


func on_peer_left(peer: int) -> void:
	if avatars.has(peer) and is_instance_valid(avatars[peer]):
		avatars[peer].queue_free()
	avatars.erase(peer)
	scores.erase(peer)
	if Net.roster.size() < 2:
		Game.say("Everyone else has left.")
	if dungeon.has_method("on_net_peer_left"):
		dungeon.on_net_peer_left(peer)


# ---------- from clients ----------

func on_client_state(peer: int, state: Array) -> void:
	if state.size() < 7 or not avatars.has(peer) or not is_instance_valid(avatars[peer]):
		return
	if arena:
		PvpGhost.apply_state(avatars[peer], state)
	else:
		avatars[peer].apply_state(state)
	_last_state[peer] = Time.get_ticks_msec()


## A client hit a ghost monster: the real one takes it (its numbers capped, so a bad client cannot one-shot a boss).
func on_client_hit(_peer: int, net_id: int, hit: Dictionary) -> void:
	var enemy: Enemy = _enemies.get(net_id)
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	var clean := {
		"damage": clampf(float(hit.get("damage", 0.0)), 0.0, 400.0),
		"element": String(hit.get("element", "")),
		"knockback": clampf(float(hit.get("knockback", 50.0)), 0.0, 400.0),
		"from": hit.get("from", enemy.global_position + Vector2.UP),
		"juice": bool(hit.get("juice", true)),
		"apply": hit.get("apply", {}),
	}
	if hit.has("text_offset"):
		clean["text_offset"] = hit["text_offset"]
	enemy.take_hit(clean)


func on_client_down(_peer: int) -> void:
	pass  # a downed hero shows hp <= 0 in its state; Dungeon.check_wipe reads that


## Arena: peer `victim` fell, last hurt by `killer`.
func on_pvp_down(victim: int, killer: int) -> void:
	if not arena or killer == 0 or killer == victim or not scores.has(killer):
		return
	scores[killer] = int(scores[killer]) + 1
	Net.send_say("%s defeated %s  (%d)" % [_name_of(killer), _name_of(victim), int(scores[killer])])
	Game.say("%s defeated %s" % [_name_of(killer), _name_of(victim)])
	if int(scores[killer]) >= Net.ARENA_KILLS:
		var info := {"kind": "arena", "winner": killer, "winner_name": _name_of(killer), "scores": scores}
		Net.end_session(info)
		if dungeon.has_method("on_net_end"):
			dungeon.on_net_end(info)


func _name_of(peer: int) -> String:
	return String(Net.roster.get(peer, {}).get("name", "Hero"))


# ---------- to clients ----------

func _on_loot(drops: Array, position: Vector2) -> void:
	Net.send_loot(drops, position)


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0 / Net.SYNC_RATE:
		return
	_timer = 0.0
	Net.send_state(snapshot())


func snapshot() -> Dictionary:
	var entries: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.ghost or enemy.is_queued_for_deletion():
			continue
		if enemy.net_id == 0:
			enemy.net_id = Net.next_net_id()
		_enemies[enemy.net_id] = enemy
		var kinds: Array = enemy.effects.keys()
		entries.append([enemy.net_id, enemy.monster_id, enemy.variant, enemy.global_position.x, enemy.global_position.y,
			enemy.hp, enemy.max_hp, enemy.aura, 1 if enemy.boss else 0, kinds])
	for id in _enemies.keys():
		if not is_instance_valid(_enemies[id]) or _enemies[id].is_queued_for_deletion():
			_enemies.erase(id)
	var players: Array = []
	var hero := dungeon.get_parent().get_node_or_null("Player") as Player
	if hero:
		players.append([1] + hero.net_state())
	for peer in avatars:
		var avatar: Node2D = avatars[peer]
		if not is_instance_valid(avatar):
			continue
		if arena:
			players.append(PvpGhost.state_of(peer, avatar))
		else:
			players.append([peer, avatar.global_position.x, avatar.global_position.y, avatar.aim.x, avatar.aim.y, avatar.hp, avatar.max_hp,
				(1 if avatar.moving else 0) | (2 if avatar.dodging else 0)])
	var boss_id := 0
	if Game.boss != null and is_instance_valid(Game.boss) and not Game.boss.ghost:
		boss_id = Game.boss.net_id
	var door_open: bool = dungeon.get("_exit_door") != null and dungeon._exit_door.open
	return {"e": entries, "p": players, "door": door_open, "t": Game.run_text, "boss": boss_id, "score": scores.duplicate(),
		"state": String(dungeon.get("state"))}


## All heroes are down (the host's and every guest's): the run is lost.
func wiped() -> bool:
	var hero := dungeon.get_parent().get_node_or_null("Player") as Player
	if hero == null or hero.hp > 0.0:
		return false
	for peer in avatars:
		var avatar: Node2D = avatars[peer]
		if is_instance_valid(avatar) and avatar.get("hp") != null and float(avatar.hp) > 0.0:
			return false
	return true
