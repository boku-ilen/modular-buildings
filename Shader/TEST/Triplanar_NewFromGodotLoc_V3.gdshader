shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

//// GENERAL PARAMETERS
group_uniforms general_parameters;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform int debug_mode = 0; // Debug-view different things if >0

//// BASE LAYER
group_uniforms layer_base;
uniform vec4 base_albedo_tint : source_color = vec4(0.0); // Multiplied on top of _albedo_tex
uniform sampler2D base_albedo_tex;
uniform sampler2D base_normal_tex : hint_roughness_normal;
uniform sampler2D base_mra_tex; // R=Metal G=Rough B=AO
uniform float base_uv_density : hint_range(0.01, 10.0) = 1.0; // Density = UV Tiling
group_uniforms;

//// DIRT LAYER
group_uniforms layer_dirt;
uniform sampler2D dirt_albedo_tex; // Depending on whether "Simple" or "Expensive" method, this is either mixed with Base Layer, or just multiplied on top of it (both methods using Dirtmask_Tex)
uniform vec4 dirt_albedo_tint : source_color = vec4(1.0); // Multiplied on top of _albedo_tex
// "Expensive Method": Disabled for Performance reason, currently only uses Tex to multiply on top
uniform sampler2D dirt_normal_tex : hint_roughness_normal;
uniform sampler2D dirt_mra_tex; // R=Metal G=Rough B=AO
uniform float dirt_uv_density : hint_range(0.01, 20.0) = 4.0; // Density = UV Tiling
group_uniforms;

//// DIRTMASK = Mask for Blending between pure Base layer, and Base Layer * Dirt Layer
group_uniforms dirtmask;
uniform sampler2D dirtmask_tex; // Grayscale
uniform float dirtmask_amount : hint_range(0.0, 1.0) = 0.5; // Used for Blending between unmodified Base Layer and Dirt Layer
uniform float dirtmask_uv_density : hint_range(0.01, 20.0) = 2.0;
group_uniforms;

varying vec3 v_triplanar_pos;
varying vec3 v_local_normal; // Used for determining dominant axis of Vertex -> which Projection Axis to use

// WARNING: Meshes must NOT use negative scale, this is not considered!


void vertex() {
	v_local_normal = NORMAL; // Pass local normal through to fragment (we'll pick dominant axis per-pixel)
	vec3 normal = NORMAL; // Maybe not required?
	// --- Unsure, maybe fixes some orientation issues, but minimal visual impact, could be disabled for Performance reason? Original Godot Triplanar Shader uses this.
	vec3 tangent_manip = normalize(vec3(
										abs(normal.y) + abs(normal.z),
										0.0,
										-abs(normal.x)
									));
	TANGENT = tangent_manip;

	vec3 binormal_manip = normalize(vec3(
										0.0,
										abs(normal.x) + abs(normal.z),
										-abs(normal.y)
									));
	BINORMAL = binormal_manip;

	// --- World position of the vertex
	vec3 vertex_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// --- Rotation-only basis from MODEL_MATRIX (strip scale)
	vec3 ax = normalize(MODEL_MATRIX[0].xyz);
	vec3 ay = normalize(MODEL_MATRIX[1].xyz);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	// world -> object-axes (inverse rotation via transpose)
	mat3 world_to_obj_axes = transpose(mat3(ax, ay, az));

	// World anchored coordinates expressed in object axes
	// => seamless UVs across meshes with identical rotation
	v_triplanar_pos = world_to_obj_axes * vertex_wp;
	v_triplanar_pos *= vec3(1.0, -1.0, 1.0);
}

vec4 triplanar_texture(sampler2D in_sampler, vec3 in_axis_mask, vec3 in_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(in_sampler, in_triplanar_pos.xy) * in_axis_mask.z;
	samp += texture(in_sampler, in_triplanar_pos.xz) * in_axis_mask.y;
	samp += texture(in_sampler, in_triplanar_pos.zy * vec2(-1.0, 1.0)) * in_axis_mask.x;
	// Put back expansive computation for Blended here as an option!
	return samp;
}

