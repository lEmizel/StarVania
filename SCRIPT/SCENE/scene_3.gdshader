shader_type canvas_item;

/* --- Noise vertical (haut/bas) --- */
uniform sampler2D noise_tex;
uniform vec2  noise_scale = vec2(4.0, 6.0);
uniform float seed = 0.0;

/* Animation / warp */
uniform vec2  noise_scroll   = vec2(0.0, 0.0);
uniform float warp_amp       = 0.06;
uniform float warp_scale     = 2.5;
uniform float warp_speed     = 0.6;
uniform vec2  noise_uv_offset = vec2(0.0, 0.0);
uniform float auto_offset_y_speed = 0.15;

/* Forme / dissolve */
uniform float cutoff   = 0.45;
uniform float softness = 0.06;
uniform float top_margin    = 0.28;
uniform float bottom_margin = 0.22;
uniform float edge_strength = 0.75;
uniform float core_hold = 0.15;

/* Fades latéraux (sans noise) */
uniform float left_margin  = 0.12;
uniform float right_margin = 0.12;

/* -------- Couleur de base (HSV) -------- */
uniform float hue = 0.78;
uniform float sat = 0.85;
uniform float val = 1.00;

/* -------- Liseré « papier brûlé » -------- */
uniform float edge_width_px = 1.5;
uniform float edge_mix      = 0.85;
uniform float edge_hue = 0.90;
uniform float edge_sat = 0.95;
uniform float edge_val = 1.20;

/* -------- Lissage optionnel du bruit --------
   0 = net (plus dur), 1 = soft (multi-samples)                       */
uniform float noise_blur = 0.6;   // ajuste 0..1 selon le rendu voulu

/* HSV -> RGB */
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec2 uv = UV;

    // ---------- UV bruit + offsets ----------
    float auto_y = -TIME * auto_offset_y_speed;
    vec2 nuv = vec2(uv.x * noise_scale.x, uv.y * noise_scale.y)
             + noise_uv_offset + vec2(0.0, auto_y)
             + TIME * noise_scroll + vec2(seed);

    // ---------- Domain warp ----------
    vec2 wuv = nuv * warp_scale + vec2(TIME * warp_speed, 0.0);
    float wx = texture(noise_tex, fract(wuv)).r;
    float wy = texture(noise_tex, fract(wuv + vec2(17.0, 37.0))).r;
    vec2 warp = (vec2(wx, wy) - 0.5) * 2.0;
    nuv += warp * warp_amp;

    // Wrap pour éviter les bandes
    nuv = fract(nuv);

    // ---------- Bruit avec adoucissement adaptatif ----------
    // Taille d’un “texel” à l’écran (approx) : fwidth(nuv)
    vec2 texel = fwidth(nuv) * noise_blur;
    // 1 tap net si noise_blur ~ 0
    float n0 = texture(noise_tex, nuv).r;
    // taps voisins (léger box blur si noise_blur > 0)
    float n1 = texture(noise_tex, fract(nuv + vec2(texel.x, 0.0))).r;
    float n2 = texture(noise_tex, fract(nuv + vec2(-texel.x, 0.0))).r;
    float n3 = texture(noise_tex, fract(nuv + vec2(0.0, texel.y))).r;
    float n4 = texture(noise_tex, fract(nuv + vec2(0.0, -texel.y))).r;
    // pondération douce (somme = 1)
    float n  = mix(n0, (n0*0.40 + (n1+n2+n3+n4)*0.15), step(0.001, noise_blur));

    // ---------- Masque haut/bas ----------
    float w_top  = smoothstep(1.0 - top_margin, 1.0, uv.y);
    float w_bot  = 1.0 - smoothstep(0.0, bottom_margin, uv.y);
    float w_edge = max(w_top, w_bot);
    float center = abs(uv.y - 0.5);
    float hold   = 1.0 - smoothstep(0.0, core_hold, center);
    float thr_tb = cutoff + edge_strength * w_edge - 0.25 * hold;
    float a_tb   = smoothstep(thr_tb - softness, thr_tb + softness, n);

    // ---------- Fades gauche/droite ----------
    float lm = max(left_margin,  0.0001);
    float rm = max(right_margin, 0.0001);
    float left_fade  = smoothstep(0.0, lm, uv.x);
    float right_fade = 1.0 - smoothstep(1.0 - rm, 1.0, uv.x);

    float a_shape = a_tb * left_fade * right_fade;

    // ---------- Liseré adouci ----------
    // Gradient du masque vertical pour anti-aliaser l’anneau
    float grad = max(length(vec2(dFdx(a_tb), dFdy(a_tb))), 1e-5);
    float w    = edge_width_px * grad;
    float ring = clamp(smoothstep(0.5 - w, 0.5, a_tb) - smoothstep(0.5, 0.5 + w, a_tb), 0.0, 1.0);

    // Couleurs
    vec3 base_col = hsv2rgb(vec3(hue,      sat,      val));
    vec3 ring_col = hsv2rgb(vec3(edge_hue, edge_sat, edge_val));
    vec3 final_rgb = mix(base_col, ring_col, ring * edge_mix);

    COLOR = vec4(final_rgb, a_shape);
}