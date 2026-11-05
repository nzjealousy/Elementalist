class_name PvpGhost
extends RefCounted
## Another player in the ARENA, as a ghost Enemy wearing their hero's picture. Because it is an Enemy, every
## way you can hurt a monster (bolts, areas, slashes, spins) works on it for free; take_hit on a ghost
## sends the hit to the player it stands for (Net.send_pvp_hit), who takes it as damage.

static func make(parent: Node, peer: int, info: Dictionary) -> Enemy:
	var enemy: Enemy = (load(Monsters.ENEMY_SCENE) as PackedScene).instantiate()
	enemy.configure("pvp_avatar")
	enemy.ghost = true
	enemy.pvp_peer = peer
	enemy.display_name = String(info.get("name", "Hero"))
	var look: Dictionary = info.get("look", {})
	var prefix: String
	if look.has("parts") and look.has("palette"):
		prefix = HeroComposer.register(look)
	else:
		prefix = HeroComposer.register(HeroLook.for_class(String(info.get("class", "wanderer"))))
	enemy.sprite_id = prefix + ":down"
	enemy.set_meta("prefix", prefix)
	parent.add_child(enemy)
	enemy.sprite.offset = Vector2(0, -9)  # the hero stands as it does on its own machine
	enemy.net_pos = enemy.global_position
	return enemy


## state: [x, y, aim_x, aim_y, hp, max_hp, flags] (flags: 1 moving, 2 dodging).
static func apply_state(enemy: Enemy, state: Array) -> void:
	enemy.net_pos = Vector2(float(state[0]), float(state[1]))
	enemy.net_aim = Vector2(float(state[2]), float(state[3]))
	enemy.max_hp = maxf(float(state[5]), 1.0)
	enemy.hp = clampf(float(state[4]), 0.0, enemy.max_hp)
	var flags := int(state[6])
	enemy.net_moving = flags & 1 != 0
	enemy.net_dodging = flags & 2 != 0


static func state_of(peer: int, enemy: Enemy) -> Array:
	return [peer, enemy.net_pos.x, enemy.net_pos.y, enemy.net_aim.x, enemy.net_aim.y, enemy.hp, enemy.max_hp,
		(1 if enemy.net_moving else 0) | (2 if enemy.net_dodging else 0)]