void fragment() {
	// -------------------------
	// DOMINANT AXIS (PER-PIXEL, HARD / ONE-HOT)
	// -------------------------
	vec3 n = normalize(v_local_normal);
	vec3 an = abs(n);
	// one-hot winner (avoids ties turning on multiple axes)
	float x_wins = step(an.y, an.x) * step(an.z, an.x);
	float y_wins = step(an.x, an.y) * step(an.z, an.y);
	float z_wins = 1.0 - max(x_wins, y_wins);
	vec3 axis_mask = vec3(x_wins, y_wins, z_wins);
	// sign of local normal (+1 / -1) per axis
	vec3 axis_sign = vec3(
		mix(-1.0, 1.0, step(0.0, n.x)),
		mix(-1.0, 1.0, step(0.0, n.y)),
		mix(-1.0, 1.0, step(0.0, n.z))
		);

	// Optional: flip U on negative-facing projections to reduce mirroring
	float fx = (axis_sign.x < 0.0) ? -1.0 : 1.0;
	float fy = (axis_sign.y < 0.0) ? -1.0 : 1.0;
	float fz = (axis_sign.z < 0.0) ? -1.0 : 1.0;
	
	///// NOT WORKING CORRECTLY YET!
	//vec2 uv_xaxis = vec2(v_triplanar_pos.z * fx, v_triplanar_pos.y);
	//vec2 uv_yaxis = vec2(v_triplanar_pos.x * fy, v_triplanar_pos.z);
	//vec2 uv_zaxis = vec2(v_triplanar_pos.x * fz, v_triplanar_pos.y);

	vec2 uv_xaxis = v_triplanar_pos.zy;
	vec2 uv_yaxis = v_triplanar_pos.zx;
	vec2 uv_zaxis = v_triplanar_pos.xy;
	
	vec2 proj_uv = uv_xaxis * axis_mask.x + uv_yaxis * axis_mask.y + uv_zaxis * axis_mask.z;
	
	// -------------------------
	// UV SETS
	// -------------------------
	vec2 uv_base = proj_uv * base_uv_density;
	vec2 uv_dirt = proj_uv * dirt_uv_density;
	vec2 uv_dirtmask = proj_uv * dirtmask_uv_density;
	
	//// BASE LAYER TEX SAMPLING
	//vec3 base_albedo_texsampled = vec3(1.0, 1.0, 1.0) * base_albedo_tint.rgb;
	vec3 base_albedo_texsampled = triplanar_texture(base_albedo_tex, axis_mask, v_triplanar_pos).rgb * base_albedo_tint.rgb;
	vec3 base_normal_texsampled = triplanar_texture(base_normal_tex, axis_mask, v_triplanar_pos).xyz;
	//float base_rmao_texsampled = triplanar_texture(base_mrao_tex, axis_mask, v_triplanar_pos).rgb;
//
    //// DIRT LAYER TEX SAMPLING
    vec3 dirt_albedo_texsampled = triplanar_texture(dirt_albedo_tex, axis_mask, v_triplanar_pos).rgb * dirt_albedo_tint.rgb;
	//vec3 dirt_normal_texsampled = triplanar_texture(dirt_normal_tex, uv_dirt).xyz * 2.0 - 1.0;
    //vec3 dirt_rmao_texsampled  = triplanar_texture(dirt_mrao_tex, uv_dirt).rgb;
//
	//// DIRTMASK TEX SAMPLING
	vec3 dirtmask_texsampled = triplanar_texture(dirtmask_tex, axis_mask, v_triplanar_pos).rgb;
	
	////-------------------------
	//CALCULATE "final_" channels for use in Output. DEBUG MODES can change those channels!
	////-------------------------
	vec3 final_albedo;
	vec3 final_normal;
	float final_metallic;
	float final_roughness;
	float final_ao;
	
	if (debug_mode == 0) {
		final_albedo     = mix(base_albedo_texsampled, dirt_albedo_texsampled, dirtmask_amount); // MAYBE WRONG MULT? // Cheap method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		//final_albedo     = mix(base_albedo_texsampled, (base_albedo_texsampled * dirt_albedo_texsampled), dirtmask_texsampled); // MAYBE WRONG MULT? // Cheap method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		final_normal    = base_normal_texsampled; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_metallic  = base_rmao_texsampled.r; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_roughness = base_rmao_texsampled.g; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_ao        = base_rmao_texsampled.b; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_albedo     = mix(base_albedo, dirt_albedo, dirtmask_texsampled); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		//final_normal    = ?
		//final_roughness = mix(base_rmao.g, dirt_rmao.g, dirtmask_texsampled); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		//final_metallic  = mix(base_rmao.r, dirt_rmao.r, dirtmask_texsampled); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		//final_ao        = mix(base_rmao.b, dirt_rmao.b, dirtmask_texsampled); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
	}
	else if (debug_mode == 1) {
		vec3 final_albedo = vec3(axis_mask.x, axis_mask.y, axis_mask.z);
		float final_metallic = 0.0;
		float final_roughness = 1.0;
    }
	else if (debug_mode == 2) {
		vec3 final_albedo = vec3(dirtmask_texsampled);
		float final_metallic = 0.0;
		float final_roughness = 1.0;
    }
	
    // -------------------------
    // TESTING OUTPUT - ONCE THIS IS IN SHADERINCLUDE, PUT THIS INTO ACTUAL SHADERS THEMSELVES and disable here!
    // -------------------------
	ALBEDO     = final_albedo;
	//METALLIC   = final_metallic;
	//ROUGHNESS  = final_roughness;
	//AO         = final_ao;
	NORMAL_MAP = final_normal;
	SPECULAR = specular;
	NORMAL_MAP_DEPTH = normal_scale;
}