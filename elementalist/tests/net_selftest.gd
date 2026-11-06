extends Node
## Two-process multiplayer test (loopback). Run one copy as the host and one as a guest:
##   godot --headless --path elementalist res://tests/net_selftest.tscn -- --role=host --port=24999
##   godot --headless --path elementalist res://tests/net_selftest.tscn -- --role=client --port=24999
## (tools/run_net_test.ps1 starts both). Each prints PASS/FAIL lines and exits 1 if anything failed.

var role := "host"
var port := 24999
var passes := 0
var failures: Array[String] = []

# what each side collected
var got_room: Dictionary = {}
var got_state: Dictionary = {}
var got_loot: Array = []
var got_kill: Array = []
var got_damage: Array = []
var got_say := ""
var got_end: Dictionary = {}
var got_pvp: Array = []
var host_states: Array = []
var host_hits: Array = []
var host_downs := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	Game.character.display_name = "Hostess" if role == "host" else "Guest"
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	print("NETTEST %s: %d passed, %d failed" % [role, passes, failures.size()])
	if not failures.is_empty():
		print("NETTEST %s FAILED: %s" % [role, " | ".join(failures)])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if not failures.is_empty() else 0)


func _check(name: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS ", name)
	else:
		failures.append(name)
		print("FAIL ", name)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var waited := 0.0
	while not condition.call() and waited < seconds:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return condition.call()


# ---------- the host's stand-in for CoopHost ----------

func on_client_state(_peer: int, state: Array) -> void:
	host_states.append(state)


func on_client_hit(_peer: int, net_id: int, hit: Dictionary) -> void:
	host_hits.append([net_id, hit])


func on_client_down(_peer: int) -> void:
	host_downs += 1


func on_pvp_down(_victim: int, _killer: int) -> void:
	pass


func on_peer_left(_peer: int) -> void:
	pass


# ---------- host ----------

func _run_host() -> void:
	_check("the host starts", Net.host(port) == OK)
	_check("the host is in the roster", Net.roster.has(1) and Net.roster[1]["name"] == "Hostess")
	Net.host_node = self
	Net.pvp_damage_received.connect(func(hit, attacker): got_pvp.append([hit, attacker]))
	var joined := await _wait_for(func(): return Net.roster.size() >= 2, 25.0)
	_check("a guest joined", joined)
	if not joined:
		return
	Net.session = {"kind": "arena", "tier": 1, "seed": 0}  # players hurt each other only in the arena (after the hello: a session refuses newcomers)
	var guest := 0
	for id in Net.roster:
		if int(id) != 1:
			guest = int(id)
	_check("the guest's hero was recorded", Net.roster[guest]["name"] == "Guest" and Net.roster[guest]["level"] >= 1 and Net.roster[guest]["look"].has("parts"))
	await get_tree().create_timer(0.5).timeout

	Net.send_room(DungeonGen.camp_room(), 0, 0, "Floor 1/5")
	Net.send_state({"e": [[7, "slime", "", 40.0, 50.0, 30.0, 40.0, "fire", 0, ["dot"], 1]], "p": [[1, 10.0, 20.0, 30.0, 20.0, 80.0, 100.0, Player.pack_flags(true, false, false, Player.glow_code("fire"))]], "door": true, "t": "Floor 1/5", "boss": 0, "score": {}})
	Net.send_loot([{"kind": "gold", "amount": 5}], Vector2(10, 20))
	Net.send_kill(12, 2)
	Net.send_damage(guest, 7.5, Vector2(1, 2), Enemy.SLAM_STUN)
	Net.send_say("hello guest")
	await get_tree().create_timer(1.5).timeout
	_check("the guest's position reached the host", not host_states.is_empty() and host_states[0].size() == 9 and absf(float(host_states[0][0]) - 11.0) < 0.01)
	_check("with the guest's cast count and its element", not host_states.is_empty() and int(host_states[0][7]) == 2 and int(host_states[0][8]) == Player.glow_code("air"))
	_check("the guest's hit reached the host", host_hits.size() == 1 and host_hits[0][0] == 42 and float(host_hits[0][1]["damage"]) == 9.0 and host_hits[0][1]["from"] == Vector2(1, 1))
	_check("the guest's fall reached the host", host_downs == 1)
	_check("the guest's duel hit on the host arrived", got_pvp.size() == 1 and float(got_pvp[0][0]["damage"]) == 4.0 and int(got_pvp[0][1]) == guest)
	Net.end_session({"kind": "coop", "won": true, "bonus": 150})
	await get_tree().create_timer(1.0).timeout


# ---------- guest ----------

func _run_client() -> void:
	await get_tree().create_timer(2.5).timeout  # let the host open its port
	var joined_flag := [false]
	Net.joined.connect(func(): joined_flag[0] = true)
	Net.room_received.connect(func(data): got_room = data)
	Net.state_received.connect(func(snapshot): got_state = snapshot)
	Net.loot_received.connect(func(drops, position): got_loot = [drops, position])
	Net.kill_received.connect(func(xp, class_xp): got_kill = [xp, class_xp])
	Net.damage_received.connect(func(amount, from, stun_time): got_damage = [amount, from, stun_time])
	Net.said.connect(func(text): got_say = text)
	Net.end_received.connect(func(info): got_end = info)
	_check("the guest starts joining", Net.join("127.0.0.1", port) == OK)
	_check("the guest is accepted", await _wait_for(func(): return joined_flag[0], 15.0))
	_check("the guest sees the roster", Net.roster.size() == 2 and Net.roster.has(1) and Net.roster[1]["name"] == "Hostess")
	_check("the guest knows it is a guest", Net.is_client() and Net.my_id() != 1)

	await get_tree().create_timer(0.8).timeout
	Net.send_position([11.0, 21.0, 31.0, 21.0, 90.0, 100.0, 3, 2, Player.glow_code("air")])
	Net.send_hit(42, {"damage": 9.0, "element": "fire", "from": Vector2(1, 1), "knockback": 50.0})
	Net.send_down()
	Net.send_pvp_hit(1, {"damage": 4.0, "element": "air", "from": Vector2(0, 0)})
	await _wait_for(func(): return not got_end.is_empty(), 15.0)

	_check("the room arrived intact", got_room.has("room") and int(got_room["room"]["cols"]) == 24 and got_room["run_text"] == "Floor 1/5" and Net.room_data == got_room)
	_check("the snapshot arrived", got_state.has("e") and got_state["e"][0][1] == "slime" and got_state["door"] == true and Net.last_snapshot == got_state)
	_check("each monster carries its pose code", got_state.has("e") and got_state["e"][0].size() == 11 and int(got_state["e"][0][10]) == 1)
	_check("the loot arrived", got_loot.size() == 2 and got_loot[0][0]["amount"] == 5 and got_loot[1] == Vector2(10, 20))
	_check("the kill reward arrived", got_kill == [12, 2])
	_check("the damage arrived, with the slam's stun", got_damage.size() == 3 and absf(float(got_damage[0]) - 7.5) < 0.001 and got_damage[1] == Vector2(1, 2) and is_equal_approx(float(got_damage[2]), Enemy.SLAM_STUN))
	_check("the guest sees the host's glow", got_state.has("p") and Player.glow_color(int(Player.unpack_flags(int(got_state["p"][0][7]))["glow"])) == Elements.color_of("fire"))
	_check("the host's message arrived", got_say == "hello guest")
	_check("the end of the session arrived", got_end.get("won", false) == true and int(got_end.get("bonus", 0)) == 150)
