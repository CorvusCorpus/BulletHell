// The hall's shader (see `scripts/bg_sanctum`): distance fog, plus a fade to
// transparent with distance. The fade is done here because `vertex_submit`
// has no per-draw alpha and the hall's buffers are frozen; both are computed
// from the same eye distance so they agree on where the hall ends.

attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vFog;

uniform vec2 u_fog;     // where the air starts to thicken, and where it is solid
uniform vec2 u_fade;    // where a surface starts to go, and where it is gone

void main() {
    vec4 obj = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * obj;

    // Eye distance rather than view-space z, so the fade boundary is a sphere
    // round the camera rather than a plane.
    float d = length((gm_Matrices[MATRIX_WORLD_VIEW] * obj).xyz);

    v_vFog = clamp((d - u_fog.x) / max(u_fog.y - u_fog.x, 1.0), 0.0, 1.0);
    float a = clamp((u_fade.y - d) / max(u_fade.y - u_fade.x, 1.0), 0.0, 1.0);

    v_vColour = vec4(in_Colour.rgb, in_Colour.a * a);
    v_vTexcoord = in_TextureCoord;
}
