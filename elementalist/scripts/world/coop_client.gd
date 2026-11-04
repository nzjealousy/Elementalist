class_name CoopClient
extends Node
## A guest's side of a multiplayer session, a child of the Dungeon (which runs in "viewer" mode: it builds the host's
## rooms but spawns nothing). The guest plays their own Player here; the host's monsters are ghost Enemies kept
## in step with the host's snapshots, the other players are RemoteAvatars (co-op) or ghost opponents (arena).
## Everything the guest does to a ghost goes to the host (Enemy.take_hit -> Net.send_hit); rewards, loot and damage
## come back as messages. See Net.

var dungeon: Node2D
var ghosts: Dictionary = {}     # net id -> Enemy ghost (monsters)
var others: Dictionary = {}     # peer -> RemoteAvatar or arena ghost Enemy
var arena := false

var _timer := 0.0
var _seen_at: Dictionary = {}   # net id or peer -> last snapshot tick it appeared in
var _tick := 0


static func attach(world: Node2D) -> CoopClient:
	var client := CoopClient.new()
	client.dungeon = world
	client.arena = String(Net.session.get("kind", "coop")) == "arena"
	world.add_child(client)
	return client


func _ready() -> void:
	Net.client_node = self
	Net.state_received.connect(apply_snapshot)
	Net.loot_received.connect(_on_loot)
	Net.kill_received.connect(func(xp, class_xp): Game.reward_kill(xp, class_xp))
	Net.damage_received.connect(_on_damage)
	Net.pvp_damage_received.connect(_on_pvp_damage)
	Net.said.connect(func(text): Game.say(text))
	if not Net.last_snapshot.is_empty():
		apply_snapshot(Net.last_snapshot)


func _exit_tree() -> void:
	if Net.client_node == self:
		Net.client_node = null


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0 / Net.SYNC_RATE:
		return
	_timer = 0.0
	var hero := dungeon.get_parent().get_node_or_null("Player") as Player
	if hero:
		Net.send_position(hero.net_state())


## Brings the ghosts and the other players in line with a snapshot from the host.
func apply_snapshot(snapshot: Dictionary) -> void:
	if not is_inside_tree():
		return
	_tick += 1
	var room_node: Node = dungeon.get("_room_node")
	if room_node == null:
		return
	for entry in snapshot.get("e", []):
		var id := int(entry[0])
		var ghost: Enemy = ghosts.get(id)
		if ghost == null or not is_instance_valid(ghost):
			ghost = _make_ghost(room_node, entry)
			ghosts[id] = ghost
		ghost.net_pos = Vector2(float(entry[3]), float(entry[4]))
		ghost.max_hp = maxf(float(entry[6]), 1.0)
		ghost.hp = clampf(float(entry[5]), 0.0, ghost.max_hp)
		ghost.aura = String(entry[7])
		ghost.effects.clear()
		for kind in entry[9]:
			ghost.effects[String(kind)] = {"time": 0.5, "power": 1.0}
		_seen_at[id] = _tick
	for id in ghosts.keys():
		if _seen_at.get(id, 0) != _tick:
			if is_instance_valid(ghosts[id]):
				ghosts[id].queue_free()
			ghosts.erase(id)
	var boss_id := int(snapshot.get("boss", 0))
	Game.boss = ghosts.get(boss_id) if boss_id != 0 else null

	var me := Net.my_id()
	var parent: Node = dungeon.get_parent()
	for entry in snapshot.get("p", []):
		var peer := int(entry[0])
		if peer == me:
			continue
		var other: Node2D = others.get(peer)
		if other == null or not is_instance_valid(other):
			var info: Dictionary = Net.roster.get(peer, {})
			if arena:
				other = PvpGhost.make(parent, peer, info)
			else:
				var avatar := RemoteAvatar.new()
				avatar.setup(peer, info)
				parent.add_child(avatar)
				other = avatar
			others[peer] = other
		var state: Array = entry.slice(1)
		if arena:
			PvpGhost.apply_state(other, state)
		else:
			other.apply_state(state)
		_seen_at[-peer] = _tick
	for peer in others.keys():
		if _seen_at.get(-int(peer), 0) != _tick:
			if is_instance_valid(others[peer]):
				others[peer].queue_free()
			others.erase(peer)

	Game.run_text = String(snapshot.get("t", Game.run_text))
	if dungeon.has_method("set_net_door"):
		dungeon.set_net_door(bool(snapshot.get("door", false)))
	if dungeon.has_method("set_net_scores"):
		dungeon.set_net_scores(snapshot.get("score", {}))


func _make_ghost(room_node: Node, entry: Array) -> Enemy:
	var enemy: Enemy = (load(Monsters.ENEMY_SCENE) as PackedScene).instantiate()
	enemy.configure(String(entry[1]), String(entry[2]))
	enemy.ghost = true
	enemy.net_id = int(entry[0])
	enemy.position = Vector2(float(entry[3]), float(entry[4]))
	room_node.add_child(enemy)
	enemy.net_pos = enemy.position
	return enemy


func _on_loot(drops: Array, position: Vector2) -> void:
	if dungeon.has_method("_on_loot_dropped"):
		dungeon._on_loot_dropped(drops, position)


## The host's monsters hurt this hero.
func _on_damage(amount: float, from: Vector2) -> void:
	var hero := dungeon.get_parent().get_node_or_null("Player") as Player
	if hero:
		hero.take_damage(amount, from)


## An opponent in the arena hit this hero.
func _on_pvp_damage(hit: Dictionary, attacker: int) -> void:
	var hero := dungeon.get_parent().get_node_or_null("Player") as Player
	if hero == null:
		return
	if dungeon.has_method("note_attacker"):
		dungeon.note_attacker(attacker)
	hero.take_damage(float(hit.get("damage", 0.0)) * Net.PVP_DAMAGE, hit.get("from", hero.global_position + Vector2.UP))
