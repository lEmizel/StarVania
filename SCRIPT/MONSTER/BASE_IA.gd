extends CharacterBody2D
class_name BaseAI


@onready var vie: Node2D = $bare_de_vie
@onready var collision = $Collision #collisionshape2d qui sert de hitbox
@onready var point = $POINT #node2d qui sert flip l'entité
@onready var animator =  $POINT/animator # principal animator du personnage pour les mouvements. hors effet speciaux
@onready var vision = $POINT/vision

var approach_initial_position: bool = false
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state = States.IDLE
var previous_state = States.IDLE
var state_functions = {}
var stimuli = false
var target = null
var initial_position :  Vector2
var position_x_player = null
var garde = false


var speed: float = 0.0
var health: int = 0
var attack_power: int = 0
var confort_zone_max: int = 0
var confort_zone_min: int = 0
var max_tracking_distance: int = 0
var vol = false


# États et machine à états
enum States { IDLE, WALK, APPROACH, RETREAT, ATTACK, HIT, DEAD }


func _ready() -> void:
	initialize_states()
	change_state(States.IDLE)

func initialize_states() -> void:
	state_functions[States.IDLE]    = { "enter": idle_enter,    "execute": walk_execute }
	state_functions[States.WALK]  = { "enter": walk_enter,  "execute": walk_execute }
	# … etc. pour chaque état

func change_state(new_state):
	if current_state == new_state: return
	if state_functions[current_state].has("exit"):
		state_functions[current_state]["exit"].call()
	current_state = new_state
	if state_functions[current_state].has("enter"):
		state_functions[current_state]["enter"].call()

func _physics_process(delta):
	if state_functions[current_state].has("execute"):
		state_functions[current_state]["execute"].call(delta)
		
		

func idle_enter():   pass
func idle_execute(delta):   pass

func walk_enter():   pass
func walk_execute(delta):   pass
