shader_type canvas_item;

// Le matériau des monstres dessinés (posé par BASE_IA sur leur animator) : leur
// image, avec leurs états par-dessus — éclair de coup, teinte, fissures,
// cristal. Les réglages et le calcul sont dans etats_monstre.gdshaderinc,
// partagé avec le slime.
#include "res://SCRIPT/MONSTER/etats_monstre.gdshaderinc"

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(etats_monstre(tex, local), tex.a);
}
