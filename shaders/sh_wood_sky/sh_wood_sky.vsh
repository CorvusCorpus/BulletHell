// The wood's sky (see `wood_draw_sky` in `scripts/bg_wood`): a dome and
// cards round the camera, which move with it so they stay at infinity.

attribute vec3 in_Position;
attribute vec3 in_Normal;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
attribute vec4 in_TextureCoord1;

varying vec3 v_dir;      // the direction from the camera, in the world
varying vec4 v_col;
varying vec2 v_uv;
varying vec4 v_ex;

void main() {
    vec4 wp = gm_Matrices[MATRIX_WORLD] * vec4(in_Position, 1.0);
    // The world matrix carries the camera's position as its translation.
    v_dir = wp.xyz - gm_Matrices[MATRIX_WORLD][3].xyz;
    v_col = in_Colour;
    v_uv = in_TextureCoord;
    v_ex = in_TextureCoord1;
    gl_Position = gm_Matrices[MATRIX_PROJECTION] * (gm_Matrices[MATRIX_VIEW] * wp);
}
