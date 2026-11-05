extends Node
## Multiplayer: up to four players over ENet, one of them the host. Autoload "Net".
##
## The model: the HOST runs the world (monsters, doors, loot, the dungeon's rooms). Every player, the host
## included, plays their own hero locally with their own input, so the game feels the same for everyone.
## Clients see the host's monsters as "ghost" Enemies (same sprites and bars, no thinking), and what a
## client does to a ghost is sent to the host as a HIT; what the host's monsters do to a client comes back
## as DAMAGE. Positions of players are exchanged ~15 times a second and shown as RemoteAvatars.
## Two kinds of session: "coop" (the dungeon, together) and "arena" (a duel, last hero standing).
## This script is only the plumbing: the roster (who is here), the lobby handshake and the RPC hub that
## hands messages to CoopHost / CoopClient, which live in the dungeon scene.

signal roster_changed
signal joined                      # (client) the host accepted us
signal join_failed(reason: String)
signal disconnected(reason: String)
signal session_begun(session: Dictionary)
signal room_received(room: Dictionary)
signal state_received(snapshot: Dictionary)
signal loot_received(drops: Array, position: Vector2)
signal kill_received(xp: int, class_xp: int)
signal damage_received(amount: float, from: Vector2, stun_time: float)
signal pvp_damage_received(hit: Dictionary, attacker: int)
signal end_received(info: Dictionary)
signal said(text: String)

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const PROTOCOL := 3   # 2: DAMAGE carries a stun time, and the state flags carry stunned and the glow; 3: each monster carries its pose code
const SYNC_RATE := 15.0          # snapshots and position updates per second
const ARENA_KILLS := 3           # kills that win an arena match
const PVP_DAMAGE := 0.7          # a player's hit on another player lands at this share
const HELLO_TIMEOUT := 5.0       # a peer that has not said hello by then is dropped (it holds one of the 3 slots)
const MAX_HIT_DAMAGE := 400.0    # a client's hit (on a monster or a player) is capped at this
## A hostile host could hand a guest any reward, and the guest saves it into their real hero: capped generously.
const KILL_XP_MAX := 4000        # the richest kill is a tier-5 boss, 1000 xp; about 4x
const KILL_CLASS_XP_MAX := 400   # 1 + xp / 10, so 101 for that boss
const CLEAR_BONUS_MAX := 1500    # 150 x tier 5 x 1.6 (Warlord) = 1200
const LOOK_PART_MAX := 32        # a part id ("robe_long") is short
const LOOK_PALETTE_MAX := 32     # a real look has about 15 colours

var mode := "offline"            # "offline", "host" or "client"
var roster: Dictionary = {}      # peer id -> {name, class, level, look}
var session: Dictionary = {}     # {kind: "coop" | "arena", tier, seed}
var room_data: Dictionary = {}   # the latest room the host sent {room, floor, index, run_text}
var last_snapshot: Dictionary = {}

# who handles in-scene traffic (set by CoopHost / CoopClient while a dungeon scene is up)
var host_node: Node = null
var client_node: Node = null

var _next_net_id := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host"))
	multiplayer.server_disconnected.connect(func(): _lost("The host left"))


func is_host() -> bool:
	return mode == "host"


func is_client() -> bool:
	return mode == "client"


func is_online() -> bool:
	return mode != "offline"


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## What this machine tells the others about its hero.
func local_info() -> Dictionary:
	var character := Game.character
	return {
		"name": character.display_name, "class": character.class_id, "level": character.level,
		"look": HeroLook.for_character(character), "version": PROTOCOL,
	}


func next_net_id() -> int:
	_next_net_id += 1
	return _next_net_id


# ---------- connecting ----------

func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "host"
	roster = {1: _clean_info(local_info())}
	roster_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	roster = {}
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	roster = {}
	session = {}
	room_data = {}
	last_snapshot = {}
	host_node = null
	client_node = null


func _on_peer_connected(id: int) -> void:
	# a new peer must say hello (with its hero) before it counts; one that never does is dropped
	if is_host():
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(_drop_if_silent.bind(id))


func _drop_if_silent(id: int) -> void:
	if is_host() and multiplayer.get_peers().has(id) and not roster.has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_connected() -> void:
	_hello.rpc_id(1, local_info())


func _on_peer_disconnected(id: int) -> void:
	if is_host() and roster.has(id):
		roster.erase(id)
		_roster.rpc(roster)
		roster_changed.emit()
		if host_node and host_node.has_method("on_peer_left"):
			host_node.on_peer_left(id)


