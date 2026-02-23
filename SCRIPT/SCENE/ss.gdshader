shader_type canvas_item;

/* ----------- Contrôle du warp principal (onde) ----------- */
uniform float amp_px      : hint_range(0.0, 64.0) = 6.0; // amplitude en pixels
uniform vec2  freq_cyles  = vec2(6.0, 3.0);              // cycles (X déforme sur Y, Y déforme sur X)
uniform vec2  speed       = vec2(1.2, 0.0);               // vitesse (rad/s) de chaque onde

/* ----------- Bruit optionnel (domain warp léger) ----------- */
uniform sampler2D noise_tex;
uniform vec2  noise_scale = vec2(2.0, 2.0);
uniform float noise_speed = 0.4;
uniform float noise_mix   : hint_range(0.0, 1.0) = 0.35;  // 0 = sans bruit, 1 = max bruit

/* ----------- Limiter l’effet aux bords (0 = partout) ------- */
uniform float edge_focus  : hint_range(0.0, 1.0) = 0.0;   // 1 = warp surtout autour des contours
uniform float edge_boost  = 40.0;                         // gain du détecteur de bord

/* ----------- UV wrap (si tu vois des bords noirs, active Repeat sur la texture) --- */
uniform bool wrap_uv = false;


void fragment() {
    vec2 uv = UV;

    // Amplitude en UV (convertit des px vers UV)
    vec2 amp_uv = TEXTURE_PIXEL_SIZE * amp_px;

    // Onde sinusoïdale bidirectionnelle (déforme X en fonction de Y, et Y en fonction de X)
    vec2 sine_off = vec2(
        sin(uv.y * TAU * freq_cyles.x + TIME * speed.x),
        sin(uv.x * TAU * freq_cyles.y + TIME * speed.y)
    ) * amp_uv;

    // Domain warp avec bruit (optionnel)
    vec2 wuv = uv;
    if (noise_mix > 0.0) {
        vec2 nuv = uv * noise_scale + vec2(TIME * noise_speed, 0.0);
        // vectorise avec 2 canaux déphasés
        vec2 nvec = texture(noise_tex, fract(nuv)).rg;
        nvec = (nvec - 0.5) * 2.0; // [-1..1]
        vec2 noise_off = nvec * amp_uv * 0.8; // amplitude du bruit ~80% de l’onde
        wuv += mix(vec2(0.0), noise_off, noise_mix);
    }

    // UV final
    vec2 final_uv = wuv + sine_off;
    if (wrap_uv) {
        final_uv = fract(final_uv); // nécessite la texture en Repeat pour être parfait
    }

    // Echantillons « original » (non déformé) et « warpé »
    vec4 col_base  = texture(TEXTURE, uv);
    vec4 col_warp  = texture(TEXTURE, final_uv);

    // Masque de bords : gradient sur l’alpha original
    float a0  = col_base.a;
    float dax = texture(TEXTURE, uv + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a - a0;
    float day = texture(TEXTURE, uv + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a - a0;
    float edge = clamp(edge_boost * length(vec2(dax, day)), 0.0, 1.0);

    // Force de mélange : 0→ warp partout ; 1→ warp surtout au bord
    float mix_strength = mix(1.0, edge, edge_focus);

    vec4 col = mix(col_base, col_warp, mix_strength);

    // On garde l’alpha du sample warpé pour que la silhouette se déforme vraiment
    COLOR = vec4(col.rgb, col.a);
}