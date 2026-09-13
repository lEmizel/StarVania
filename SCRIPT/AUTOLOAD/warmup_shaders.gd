extends Node
## ============================================================================
## WARMUP — pré-chauffe des shaders et des pipelines de rendu 2D.
##
## POURQUOI : Godot compile un shader quand la ressource se charge, puis crée
## le "pipeline" GPU à la PREMIÈRE frame où un objet l'utilise — une fois hors
## lumière, une fois sous une Light2D. Chaque création bloque le rendu de 10 à
## 300 ms selon le shader et le pilote (Metal sur Mac est le plus lent) :
## freeze en pleine partie à la première flamme, au premier coup, à la
## première lumière… Godot met ensuite tout en cache sur disque : c'est pour ça
## que ça ne freeze QUE sur un PC qui lance le jeu pour la première fois.
##
## COMMENT : chaque matériau est dessiné sur un sprite d'un pixel, deux fois
## (hors lumière + sous une PointLight2D), chaque type de particule GPU émet
## une fois, pendant quelques frames dans une couche invisible, puis tout est
## jeté. Trois moments :
##   • au boot (derrière le menu) : shaders fichiers + scènes d'effets légères,
##     lues via SceneState sans les instancier ;
##   • au spawn du joueur : `chauffer_arbre(joueur)` (ses matériaux internes,
##     ex. le slash d'attaque, sinon 140 ms au premier coup sur Mac) ;
##   • à la pose d'un niveau : `chauffer_arbre(niveau)` (matériaux en dur).
##
## À MAINTENIR : tout nouveau .gdshader ou nouvelle scène d'effet → l'ajouter
## aux listes ci-dessous. JAMAIS de scène de niveau ni le PLAYER dans les
## listes du boot (des centaines de textures = secondes de chargement).
## ============================================================================

## shaders fichiers → matériau neuf. Les uniformes par défaut suffisent : le
## pipeline dépend du code du shader, pas des valeurs.
const SHADERS: Array[String] = [
	"res://SCRIPT/SHADER/flamme_cartoon.gdshader",     # flamme.tscn
	"res://SCRIPT/SHADER/flou_fond.gdshader",          # flou de fond (scene_06, scene_7)
	"res://SCRIPT/SCENE/ss.gdshader",                  # cadre mur griffe, grotte
	"res://SCRIPT/SCENE/scene_3.gdshader",             # décor de scene_3
	"res://SCRIPT/MONSTER/hit_flash.gdshader",         # flash de coup (BASE_IA)
	"res://SCRIPT/SPELL/bloodball.gdshader",
	"res://SCRIPT/SPELL/bloodball_explosion.gdshader",
]
## scènes d'effets LÉGÈRES : matériaux et particules lus dans la scène SANS
## l'instancier (aucun script ne tourne). Couvre aussi les shaders écrits en
## dur dans la scène (ex. l'hologramme du cœur).
const SCENES_FX: Array[String] = [
	"res://SCRIPT/INTERACTIBLE/coeur.tscn",
	"res://SCRIPT/INTERACTIBLE/flamme.tscn",
	"res://SCRIPT/INTERACTIBLE/cadre_mur_griffe.tscn",
	"res://SCRIPT/SPELL/bloodball.tscn",
	"res://SCRIPT/SPELL/bloodball_explosion.tscn",
	"res://SCRIPT/PARTICLE/BLOOD_PARTICLE.tscn",
]
const LIGHT_TEXTURE := "res://MEDIA/UTILITAIRE/light.png"
const ZOO_LAYER := -100          # couche canvas derrière tout (menu = 0)
const FRAMES_DE_CHAUFFE := 6     # frames rendues avant le nettoyage
const POS_HORS_LUMIERE := Vector2(20.0, 20.0)
const POS_SOUS_LUMIERE := Vector2(240.0, 240.0)

# garde les ressources en cache pour toute la partie : pas de rechargement ni
# de recompilation quand une scène les redemande
var _refs: Array[Resource] = []
var _tex_pixel: ImageTexture
var _deja: Dictionary = {}       # clé (shader ou matériau) → true : déjà chauffé


func _ready() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_tex_pixel = ImageTexture.create_from_image(img)

	var materiaux: Array[Material] = [null]      # null = matériau par défaut (décors, sprites, HUD)
	var particules: Array[Dictionary] = []

	for path in SHADERS:
		var sh := load(path) as Shader
		if sh == null:
			push_warning("[WARMUP] shader introuvable : " + path)
			continue
		_refs.append(sh)
		var m := ShaderMaterial.new()
		m.shader = sh
		materiaux.append(m)

	for path in SCENES_FX:
		var ps := load(path) as PackedScene
		if ps == null:
			push_warning("[WARMUP] scène introuvable : " + path)
			continue
		_refs.append(ps)
		_collecter_scene(ps, materiaux, particules)

	_chauffer(materiaux, particules, "boot")


