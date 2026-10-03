// A sprite as its own negative (the hit mark, `fx_hit_mark_draw`): every
// colour inverted, its alpha kept, times the draw alpha.
varying vec2 v_vTexcoord;
varying vec4 v_vColour;

void main() {
    vec4 c = texture2D(gm_BaseTexture, v_vTexcoord);
    gl_FragColor = vec4(vec3(1.0) - c.rgb, c.a * v_vColour.a);
}
