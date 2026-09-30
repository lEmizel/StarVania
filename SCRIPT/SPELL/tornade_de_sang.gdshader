shader_type canvas_item;

// TORNADE DE SANG — le projectile de la boule de sang quand le talisman
// « Tornade de sang » est équipé (30 sept. 2026).
// C'est la boule de sang COMME AVANT (même boule, mêmes couleurs, même feu
// rongé par le bruit : voir bloodball.gdshader) dont la traînée, au lieu de
// filer droit, S'ENROULE EN SPIRALE derrière elle : serrée contre la boule,
// elle s'ouvre en s'éloignant et finit en volutes fines.
// Tout est compté en PIXELS autour de la boule (x vers l'avant, y vers le bas) :
// tornade_de_sang.gd fournit `taille`, `origine`, `temps` et `parcouru`.

// --- fournis par tornade_de_sang.gd -----------------------------------------
// secondes écoulées depuis le lancer, et distance déjà parcourue (px) : la
// spirale ne peut pas être plus longue que le chemin fait
uniform float temps = 1.0;
uniform float parcouru = 400.0;
// 0 en vol ; de 0 à 1 après l'impact : la boule s'efface sous l'explosion et la
// spirale est avalée par le point d'impact
uniform float dissipation : hint_range(0.0, 1.0) = 0.0;
// taille du rectangle, et place de la boule dedans (px)
uniform vec2 taille = vec2(330.0, 130.0);
uniform vec2 origine = vec2(280.0, 65.0);
// ----------------------------------------------------------------------------

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform vec4 blood_color : source_color = vec4(0.85, 0.08, 0.08, 1.0);
uniform vec4 outer_color : source_color = vec4(0.35, 0.0, 0.06, 1.0);
// --- la boule ---
// rayon de la boule (px) — 18 = celui de la boule de sang
uniform float rayon_boule : hint_range(6.0, 40.0) = 18.0;
// la flamme droite qui file derrière la boule, comme avant (0 = aucune)
uniform float trainee : hint_range(0.0, 2.0) = 0.6;
// --- la spirale ---
// longueur de la queue (px), et nombre de tours qu'elle fait dessus
uniform float longueur : hint_range(60.0, 400.0) = 250.0;
uniform float spires : hint_range(1.0, 8.0) = 3.0;
// écart maximal à l'axe (px) : la spirale s'ouvre jusque-là
uniform float ampleur : hint_range(0.0, 80.0) = 40.0;
// demi-épaisseur des brins (px)
uniform float epaisseur : hint_range(2.0, 24.0) = 12.0;
// nombre de brins enroulés ensemble
uniform int nb_brins : hint_range(1, 3) = 2;
// tours par seconde
uniform float vitesse_rotation : hint_range(0.0, 10.0) = 3.5;
// éclat de la spirale (1 = le devant des brins est aussi clair que la boule)
uniform float force_spirale : hint_range(0.0, 1.5) = 1.0;

// (PI et TAU sont fournis par le langage de shader de Godot)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * taille - origine;
	float s = -p.x;                            // px derrière la boule

	// Bruit animé qui défile vers l'arrière (le même que la boule de sang)
	float n = noise(vec2(p.x / 24.0 + temps * 6.0, p.y / 10.7)) * 0.5
			+ noise(vec2(p.x / 12.0 + temps * 10.0, p.y / 5.3 + temps * 2.0)) * 0.25;

	// la queue s'allonge avec le chemin parcouru, et ne sort jamais du rectangle ;
	// à l'impact, son bout rattrape la boule : elle est avalée
	float queue = clamp(parcouru + 10.0, 10.0, min(longueur, origine.x - 8.0));
	queue = max(queue * (1.0 - dissipation), 1.0);
	float vivant = 1.0 - smoothstep(0.0, 0.3, dissipation);     // la boule, elle, s'efface tout de suite
	float derriere = step(0.0, s) * step(s, queue);
	float fin = 1.0 - smoothstep(0.6, 1.0, s / queue);      // elle s'affine au bout

	// --- la flamme droite, comme avant ---
	float flamme = smoothstep(27.0, 0.0, abs(p.y))
			* smoothstep(min(150.0, queue), -13.0, s)
			* step(0.0, s) * n * trainee * vivant;

	// --- la SPIRALE : des brins enroulés autour de l'axe du vol ---
	// serrée contre la boule, elle s'ouvre en s'éloignant
	float ouverture = smoothstep(0.0, 0.55 * longueur, s);
	float amp = min(ampleur, 0.5 * taille.y - epaisseur * 1.5 - 4.0) * ouverture;
	float k = TAU * spires / longueur;
	float spirale = 0.0;
	for (int j = 0; j < 3; j++) {
		if (j >= nb_brins) {
			break;
		}
		float phi = k * s - TAU * vitesse_rotation * temps - 5.0 * dissipation
				+ TAU * float(j) / float(nb_brins);
		float devant = cos(phi);               // +1 : le brin passe devant, -1 : derrière
		float pente = amp * k * cos(phi);
		float dist = abs(p.y - amp * sin(phi)) / sqrt(1.0 + pente * pente);
		// devant, le brin est épais et brûlant ; derrière, plus fin et sombre
		// (c'est ce qui fait lire une spirale, et pas une vague)
		float demi = epaisseur * (0.72 + 0.28 * devant) * fin;
		// (un brin devenu plus fin que 3 px s'éteint : pas de fil d'un pixel au bout)
		float brin = smoothstep(demi, demi * 0.25, dist + n * demi * 0.45)
				* (0.68 + 0.32 * devant) * smoothstep(1.0, 3.5, demi);
		spirale = max(spirale, brin);
	}
	spirale *= derriere * force_spirale;

	// --- la boule : cœur dense + halo, bord rongé par le bruit (comme avant) ---
	// elle grossit depuis la main sur les premières images
	float r = rayon_boule * mix(0.45, 1.0, smoothstep(0.0, 0.06, temps));
	float d = length(p);
	float ball = smoothstep(r, r * 0.3, d + n * r * 0.56) * vivant;
	float halo = smoothstep(r * 2.0, r * 0.5, d) * 0.5 * vivant;

	float intensity = max(ball * 1.25, max(max(flamme, halo), spirale));

	// Palette : sombre -> rouge sang -> cœur clair
	vec3 col = mix(outer_color.rgb, blood_color.rgb, smoothstep(0.12, 0.55, intensity));
	col = mix(col, core_color.rgb, smoothstep(0.78, 1.05, intensity));

	float alpha = smoothstep(0.10, 0.32, intensity);
	COLOR = vec4(col, alpha);
}
