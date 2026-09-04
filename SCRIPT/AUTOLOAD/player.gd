extends Node

# Dernier checkpoint croisé : position + scène — un NodePath ne survivrait
# pas au rechargement de la scène après la mort (ancien bug de respawn)
var last_checkpoint_pos := Vector2.ZERO
var last_checkpoint_scene := ""
var has_checkpoint := false
var last_door_id: int = -1
# Élan à conserver en traversant un passage en courant : capturé par
# passage.gd, restitué par spawnplayer de l'autre côté (une seule fois)
var transition_velocity := Vector2.ZERO
var transition_direction: int = 1
var has_transition_momentum := false

var blood := 0
# La vie est comptée en CŒURS : 1 dégât = 1 cœur perdu.
# (garder hp/MAX_HP synchronisés avec max_hearts)
var hp := 5
var MAX_HP := 5
var max_hearts := 5  # nombre de cœurs affichés
# vrai après le premier spawn : l'export MAX_HEARTS du player n'est que la
# valeur de DÉPART, ensuite l'autoload fait foi (cœurs ramassés compris)
var hearts_initialized := false
# Registre des cœurs déjà ramassés (clé = scène niveau + position) : un
# pickup présent ici se détruit à son chargement — sinon il renaîtrait à
# chaque respawn (cœurs infinis). Vit le temps de la session ; à brancher
# sur la vraie sauvegarde disque quand elle existera.
var coeurs_ramasses := {}
var sang := 0  # la jauge de sang commence vide (se remplit via les récoltes)
var MAX_SANG := 195

## Réinitialise TOUT l'état de partie — appelé par PLAY au menu principal.
## Nouvelle partie = page blanche : cœurs ramassés compris.
func reset_partie() -> void:
	hearts_initialized = false  # le prochain spawn relira l'export du player
	coeurs_ramasses.clear()
	hp = 999999  # clampé au max par le _enter_tree du player
	blood = 0
	sang = 0
	MAX_SANG = 195
	has_checkpoint = false
	last_checkpoint_scene = ""
	last_checkpoint_pos = Vector2.ZERO
	last_door_id = -1
	has_transition_momentum = false


func changement_de_vie(amount: int) -> void:
	var old := hp
	hp = clamp(hp + amount, 0, MAX_HP)
	var delta := hp - old
	var bars := get_tree().get_nodes_in_group("UI_Health")
	if !bars.is_empty():
		bars[0].emit_signal("health_request", float(delta))

func changement_de_sang(amount: int) -> void:
	var old := sang
	sang = clamp(sang + amount, 0, MAX_SANG)
	var delta := sang - old
	var bars := get_tree().get_nodes_in_group("UI_Sang")
	if !bars.is_empty():
		bars[0].emit_signal("sang_request", float(delta))

func changement_de_blood(amount: int) -> void:
	if amount == 0:
		return
	var old := blood
	blood = max(0, old + amount)   # clamp à 0 (pas de max)
	var delta := blood - old
	if delta == 0:
		return
	for n in get_tree().get_nodes_in_group("UI_Blood"):
		n.emit_signal("souls_request", delta)

# ---------- MAX HP / EN ----------


# --- MAX HP ---
func set_max_hp(new_max: int) -> void:
	new_max = max(1, new_max)
	if new_max == MAX_HP:
		return
	var old_hp := hp
	MAX_HP = new_max
	max_hearts = MAX_HP  # la rangée de cœurs affichée suit toujours le max
	# Ne PAS rééchelonner : on garde la valeur et on clamp si besoin
	hp = min(old_hp, MAX_HP)

	var ui := get_tree().get_nodes_in_group("UI_Health")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "hp", float(MAX_HP))  # pas de health_request

func add_max_hp(delta: int) -> void:
	set_max_hp(MAX_HP + delta)  # <-- aucune mise à l’échelle

# --- MAX SANG ---
func set_max_sang(new_max: int) -> void:
	new_max = max(1, new_max)
	if new_max == MAX_SANG:
		return
	var old_sang := sang
	MAX_SANG = new_max
	sang = min(old_sang, MAX_SANG)

	var ui := get_tree().get_nodes_in_group("UI_Sang")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "sang", float(MAX_SANG))

func add_max_sang(delta: int) -> void:
	set_max_sang(MAX_SANG + delta)


#Player.add_max_sang(50)        # +50 de capacité de jauge de sang (la barre s'allonge)
