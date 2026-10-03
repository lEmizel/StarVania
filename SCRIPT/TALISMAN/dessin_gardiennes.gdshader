shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « GARDIENNES » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit, plus chaud au milieu, cerné
// d'un trait d'encre ; au centre, la SILHOUETTE sombre du héros ; autour de son
// torse, une ronde en perspective où tournent DEUX GOUTTES de sang avec leur
// sillage — celle du fond passe derrière lui, plus petite et plus sombre,
// celle de devant par-dessus. Aplats, encre, un reflet rouge clair (pas de
// blanc). Pointé ou porté (`eveil`), elles tournent plus vite.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.27, 0.05, 0.08, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.74, 0.04, 0.1, 1.0);
uniform vec4 couleur_loin : source_color = vec4(0.4, 0.02, 0.06, 1.0);
uniform vec4 reflet : source_color = vec4(1.0, 0.36, 0.36, 1.0);
uniform vec4 silhouette : source_color = vec4(0.05, 0.012, 0.025, 1.0);

const vec2 CENTRE = vec2(0.0, 0.16);
const vec2 RAYONS = vec2(0.74, 0.2);
const float INCLINAISON = -0.17;

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// une larme le long de +y, tête de rayon r1 en (0,0), bout r2 en (0,h) —
// POSITIVE dedans, comme les autres formes de ce dessin
float larme(vec2 p, float r1, float r2, float h) {
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(1.0 - b * b);
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) {
		return r1 - length(p);
	}
	if (k > a * h) {
		return r2 - length(p - vec2(0.0, h));
	}
	return r1 - dot(p, vec2(a, b));
}

vec2 sur_ronde(float th) {
	vec2 e = vec2(cos(th) * RAYONS.x, sin(th) * RAYONS.y);
	float c = cos(INCLINAISON);
	float s = sin(INCLINAISON);
	return CENTRE + vec2(c * e.x - s * e.y, s * e.x + c * e.y);
}

vec2 tangente(float th) {
	vec2 e = vec2(-sin(th) * RAYONS.x, cos(th) * RAYONS.y);
	float c = cos(INCLINAISON);
	float s = sin(INCLINAISON);
	return normalize(vec2(c * e.x - s * e.y, s * e.x + c * e.y));
}

// une goutte et son sillage, si elle est du côté demandé (devant = 1 : devant)
void goutte(inout vec3 rgb, vec2 p, float th, float devant, float dedans, float px) {
	float z = sin(th);
	// ---- le sillage : sur la ronde, derrière elle ----
	float ci = cos(-INCLINAISON);
	float si = sin(-INCLINAISON);
	vec2 q = p - CENTRE;
	vec2 pe = vec2(ci * q.x - si * q.y, si * q.x + ci * q.y);
	vec2 qe = pe / RAYONS;
	float lq = length(qe);
	float d_ronde = (lq - 1.0) * lq / max(length(pe / (RAYONS * RAYONS)), 1e-5);
	float phi = atan(qe.y, qe.x);
	float z_phi = sin(phi);
	float u = mod(th - phi, 6.2831853) / 1.25;
	if (u < 1.0 && step(0.0, z_phi) == devant) {
		float w = 0.06 * (1.0 + 0.2 * z_phi) * pow(1.0 - u, 0.8);
		float m = smoothstep(-px * 0.5, px * 0.5, w - abs(d_ronde)) * pow(1.0 - u, 1.3) * 0.7;
		rgb = mix(rgb, mix(couleur_loin.rgb, couleur.rgb, smoothstep(-1.0, 0.7, z_phi)), m * step(0.0, dedans));
	}
	// ---- la goutte ----
	if (step(0.0, z) != devant) {
		return;
	}
	float s = 1.0 + 0.22 * z;
	vec2 c = sur_ronde(th);
	vec2 sens = tangente(th);
	vec2 d = p - c;
	vec2 l = vec2(dot(d, vec2(-sens.y, sens.x)), -dot(d, sens));
	float r1 = 0.115 * s;
	float g = min(larme(l, r1, r1 * 0.15, r1 * 2.3), dedans);
	forme(rgb, g, mix(couleur_loin.rgb, couleur.rgb, smoothstep(-1.0, 0.7, z)), trait * 0.8 * s, px);
	// le reflet, sur le haut de la tête
	float rf = min(g - 0.014, 0.036 * s - length(d - vec2(-0.025, -0.04) * s));
	rgb = mix(rgb, mix(couleur.rgb, reflet.rgb, 0.5 + 0.5 * step(0.0, z)), smoothstep(-px * 0.5, px * 0.5, rf));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));
	float dedans = (1.0 - trait * 1.6) - r;

	// les deux gouttes : elles tournent (plus vite éveillées : le temps du rond
	// s'accélère tout seul)
	float th = temps * 1.3 + 0.9;

	// ===================== DERRIÈRE LE HÉROS =====================
	goutte(rgb, p, th, 0.0, dedans, px);
	goutte(rgb, p, th + 3.14159265, 0.0, dedans, px);

	// ===================== LA SILHOUETTE =====================
	float tete = 0.2 - length((p - vec2(0.0, -0.36)) * vec2(1.0, 0.95));
	// trois mèches en pointe sur le crâne (le héros a les cheveux en épis)
	for (int i = 0; i < 3; i++) {
		float fi = float(i) - 1.0;
		vec2 b = vec2(fi * 0.11, -0.5);
		vec2 u = normalize(vec2(fi * 0.55 - 0.25, -1.0));
		float s = dot(p - b, u);
		float v = abs(dot(p - b, vec2(-u.y, u.x)));
		tete = max(tete, min(0.07 * (1.0 - s / 0.17) - v, s + 0.04));
	}
	float epaules = 0.24 + 0.2 * smoothstep(-0.16, 0.25, p.y);
	float torse = min(epaules - abs(p.x), p.y + 0.14);
	float corps = min(max(tete, torse), dedans);
	forme(rgb, corps, silhouette.rgb, trait, px);

	// ===================== DEVANT LE HÉROS =====================
	goutte(rgb, p, th, 1.0, dedans, px);
	goutte(rgb, p, th + 3.14159265, 1.0, dedans, px);

	COLOR = vec4(rgb, a * opacite);
}
