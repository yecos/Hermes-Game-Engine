class_name WorldMaterials3D
extends RefCounted

static func road_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 asphalt_color : source_color = vec4(0.105, 0.12, 0.135, 1.0);
uniform vec4 rubber_color : source_color = vec4(0.035, 0.04, 0.045, 1.0);
uniform float roughness_value = 0.82;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float grain = hash21(floor(UV * vec2(420.0, 1500.0)));
	float fine_grain = hash21(floor(UV * vec2(1300.0, 4500.0)));
	float center = 1.0 - smoothstep(0.11, 0.32, abs(UV.x - 0.5));
	float rubber_noise = hash21(floor(UV * vec2(18.0, 260.0)));
	float rubber = center * smoothstep(0.48, 0.90, rubber_noise) * 0.28;
	vec3 base = asphalt_color.rgb * (0.86 + grain * 0.10 + fine_grain * 0.035);
	base = mix(base, rubber_color.rgb, rubber);
	ALBEDO = base;
	ROUGHNESS = roughness_value - grain * 0.08;
	METALLIC = 0.02;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

static func grass_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_a : source_color = vec4(0.12, 0.42, 0.08, 1.0);
uniform vec4 grass_b : source_color = vec4(0.22, 0.56, 0.11, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	float large = hash21(floor(UV * 55.0));
	float fine = hash21(floor(UV * 520.0));
	float stripes = 0.5 + 0.5 * sin((UV.x + UV.y) * 220.0);
	vec3 color = mix(grass_a.rgb, grass_b.rgb, large * 0.62 + stripes * 0.10);
	color *= 0.90 + fine * 0.12;
	ALBEDO = color;
	ROUGHNESS = 0.93;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

static func curb_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.64
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
