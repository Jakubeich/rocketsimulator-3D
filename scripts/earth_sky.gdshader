shader_type sky;
render_mode disable_fog, use_half_res_pass;

// Analytic ray / sphere intersection in Earth-radius units. The rendered
// planet is background only: nearby launch and landing scenery occlude it.
// Coordinates are local launch East, Up, South; the image uses lon/lat.
uniform sampler2D earth_map : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloud_map : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 camera_earth = vec3(0.0, 1.0, 0.0);
uniform float altitude_m = 0.0;
uniform bool landing_region = false;
uniform vec3 local_sun = vec3(0.45, 0.75, -0.48);

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec3 to_geographic(vec3 v) {
    // Cape Canaveral: 28.5° N, 80.6° W. The three columns transform
    // launch-local east/up/south to Earth-fixed longitude and latitude.
    vec3 east = vec3(0.98657, 0.0, 0.16333);
    vec3 up = vec3(0.14354, 0.47716, -0.86739);
    vec3 south = vec3(0.07795, -0.87882, -0.47075);
    return east * v.x + up * v.y + south * v.z;
}

void sky() {
    if (!AT_HALF_RES_PASS && !AT_CUBEMAP_PASS) {
        COLOR = HALF_RES_COLOR.rgb;
    } else {
    vec3 ray = normalize(EYEDIR);
    vec3 radial = normalize(camera_earth);
    float elevation = dot(ray, radial);
    float space = smoothstep(8000.0, 85000.0, altitude_m);
    float horizon = exp(-abs(elevation) * 5.5);
    vec3 zenith = mix(vec3(0.17, 0.36, 0.64), vec3(0.001, 0.003, 0.010), space);
    vec3 haze = mix(vec3(0.63, 0.76, 0.88), vec3(0.012, 0.025, 0.055), space);
    vec3 sky_color = mix(zenith, haze, horizon * 0.85);
    if (elevation < 0.0) {
        sky_color = mix(sky_color, mix(vec3(0.19, 0.27, 0.23), vec3(0.003, 0.006, 0.014), space), smoothstep(0.0, 0.2, -elevation));
    }
    // Very sparse fixed-direction stars, evaluated before the opaque planet.
    vec3 star_cell = floor(ray * 1300.0);
    float star = step(0.9986, hash13(star_cell)) * pow(clamp(hash13(star_cell + 7.0), 0.0, 1.0), 3.0);
    sky_color += vec3(0.68, 0.76, 1.0) * star * space;

    float b = dot(camera_earth, ray);
    float c = max(dot(camera_earth, camera_earth) - 1.0, 0.00000001);
    float discriminant = b * b - c;
    if (b < 0.0 && discriminant > 0.0) {
        float hit = -b - sqrt(discriminant);
        vec3 normal = normalize(camera_earth + ray * hit);
        vec3 g = normalize(to_geographic(normal));
        float lon = atan(g.z, g.x);
        float lat = asin(clamp(g.y, -1.0, 1.0));
        // Longitude wraps; latitude clamps at the poles instead of wrapping
        // north into south (which otherwise produces visible polar stripes).
        vec2 uv = vec2(fract(lon / TAU + 0.5), clamp(0.5 - lat / PI, 0.0005, 0.9995));
        vec3 surface = texture(earth_map, uv).rgb;
        // Subtle fabricated surface variation only at low altitude. This adds
        // visual texture, not geographic detail or physical height geometry.
        float land = smoothstep(0.0, 0.10, surface.g - surface.b * 0.85);
        float micro = sin(g.x * 8200.0 + sin(g.z * 3800.0)) * sin(g.z * 6900.0 + g.y * 4300.0);
        float micro_fade = 1.0 - smoothstep(12000.0, 45000.0, altitude_m);
        surface *= 1.0 + micro * 0.045 * land * micro_fade;
        float landing_blend = landing_region ? 1.0 - smoothstep(2500.0, 14000.0, altitude_m) : 0.0;
        vec3 plain = vec3(0.33, 0.40, 0.24) * (1.0 + micro * 0.045);
        surface = mix(surface, plain, landing_blend);
        // A static NASA historical cloud composite, intentionally not weather.
        float cloud = smoothstep(0.06, 0.75, texture(cloud_map, uv).r);
        float cloud_fade = smoothstep(9000.0, 25000.0, altitude_m);
        surface = mix(surface, vec3(0.88, 0.91, 0.92), cloud * 0.72 * cloud_fade);
        // Soft day-side shading without an abrupt artificial terminator.
        float light = 0.72 + 0.28 * max(dot(normal, normalize(local_sun)), 0.0);
        vec3 surface_color = surface * light;
        // Aerial perspective fades naturally with angle near the limb.
        float limb = pow(1.0 - clamp(dot(normal, -ray), 0.0, 1.0), 4.0);
        surface_color = mix(surface_color, vec3(0.30, 0.53, 0.75), limb * 0.35);
        float planet_fade = smoothstep(80.0, 4000.0, altitude_m);
        planet_fade = mix(planet_fade, 1.0, landing_blend);
        sky_color = mix(sky_color, surface_color, planet_fade);
    } else if (b < 0.0 && space > 0.01) {
        // Thin blue atmospheric limb just outside the disc.
        float glow = exp(-abs(discriminant) * 600.0) * space * 0.35;
        sky_color += vec3(0.20, 0.42, 0.85) * glow;
    }
    COLOR = sky_color;
    if (AT_HALF_RES_PASS) { ALPHA = 1.0; }
    }
}
