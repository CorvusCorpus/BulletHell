// Gilt lettering, the runtime counterpart of the title card's rendered name
// (`gilt` in `tools/make_titles.py`, whose gold stops these are): a gold
// that darkens across a horizon below the capitals' middle, lit along the
// letters' upper-left edges and shaded along their lower-right ones.
//
// `u_origin` is the text's anchor and `u_down` the unit vector down its
// letters (the text may be turned). `u_cap` is where its capitals start
// along `u_down` from the anchor, and how tall they are. `u_bevel` is the
// bevel's reach in texels, up and left in the font's texture. `u_sheen` is a
// band of light crossing the letters: its position along the text from the
// anchor, its half-width, and its strength. `u_flash` turns it all to
// white-gold.

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying vec2 v_vPos;

uniform vec2 u_origin;
uniform vec2 u_down;
uniform vec2 u_cap;
uniform vec2 u_bevel;
uniform vec3 u_sheen;
uniform float u_flash;

vec3 gold(float t) {
    vec3 c0 = vec3(1.000, 0.965, 0.808);
    vec3 c1 = vec3(0.988, 0.871, 0.533);
    vec3 c2 = vec3(0.894, 0.667, 0.259);
    vec3 c3 = vec3(0.588, 0.345, 0.102);
    vec3 c4 = vec3(0.769, 0.510, 0.173);
    vec3 c5 = vec3(0.957, 0.769, 0.408);
    if (t < 0.28) return mix(c0, c1, t / 0.28);
    if (t < 0.52) return mix(c1, c2, (t - 0.28) / 0.24);
    if (t < 0.56) return mix(c2, c3, (t - 0.52) / 0.04);
    if (t < 0.70) return mix(c3, c4, (t - 0.56) / 0.14);
    return mix(c4, c5, (t - 0.70) / 0.30);
}

void main() {
    float a = texture2D(gm_BaseTexture, v_vTexcoord).a;
    vec2 d = v_vPos - u_origin;
    float down = dot(d, u_down);
    vec3 col = gold(clamp((down - u_cap.x) / u_cap.y, 0.0, 1.0));

    float up_left = texture2D(gm_BaseTexture, v_vTexcoord - u_bevel).a;
    float down_right = texture2D(gm_BaseTexture, v_vTexcoord + u_bevel).a;
    col = mix(col, vec3(1.0, 0.988, 0.902), clamp(a - up_left, 0.0, 1.0) * 0.85);
    col = mix(col, vec3(0.431, 0.227, 0.063), clamp(a - down_right, 0.0, 1.0) * 0.75);

    // The sheen leans with the letters, like a reflection.
    vec2 across = vec2(u_down.y, -u_down.x);
    float x = dot(d, across) + down * 0.35;
    float s = 1.0 - clamp(abs(x - u_sheen.x) / max(u_sheen.y, 1.0), 0.0, 1.0);
    col += vec3(1.0, 0.95, 0.80) * (s * s * u_sheen.z);

    col = mix(col, vec3(1.0, 0.98, 0.90), u_flash);
    gl_FragColor = vec4(min(col, vec3(1.0)), a * v_vColour.a);
}
