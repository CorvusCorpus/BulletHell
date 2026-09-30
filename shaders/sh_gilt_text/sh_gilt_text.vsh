// Gilt lettering (see `draw_text_gilt` in `scripts/spell_cutin`): passes the
// vertex's position on the GUI layer through, so the fragment stage can grade
// the gold down the letters wherever the text is placed or turned.
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying vec2 v_vPos;

void main() {
    vec4 obj = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * obj;
    v_vColour = in_Colour;
    v_vTexcoord = in_TextureCoord;
    v_vPos = (gm_Matrices[MATRIX_WORLD] * obj).xy;
}
