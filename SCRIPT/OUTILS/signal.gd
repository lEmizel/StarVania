extends RefCounted

class_name SignalUtils

static func connect_signal(emitter, signal_name, target, method_name):
	var callable = Callable(target, method_name)
	if not emitter.is_connected(signal_name, callable):
		emitter.connect(signal_name, callable)
		
		
		
		# Exemple d'utilisation dans un autre script
#SignalUtils.connect_signal(button, "pressed", self, "on_button_pressed")
