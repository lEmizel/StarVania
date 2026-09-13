extends Node
## ============================================================================
## POOL D'EFFETS — instances fabriquées UNE FOIS au boot et recyclées.
##
## POURQUOI : créer un système de particules en jeu (GPU ou CPU) coûte 100 à
## 250 ms sur Metal / Mac — allocations GPU du pilote — mesuré le 13 sept.
## 2026 par A/B (sans particules : zéro freeze). On paie donc ce coût au
## démarrage, caché derrière le menu, et on ne crée plus jamais en partie.
##
## Les instances vivent ici, sous l'autoload : elles survivent aux changements
## de niveau (une récolte en vol continue vers le joueur, qui persiste aussi).
## ============================================================================

const SANG_SCENE := preload("res://SCRIPT/PARTICLE/BLOOD_PARTICLE.tscn")
const SANG_INITIAL := 6                 # récoltes simultanées prévues (kills rapprochés)
const HORS_ECRAN := Vector2(-100000.0, -100000.0)

var _sang_libres: Array[Node2D] = []


func _ready() -> void:
	for i in SANG_INITIAL:
		_sang_libres.append(_fabriquer_sang())
	# chauffe : chaque instance émet une fois hors écran → tampons GPU et
	# chemin de mise à jour déjà exercés avant la première mort
	for s in _sang_libres:
		s.visible = true
		s.global_position = HORS_ECRAN
		s.get_node("Particules").restart()
	for i in 10:
		await get_tree().process_frame
	for s in _sang_libres:
		_endormir(s)
	print("[POOL] %d récoltes de sang prêtes" % _sang_libres.size())


func _fabriquer_sang() -> Node2D:
	var s: Node2D = SANG_SCENE.instantiate()
	add_child(s)
	_endormir(s)
	return s


func _endormir(s: Node2D) -> void:
	s.get_node("Particules").dormir()
	s.visible = false
	s.global_position = HORS_ECRAN


## Une récolte de sang prête, posée à `position_globale`. Ne coûte rien.
func sang(position_globale: Vector2) -> Node2D:
	var s: Node2D
	if _sang_libres.is_empty():
		# rare : plus d'instance libre → on en crée une (avec le coût, une fois)
		s = _fabriquer_sang()
		print("[POOL] sang : pool épuisé, instance supplémentaire créée")
	else:
		s = _sang_libres.pop_back()
	s.visible = true
	s.global_position = position_globale
	s.get_node("Particules").relancer()
	return s


## Appelé par la récolte quand elle a fini : retour au pool.
func rendre_sang(s: Node2D) -> void:
	if s == null or _sang_libres.has(s):
		return
	_endormir(s)
	_sang_libres.append(s)