func _fail(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func _lost(reason: String) -> void:
	leave()
	disconnected.emit(reason)


## Only plain, bounded data from a stranger's hello.
func _clean_info(info: Dictionary) -> Dictionary:
	var name_text: Variant = info.get("name")
	var class_id: Variant = info.get("class")
	return {
		"name": Game.clean_name(name_text if name_text is String else "Hero"),
		"class": class_id if class_id is String and Classes.CLASSES.has(class_id) else Classes.NEUTRAL_CLASS,
		"level": int(clean_num(info.get("level"), 1, 99, 1)),
		"look": _clean_look(info.get("look")),
	}


## A look exactly as HeroLook.for_character makes it ({parts: {part key: id}, palette: {key: "rrggbb"}}), else {}
## (the default look of the class): every avatar composes it into pictures, so nothing odd or giant gets through.
func _clean_look(look: Variant) -> Dictionary:
	if not (look is Dictionary and look.size() == 2 and look.get("parts") is Dictionary and look.get("palette") is Dictionary):
		return {}
	for key in look["parts"]:
		var part: Variant = look["parts"][key]
		if not (key in HeroLook.PART_KEYS and part is String and part.length() <= LOOK_PART_MAX):
			return {}
	if look["palette"].size() > LOOK_PALETTE_MAX:
		return {}
	for key in look["palette"]:
		var colour: Variant = look["palette"][key]
		if not (key is String and key.length() <= LOOK_PART_MAX and colour is String and colour.length() <= 7 and Color.html_is_valid(colour)):
			return {}
	return look


## A number from a peer: wrong types give `fallback`, NaN and INF count as 0, and it is kept within low..high.
func clean_num(value: Variant, low: float, high: float, fallback: float = 0.0) -> float:
	if not (value is int or value is float):
		return fallback
	var number := float(value)
	return clampf(number if is_finite(number) else 0.0, low, high)


## True if `values` is an Array whose first `count` entries are all numbers (a snapshot or position entry).
func all_numbers(values: Variant, count: int) -> bool:
	if not (values is Array and values.size() >= count):
		return false
	for i in count:
		if not (values[i] is int or values[i] is float):
			return false
	return true


## The sender of an any_peer call, or 0 if it has not passed the hello handshake (a stranger).
func _known_sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if multiplayer.is_server() and roster.has(id) else 0


# ---------- the lobby handshake ----------

@rpc("any_peer", "reliable")
func _hello(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		return  # one hello per peer
	if info.get("version") != PROTOCOL:
		_refuse.rpc_id(id, "Different game version")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if roster.size() >= MAX_PLAYERS or not session.is_empty():
		_refuse.rpc_id(id, "The game is full or already started")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	roster[id] = _clean_info(info)
	_roster.rpc(roster)
	roster_changed.emit()


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable")
func _roster(new_roster: Dictionary) -> void:
	var first := roster.is_empty()
	roster = new_roster
	if first:
		joined.emit()
	roster_changed.emit()


# ---------- starting and ending a session ----------

## Host: begin the session for everyone. "coop" takes a dungeon tier; "arena" needs none.
func start_session(kind: String, tier: int = 1) -> void:
	if not is_host() or roster.size() < 2:
		return
	session = {"kind": kind, "tier": tier, "seed": randi()}
	_begin.rpc(session)
	_enter_session()


@rpc("authority", "reliable")
func _begin(new_session: Dictionary) -> void:
	session = new_session
	_enter_session()


func _enter_session() -> void:
	room_data = {}
	last_snapshot = {}
	session_begun.emit(session)
	if is_host():
		if String(session["kind"]) == "arena":
			Game.begin_arena()
		else:
			Game.begin_run(int(session["tier"]))
	else:
		Game.begin_net_client(String(session["kind"]))


## Host: the session is over for everybody (they go back to the menu / camp on their own).
func end_session(info: Dictionary) -> void:
	if is_host():
		_end.rpc(info)


@rpc("authority", "reliable")
func _end(info: Dictionary) -> void:
	end_received.emit(info)


# ---------- host -> clients ----------

func send_room(room: Dictionary, floor_number: int, index: int, run_text: String) -> void:
	room_data = {"room": room, "floor": floor_number, "index": index, "run_text": run_text}
	if is_host() and roster.size() > 1:
		_room.rpc(room_data)


@rpc("authority", "reliable")
func _room(data: Dictionary) -> void:
	room_data = data
	room_received.emit(data)


func send_state(snapshot: Dictionary) -> void:
	if is_host() and roster.size() > 1:
		_state.rpc(snapshot)


@rpc("authority", "unreliable")
func _state(snapshot: Dictionary) -> void:
	last_snapshot = snapshot
	state_received.emit(snapshot)


func send_loot(drops: Array, position: Vector2) -> void:
	if is_host() and roster.size() > 1:
		_loot.rpc(drops, position)


@rpc("authority", "reliable")
func _loot(drops: Array, position: Vector2) -> void:
	loot_received.emit(drops, position)


func send_kill(xp: int, class_xp: int) -> void:
	if is_host() and roster.size() > 1:
		_kill.rpc(xp, class_xp)


@rpc("authority", "reliable")
func _kill(xp: int, class_xp: int) -> void:
	var reward := clean_kill(xp, class_xp)
	kill_received.emit(reward.x, reward.y)


## A kill reward from the host, capped (it is saved into this guest's real hero).
func clean_kill(xp: int, class_xp: int) -> Vector2i:
	return Vector2i(clampi(xp, 0, KILL_XP_MAX), clampi(class_xp, 0, KILL_CLASS_XP_MAX))


## The clear bonus and tier a guest books from the host's end-of-run info, capped and checked (saved into the real hero).
func clean_clear_reward(info: Dictionary) -> Dictionary:
	var tier: Variant = info.get("tier", 0)
	var known := (tier is int or tier is float) and Game.TIERS.has(int(tier))
	return {"bonus": int(clean_num(info.get("bonus"), 0, CLEAR_BONUS_MAX)), "tier": int(tier) if known else 0}


## `stun_time` > 0: the hero is stunned that long too if the hit lands (a boss slam).
func send_damage(peer: int, amount: float, from: Vector2, stun_time: float = 0.0) -> void:
	if is_host() and peer != 1:
		_damage.rpc_id(peer, amount, from, stun_time)


@rpc("authority", "reliable")
func _damage(amount: float, from: Vector2, stun_time: float) -> void:
	damage_received.emit(amount, from, clampf(stun_time, 0.0, 2.0))


func send_say(text: String) -> void:
	if is_host() and roster.size() > 1:
		_say.rpc(text)


@rpc("authority", "reliable")
func _say(text: String) -> void:
	said.emit(text)


# ---------- clients -> host ----------

## A client's position, aim and health, for the others to see.
func send_position(state: Array) -> void:
	if is_client():
		_pos.rpc_id(1, state)


@rpc("any_peer", "unreliable")
func _pos(state: Array) -> void:
	var sender := _known_sender()
	if sender != 0 and host_node and host_node.has_method("on_client_state"):
		host_node.on_client_state(sender, state)


## What a client did to a ghost monster; the host applies it to the real one.
func send_hit(net_id: int, hit: Dictionary) -> void:
	if is_client():
		_hit.rpc_id(1, net_id, hit)


@rpc("any_peer", "reliable")
func _hit(net_id: int, hit: Dictionary) -> void:
	var sender := _known_sender()
	if sender != 0 and host_node and host_node.has_method("on_client_hit"):
		host_node.on_client_hit(sender, net_id, hit)


## A client's hero fell.
func send_down() -> void:
	if is_client():
		_down.rpc_id(1)


@rpc("any_peer", "reliable")
func _down() -> void:
	var sender := _known_sender()
	if sender != 0 and host_node and host_node.has_method("on_client_down"):
		host_node.on_client_down(sender)


# ---------- the arena: players hit each other ----------

## Hit player `target` (a peer id). From the host it goes straight out; from a client via the host.
func send_pvp_hit(target: int, hit: Dictionary) -> void:
	if not is_online():
		return
	if is_host():
		_pvp_deliver(target, hit, 1)
	else:
		_pvp_hit.rpc_id(1, target, hit)


@rpc("any_peer", "reliable")
func _pvp_hit(target: int, hit: Dictionary) -> void:
	var sender := _known_sender()
	if sender != 0:
		_pvp_deliver(target, hit, sender)


## Players hurt each other only in the arena, and only with the numbers the receiver uses (Dungeon._on_host_pvp_damage,
## CoopClient._on_pvp_damage). The host's own hits come through here too.
func _pvp_deliver(target: int, hit: Dictionary, attacker: int) -> void:
	if String(session.get("kind", "")) != "arena" or not roster.has(target):
		return
	var clean := clean_pvp_hit(hit)
	if target == 1:
		pvp_damage_received.emit(clean, attacker)
	else:
		_pvp_damage.rpc_id(target, clean, attacker)


## A PvP hit rebuilt from what the receiver reads: damage (capped) and where it came from.
func clean_pvp_hit(hit: Dictionary) -> Dictionary:
	var clean := {"damage": clean_num(hit.get("damage"), 0.0, MAX_HIT_DAMAGE)}
	var from: Variant = hit.get("from")
	if from is Vector2 and from.is_finite():
		clean["from"] = from
	return clean


@rpc("authority", "reliable")
func _pvp_damage(hit: Dictionary, attacker: int) -> void:
	pvp_damage_received.emit(hit, attacker)


## My hero fell in the arena (`killer` is the peer that hit me last, 0 if nobody).
func send_pvp_down(killer: int) -> void:
	if is_host():
		if host_node and host_node.has_method("on_pvp_down"):
			host_node.on_pvp_down(1, killer)
	elif is_client():
		_pvp_down.rpc_id(1, killer)


@rpc("any_peer", "reliable")
func _pvp_down(killer: int) -> void:
	var sender := _known_sender()
	if sender != 0 and host_node and host_node.has_method("on_pvp_down"):
		host_node.on_pvp_down(sender, killer)
