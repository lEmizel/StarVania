@tool
extends ColorRect
## ============================================================================
## TORNADE DE SANG — le VISUEL du projectile (le vol, les dégâts et le recul
## sont dans bloodball.gd, sur la racine de tornade_de_sang.tscn). Ce script
## fait tourner le `temps` du shader, lui dit le chemin déjà parcouru (la
## spirale s'allonge derrière la boule au fil du vol) et la taille du rectangle.
##
## À L'IMPACT, bloodball.gd appelle `dissiper()` : la boule s'efface sous
## l'explosion, la spirale est avalée par le point d'impact en `duree_dissipation`
## secondes, puis ce script supprime le projectile.
##
## POUR LA JUGER : ouvrir tornade_de_sang.tscn, elle tourne toute seule dans
## l'éditeur, queue entièrement déroulée (décocher `animer_dans_l_editeur` pour
## la figer). Les formes et les couleurs se règlent sur le matériau. Le
## rectangle n'est que la ZONE DE DESSIN : la boule est à l'origine du nœud
## parent, la spirale ne sort jamais du rectangle (elle se limite à lui).
## ============================================================================

## dans l'éditeur : la spirale tourne pendant qu'on règle le matériau
@export var animer_dans_l_editeur := true
## temps que met la spirale à être avalée par l'impact (s)
@export var duree_dissipation := 0.14

var _t := 0.0
var _parcouru := 10000.0       # dans l'éditeur : la queue entière
var _dissipation := -1.0       # < 0 : en vol ; sinon secondes écoulées depuis l'impact


func _ready() -> void:
	_appliquer()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not animer_dans_l_editeur:
		return
	_t += delta
	if _dissipation >= 0.0:
		_dissipation += delta
		if _dissipation >= duree_dissipation:
			get_parent().queue_free()
			return
	elif not Engine.is_editor_hint():
		# chemin parcouru : le vol est à vitesse constante (bloodball.gd)
		var projectile := get_parent()
		if projectile != null and "speed" in projectile:
			_parcouru = float(projectile.speed) * _t
	_appliquer()


## Le projectile vient d'exploser : la queue ne s'allonge plus, elle se fait
## avaler par le point d'impact, puis le projectile est supprimé.
func dissiper() -> void:
	if _dissipation < 0.0:
		_dissipation = 0.0
		_appliquer()


func _appliquer() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("parcouru", _parcouru)
	mat.set_shader_parameter("dissipation",
		clampf(_dissipation / maxf(duree_dissipation, 0.001), 0.0, 1.0))
	# le repère du shader : des pixels, avec la boule (le nœud parent) à l'origine
	mat.set_shader_parameter("taille", size)
	mat.set_shader_parameter("origine", -position)
