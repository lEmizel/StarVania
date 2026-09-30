extends AnimatedSprite2D
## Pilote d'animation du SQUELETTE BLEU (script à lui, copie de
## animator_skeleton.gd au 18 sept. 2026 : son anim "attack" a les mêmes 6
## images à 13 ips, donc les mêmes frames de coup) : hitbox d'attaque aux frames 4-5,
## FX de slash synchronisé avec le coup (caché au repos, coupé si
## l'attaque est interrompue).

@onready var enemi: CharacterBody2D = $"../.."
@onready var collision: Area2D = $"../collision_attack"
@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var slash_fx: AnimatedSprite2D = $"../slash_attack"

## LE SLASH EN SHADER (1er oct. 2026) : le même croissant que les dessins
## `Slash_attack_skeleton`, mais à chaque image d'écran (SCRIPT/SHADER/
## slash_heros.gd, entrée "slash_squelette" ; le classique et le bleu partagent
## les mêmes dessins). Il remplace le dessin tant que `slash_en_shader` est
## coché sur le squelette ; décoché, le dessin revient, à l'identique.
const SLASH_SHADER := preload("res://SCRIPT/SHADER/slash_heros.tscn")
const SLASH_NOM := "slash_squelette"
var _slash_shader: Node2D


func _ready() -> void:
	SignalUtils.connect_signal(self, "frame_changed", self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")
	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	SignalUtils.connect_signal(slash_fx, "animation_finished", self, "_on_slash_finished")
	slash_fx.visible = false
	# le slash en shader : frère du dessin sous POINT (il se retourne avec le
	# squelette), à sa place, à sa taille, à son rang (le dessin passe DERRIÈRE
	# le corps du squelette : le shader aussi)
	_slash_shader = SLASH_SHADER.instantiate()
	_slash_shader.demo_boucle = false
	_slash_shader.position = slash_fx.position
	_slash_shader.scale = slash_fx.scale
	_slash_shader.z_index = slash_fx.z_index
	_slash_shader.z_as_relative = slash_fx.z_as_relative
	slash_fx.add_sibling.call_deferred(_slash_shader)


func _on_body_entered(body: Node) -> void:
	# CAMPS : c'est le monstre qui décide qui est un ennemi et à quelle échelle
	# il frappe (cœurs pour le joueur, points de vie pour un monstre)
	enemi.infliger(body, enemi.global_position.x, "attaque:" + enemi.name)


func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)


# --- FX de slash : même règle de vie que celui du joueur ---

func _on_slash_finished() -> void:
	slash_fx.visible = false


func _play_slash() -> void:
	_stop_slash()
	if enemi.slash_en_shader and _slash_shader.is_inside_tree() and _slash_shader.connait(SLASH_NOM):
		_slash_shader.effet = enemi.slash_effet
		_slash_shader.jouer(SLASH_NOM)
		return
	slash_fx.visible = true
	slash_fx.play("slash")


## le coup est terminé ou interrompu : son slash disparaît, dessiné ou en shader
func _stop_slash() -> void:
	slash_fx.stop()
	slash_fx.visible = false
	if _slash_shader != null:
		_slash_shader.couper()


func _on_frame_changed() -> void:
	match animation:
		"attack":
			match frame:
				0:
					_disable_all_hitboxes()
				4:
					hitbox_1.set_deferred("disabled", false)
					_play_slash()  # le FX part avec le coup
				5:
					_disable_all_hitboxes()
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()


func _on_animation_changed() -> void:
	_disable_all_hitboxes()
	# attaque terminée ou interrompue : le FX de slash meurt avec elle
	_stop_slash()