## API : chauffe les matériaux et particules d'un arbre VIVANT (joueur au spawn,
## niveau qui vient d'être posé), nœuds cachés compris. Ne refait jamais un
## shader déjà chauffé.
func chauffer_arbre(racine: Node, etiquette := "") -> void:
	if racine == null:
		return
	var materiaux: Array[Material] = []
	var particules: Array[Dictionary] = []
	_collecter_vivant(racine, materiaux, particules)
	if materiaux.is_empty() and particules.is_empty():
		return
	_chauffer(materiaux, particules, etiquette if etiquette != "" else str(racine.name))


func _chauffer(materiaux: Array[Material], particules: Array[Dictionary], etiquette: String) -> void:
	var t0 := Time.get_ticks_msec()
	var zoo := CanvasLayer.new()
	zoo.layer = ZOO_LAYER
	add_child(zoo)

	# un sprite d'un pixel par matériau, hors lumière et sous la lumière
	for m in materiaux:
		if m != null:
			_deja[_cle(m)] = true
		for pos in [POS_HORS_LUMIERE, POS_SOUS_LUMIERE]:
			var s := Sprite2D.new()
			s.texture = _tex_pixel
			s.material = m
			s.position = pos
			s.scale = Vector2(0.25, 0.25)
			zoo.add_child(s)

	# la lumière déclenche les variantes "éclairées" des pipelines
	var light := PointLight2D.new()
	light.texture = load(LIGHT_TEXTURE)
	light.position = POS_SOUS_LUMIERE
	light.range_layer_min = ZOO_LAYER
	light.range_layer_max = ZOO_LAYER
	zoo.add_child(light)

	# particules GPU : shader de simulation + rendu instancié, une émission
	for p in particules:
		_deja[p["process_material"]] = true
		var gp := GPUParticles2D.new()
		gp.process_material = p["process_material"]
		gp.texture = p["texture"]
		gp.amount = 8
		gp.lifetime = 0.2
		gp.emitting = true
		gp.position = POS_HORS_LUMIERE
		zoo.add_child(gp)

	# particules CPU (sang, traînée du cœur) : pipeline instancié du canvas
	var cp := CPUParticles2D.new()
	cp.texture = _tex_pixel
	cp.amount = 4
	cp.lifetime = 0.2
	cp.emitting = true
	cp.position = POS_HORS_LUMIERE
	zoo.add_child(cp)

	for i in FRAMES_DE_CHAUFFE:
		await get_tree().process_frame
	zoo.queue_free()
	print("[WARMUP] %s : %d matériaux et %d particules chauffés en %d ms"
		% [etiquette, materiaux.size(), particules.size(), Time.get_ticks_msec() - t0])


## clé de déduplication : le pipeline dépend du SHADER, pas des valeurs d'uniformes
func _cle(m: Material) -> Variant:
	if m is ShaderMaterial and m.shader != null:
		return m.shader
	return m


## lit les matériaux et les particules d'une scène via son SceneState,
## sans l'instancier
func _collecter_scene(ps: PackedScene, materiaux: Array[Material], particules: Array[Dictionary]) -> void:
	var st := ps.get_state()
	for i in st.get_node_count():
		var est_particule := st.get_node_type(i) == &"GPUParticles2D"
		var props := {}
		for j in st.get_node_property_count(i):
			var nom := String(st.get_node_property_name(i, j))
			var val = st.get_node_property_value(i, j)
			if nom == "material" and val is Material and not materiaux.has(val):
				materiaux.append(val)
			elif est_particule and (nom == "process_material" or nom == "texture"):
				props[nom] = val
		if est_particule and props.has("process_material"):
			particules.append({
				"process_material": props["process_material"],
				"texture": props.get("texture"),
			})


## parcourt un arbre de nœuds vivants (cachés compris)
func _collecter_vivant(n: Node, materiaux: Array[Material], particules: Array[Dictionary]) -> void:
	if n is CanvasItem and n.material != null:
		var m: Material = n.material
		if not _deja.has(_cle(m)) and not materiaux.has(m):
			materiaux.append(m)
	if n is GPUParticles2D and n.process_material != null and not _deja.has(n.process_material):
		particules.append({"process_material": n.process_material, "texture": n.texture})
	for c in n.get_children():
		_collecter_vivant(c, materiaux, particules)
