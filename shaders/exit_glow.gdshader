shader_type spatial;
render_mode unshaded;

uniform vec4 color: source_color = vec4(0.314, 0.953, 0.467, 1.0);
uniform float height = 1.0;

//varying vec3 world_pos;
varying vec3 vertex_pos;

void vertex() {
    //world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_pos = VERTEX;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * clamp((1.0-vertex_pos.y/height), 0.0, 1.0);
}