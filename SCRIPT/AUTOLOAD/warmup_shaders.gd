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
	"res://SCRIPT/SHADER/jet_flamme.gdshader",         # jet_flamme.tscn (prototype, sept. 2026)
	"res://SCRIPT/SHADER/boule_de_feu.gdshader",       # boule_de_feu.tscn (projectile, sept. 2026)
	"res://SCRIPT/SPELL/explosion_feu.gdshader",      # l'impact de la boule de feu (1er oct. 2026)
	"res://SCRIPT/SHADER/sillage_sang.gdshader",      # la brume du talisman sillage de sang (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_sillage.gdshader",  # son dessin dans le menu START
	"res://SCRIPT/SHADER/epines_sang.gdshader",       # les pics du talisman épines de sang (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_epines.gdshader",   # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_frenesie.gdshader", # le dessin du talisman frénésie dans le menu START (1er oct. 2026)
	"res://SCRIPT/SHADER/marque_sang.gdshader",       # la rune du talisman marque de sang (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_marque.gdshader",   # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_souffle.gdshader",  # talisman second souffle (menu START)
	"res://SCRIPT/TALISMAN/dessin_canon.gdshader",    # talisman canon de verre (menu START)
	"res://SCRIPT/SHADER/couronne_vengeance.gdshader", # la couronne du talisman vengeance (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_vengeance.gdshader", # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_allonge.gdshader",  # talisman allonge (menu START)
	"res://SCRIPT/SHADER/croissant_sang.gdshader",    # le projectile du talisman croissant de sang (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_croissant.gdshader", # son dessin dans le menu START
	"res://SCRIPT/SHADER/chauve_souris_sang.gdshader", # les chauves-souris du talisman essaim (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_essaim.gdshader",   # son dessin dans le menu START
	"res://SCRIPT/SHADER/sceau_sang.gdshader",        # le sceau du talisman offrande (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_offrande.gdshader", # son dessin dans le menu START
	"res://SCRIPT/SHADER/bouillon_sang.gdshader",     # les bulles du talisman sang bouillant (1er oct. 2026)
	"res://SCRIPT/SHADER/explosion_sang.gdshader",    # son explosion
	"res://SCRIPT/TALISMAN/dessin_bouillant.gdshader", # son dessin dans le menu START
	"res://SCRIPT/SHADER/ombre_sang.gdshader",        # la teinte du double du talisman ombre de sang (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_ombre.gdshader",    # son dessin dans le menu START
	"res://SCRIPT/SHADER/poison_sang.gdshader",       # les volutes du talisman sang corrompu (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_corrompu.gdshader", # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_dos.gdshader",      # talisman coup dans le dos (menu START, 1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_crescendo.gdshader", # talisman crescendo (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/parade_choc.gdshader",       # le choc du talisman parade (1er oct. 2026)
	"res://SCRIPT/SHADER/etourdi.gdshader",           # les étoiles d'un monstre sonné (parade)
	"res://SCRIPT/TALISMAN/dessin_parade.gdshader",   # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_lame_corrompue.gdshader", # talisman lame corrompue (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/grace_eclats.gdshader",      # les éclats du talisman coup de grâce (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_grace.gdshader",    # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_prise.gdshader",    # talisman prise ferme (menu START, 1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_venin.gdshader",    # talisman venin (menu START, 1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_cristal.gdshader",  # talisman sang cristallisé (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/plume_aceree.gdshader",      # la plume-lame du talisman plumes acérées (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_plumes.gdshader",   # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_sang_plein.gdshader", # talisman sang plein (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/oeil_canon.gdshader",        # l'œil de feu du canon de verre (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_sang_verse.gdshader", # talisman sang versé (menu START, 1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_reliquaire.gdshader", # talisman reliquaire (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/gardiennes_sang.gdshader",   # les gouttes du talisman gardiennes (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_gardiennes.gdshader", # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_soin_eclair.gdshader", # talisman soin éclair (menu START, 1er oct. 2026)
	"res://SCRIPT/SHADER/esprit_sang.gdshader",      # l'esprit de sang : les âmes perdues à la mort (1er oct. 2026)
	"res://SCRIPT/SHADER/entrave_sang.gdshader",     # l'anneau du talisman entraves (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_entraves.gdshader", # son dessin dans le menu START
	"res://SCRIPT/SHADER/coeur_noir_onde.gdshader",  # l'onde du talisman cœur noir (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_coeur_noir.gdshader", # son dessin dans le menu START
	"res://SCRIPT/SHADER/couronne_defi.gdshader",    # la couronne d'or du talisman couronne du défi (1er oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_defi.gdshader",    # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_chercheuse.gdshader", # talisman boule chercheuse (menu START, 2 oct. 2026)
	"res://SCRIPT/SHADER/trop_plein_jauge.gdshader", # la roue (façon endurance de Zelda) du talisman trop-plein (2 oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_trop_plein.gdshader", # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_sang_neuf.gdshader", # talisman sang neuf (menu START, 2 oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_inebranlable.gdshader", # talisman inébranlable (menu START, 2 oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_sixieme.gdshader", # talisman sixième coup (menu START, 2 oct. 2026)
	"res://SCRIPT/TALISMAN/dessin_pacte.gdshader",  # talisman pacte de sang (menu START, 2 oct. 2026)
	"res://SCRIPT/SHADER/explosion_violette.gdshader", # explosion du kamikaze (sept. 2026)
	"res://SCRIPT/SHADER/cable_de_sang.gdshader",    # câble du grappin (sept. 2026)
	"res://SCRIPT/SHADER/pince_grappin.gdshader",    # la pince du point d'accroche du grappin (2 oct. 2026)
	"res://SCRIPT/SHADER/sceau_runes.gdshader",      # le piège sceau de runes (2 oct. 2026)
	"res://SCRIPT/SHADER/pilier_foudre.gdshader",    # le piège pilier de foudre (2 oct. 2026)
	"res://SCRIPT/SHADER/foudre_ciel.gdshader",      # l'éclair qu'il appelle du ciel, averti au sol
	"res://SCRIPT/SHADER/trou_noir.gdshader",        # piège trou noir : il aspire, lentille sur le décor
	"res://SCRIPT/SHADER/vent.gdshader",             # piège de vent : filets et anneaux d'air
	"res://SCRIPT/SHADER/faille_etoilee.gdshader",   # pluie d'étoiles : la faille dans le ciel
	"res://SCRIPT/SHADER/comete.gdshader",           # pluie d'étoiles : une comète avertie et son impact
	"res://SCRIPT/SHADER/pilon.gdshader",            # le pilon : le concasseur (décor, sans contour)
	"res://SCRIPT/SHADER/roue_pointes.gdshader",     # roue à pointes : la roue seule, ses étincelles, son éclatement
	"res://SCRIPT/SHADER/barre_feu_socle.gdshader",  # barre de feu : le bloc de pierre au centre (décor, sans contour)
	"res://SCRIPT/SHADER/lanceur_feu.gdshader",      # lanceur de boules de feu : le canon (décor, sans contour)
	"res://SCRIPT/SHADER/impact_blanc.gdshader",     # éclat d'un coup d'épée qui porte (sept. 2026)
	"res://SCRIPT/SHADER/souffle_dash.gdshader",     # souffle d'air au départ du dash (sept. 2026)
	"res://SCRIPT/SHADER/onde_de_choc.gdshader",     # onde de choc du coup de pied du boss (sept. 2026)
	"res://SCRIPT/SHADER/impulsion_saut.gdshader",   # impulsion d'air au départ du saut simple (sept. 2026)
	"res://SCRIPT/SHADER/trace_de_griffe.gdshader",  # sillons et étincelles de la griffe en wall run (sept. 2026)
	"res://SCRIPT/SHADER/aile_double_saut.gdshader", # aile rouge sang du double saut (sept. 2026)
	"res://SCRIPT/SHADER/plumes_envolees.gdshader",  # souffle et plumes que le coup d'aile laisse sur place
	"res://SCRIPT/SHADER/plume_planee.gdshader",     # plume que l'aile de plané perd en route (1er oct. 2026)
	"res://SCRIPT/SHADER/griffure_xeno.gdshader",    # coups de griffes du xeno (sept. 2026)
	"res://SCRIPT/SHADER/slash_heros.gdshader",      # le slash des attaques du héros, refait d'après ses dessins (sept. 2026)
	"res://SCRIPT/SHADER/arc_foudre.gdshader",       # l'éclair qui bondit d'un ennemi à l'autre (talisman lame de foudre, sept. 2026)
	"res://SCRIPT/TALISMAN/dessin_foudre.gdshader",  # le médaillon du talisman lame de foudre (menu START)
	"res://SCRIPT/SHADER/bouclier_sang.gdshader",    # la bulle du talisman bouclier de sang (sept. 2026)
	"res://SCRIPT/TALISMAN/dessin_bouclier.gdshader", # son dessin dans le menu START
	"res://SCRIPT/TALISMAN/dessin_esquive.gdshader",  # talisman pas de côté (menu START)
	"res://SCRIPT/TALISMAN/dessin_soif.gdshader",     # talisman soif de sang (menu START)
	"res://SCRIPT/SHADER/flou_fond.gdshader",          # flou de fond (scene_06, scene_7)
	"res://SCRIPT/SCENE/ss.gdshader",                  # cadre mur griffe, grotte
	"res://SCRIPT/SCENE/scene_3.gdshader",             # décor de scene_3
	"res://SCRIPT/MONSTER/hit_flash.gdshader",         # flash de coup (BASE_IA)
	"res://SCRIPT/SPELL/bloodball.gdshader",
	"res://SCRIPT/SPELL/bloodball_explosion.gdshader",
	"res://SCRIPT/SPELL/tornade_de_sang.gdshader",   # la boule de sang du talisman « Tornade de sang » (sept. 2026)
	"res://SCRIPT/TALISMAN/dessin_tornade_de_sang.gdshader",  # le dessin de ce talisman dans le menu START
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
