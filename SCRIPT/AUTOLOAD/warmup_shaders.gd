extends Node
## ============================================================================
## WARMUP — pré-chauffe des shaders et des pipelines de rendu 2D au démarrage.
##
## POURQUOI : Godot compile un shader quand la ressource se charge, puis crée
## le "pipeline" GPU à la PREMIÈRE frame où un objet l'utilise — une fois hors
## lumière, une fois sous une Light2D. Chaque création bloque le rendu de 10 à
## 300 ms selon le shader et le pilote : freeze en pleine partie à la première
## flamme, au premier flash de coup, à la première bloodball, à la première
## lumière… Godot met ensuite tout en cache sur disque (user://shader_cache +
## cache de pipelines) : c'est pour ça que ça ne freeze QUE sur un PC qui
## lance le jeu pour la première fois, jamais sur la machine de dev.
##
## COMMENT : au boot, derrière le menu, chaque matériau est dessiné sur un
## sprite d'un pixel, deux fois (hors lumière + sous une PointLight2D), chaque
## type de particule GPU émet une fois, le tout pendant quelques frames, puis
## tout est jeté. Coût : un premier lancement un peu plus long sur un PC neuf.
##
## À MAINTENIR : tout nouveau .gdshader ou nouvelle scène d'effet → l'ajouter
## aux listes ci-dessous. JAMAIS de scène de niveau ni le PLAYER ici (des
## centaines de textures = secondes de chargement au boot) : leurs shaders
## internes se compilent pendant l'écran de chargement et leur première
## apparition coïncide avec l'arrivée dans le niveau (freeze masqué).
## ============================================================================

## shaders fichiers → matériau neuf. Les uniformes par défaut suffisent : le
## pipeline dépend du code du shader, pas des valeurs.
const SHADERS: Array[String] = [
	"res://SCRIPT/SHADER/flamme_cartoon.gdshader",     # flamme.tscn
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
var _zoo: CanvasLayer


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
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
		_collecter(ps, materiaux, particules)

	_zoo = CanvasLayer.new()
	_zoo.layer = ZOO_LAYER
	add_child(_zoo)

	# un sprite d'un pixel par matériau, hors lumière et sous la lumière
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	for m in materiaux:
		for pos in [POS_HORS_LUMIERE, POS_SOUS_LUMIERE]:
			var s := Sprite2D.new()
			s.texture = tex
			s.material = m
			s.position = pos
			s.scale = Vector2(0.25, 0.25)
			_zoo.add_child(s)

	# la lumière déclenche les variantes "éclairées" des pipelines
	var light := PointLight2D.new()
	light.texture = load(LIGHT_TEXTURE)
	light.position = POS_SOUS_LUMIERE
	light.range_layer_min = ZOO_LAYER
	light.range_layer_max = ZOO_LAYER
	_zoo.add_child(light)

	# particules GPU : shader de simulation + rendu instancié, une émission
	for p in particules:
		var gp := GPUParticles2D.new()
		gp.process_material = p["process_material"]
		gp.texture = p["texture"]
		gp.amount = 8
		gp.lifetime = 0.2
		gp.emitting = true
		gp.position = POS_HORS_LUMIERE
		_zoo.add_child(gp)

	for i in FRAMES_DE_CHAUFFE:
		await get_tree().process_frame
	_zoo.queue_free()
	_zoo = null
	print("[WARMUP] %d matériaux et %d particules chauffés en %d ms"
		% [materiaux.size(), particules.size(), Time.get_ticks_msec() - t0])


## lit les matériaux et les particules d'une scène via son SceneState,
## sans l'instancier
func _collecter(ps: PackedScene, materiaux: Array[Material], particules: Array[Dictionary]) -> void:
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
