// Test shaders for a Metal driver that is still learning: each function exercises one thing, and the expected result
// is easy to compute on the CPU. Used by the check application of the Redmi K40 iOS port; nothing here is specific to
// it.
#include <metal_stdlib>
using namespace metal;

struct Vertex {
	float4 position;
	float4 color;
};

struct VOut {
	float4 position [[position]];
	float4 color;
	float2 uv;
};

// ---- render ----

// A triangle that covers the whole target, from the vertex index alone (no buffers): draw 3 vertices.
vertex VOut v_fullscreen(uint vid [[vertex_id]])
{
	float2 p = float2((vid << 1) & 2, vid & 2);
	VOut o;
	o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
	o.color = float4(1.0);
	o.uv = float2(p.x, 1.0 - p.y);
	return o;
}

// Positions (clip space) and colours from buffer 0.
vertex VOut v_colored(uint vid [[vertex_id]], const device Vertex *v [[buffer(0)]])
{
	VOut o;
	o.position = v[vid].position;
	o.color = v[vid].color;
	o.uv = v[vid].position.xy * 0.5 + 0.5;
	return o;
}

// The interpolated vertex colour.
fragment float4 f_color(VOut in [[stage_in]])
{
	return in.color;
}

// One colour, from fragment buffer 0.
fragment float4 f_solid(constant float4 &c [[buffer(0)]])
{
	return c;
}

// Texture 0 through sampler 0.
fragment float4 f_texture(VOut in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]])
{
	return t.sample(s, in.uv);
}

// ---- clip distances ----

struct ClipOut1 {
	float4 position [[position]];
	float clip [[clip_distance]] [1];
};

// The whole-target triangle with one clip distance, its clip-space x: everything left of the middle is clipped.
vertex ClipOut1 v_clip1(uint vid [[vertex_id]])
{
	float2 p = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
	ClipOut1 o;
	o.position = float4(p, 0.0, 1.0);
	o.clip[0] = p.x;
	return o;
}

struct ClipOut2 {
	float4 position [[position]];
	float clip [[clip_distance]] [2];
};

// Two: x and y (up in clip space) -- only the top right quarter is left.
vertex ClipOut2 v_clip2(uint vid [[vertex_id]])
{
	float2 p = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
	ClipOut2 o;
	o.position = float4(p, 0.0, 1.0);
	o.clip[0] = p.x;
	o.clip[1] = p.y;
	return o;
}

// ---- compute ----

// d[i] = 3i + 1: no inputs at all.
kernel void k_iota(device uint *d [[buffer(0)]], uint i [[thread_position_in_grid]])
{
	d[i] = 3u * i + 1u;
}

// c = a + b.
kernel void k_add(const device float *a [[buffer(0)]], const device float *b [[buffer(1)]],
		device float *c [[buffer(2)]], uint i [[thread_position_in_grid]])
{
	c[i] = a[i] + b[i];
}

// A gradient into whatever texture format: red = x / (w - 1), green = y / (h - 1), blue 0.5, alpha 1. Read back as
// RGBA8Unorm, pixel (x, y) must be (round(255x/(w-1)), round(255y/(h-1)), 128, 255): the store has to convert to the
// texture's format.
kernel void k_gradient(texture2d<float, access::write> t [[texture(0)]], uint2 g [[thread_position_in_grid]])
{
	uint w = t.get_width(), h = t.get_height();
	if (g.x >= w || g.y >= h)
		return;
	t.write(float4(float(g.x) / float(w - 1), float(g.y) / float(h - 1), 0.5, 1.0), g);
}

// Sum of in[] through threadgroup memory and barriers, added atomically into sum[0].
kernel void k_reduce(const device uint *in [[buffer(0)]], device atomic_uint *sum [[buffer(1)]],
		threadgroup uint *scratch [[threadgroup(0)]], uint i [[thread_position_in_grid]],
		uint l [[thread_position_in_threadgroup]], uint n [[threads_per_threadgroup]])
{
	scratch[l] = in[i];
	threadgroup_barrier(mem_flags::mem_threadgroup);
	for (uint s = n / 2; s > 0; s >>= 1) {
		if (l < s)
			scratch[l] += scratch[l + s];
		threadgroup_barrier(mem_flags::mem_threadgroup);
	}
	if (l == 0)
		atomic_fetch_add_explicit(sum, scratch[0], memory_order_relaxed);
}

// Function constants: d[i] = d[i] * scale (+ 10 when offset is true). Specialise with constant 0 (float) and 1 (bool).
constant float fc_scale [[function_constant(0)]];
constant bool fc_offset [[function_constant(1)]];

kernel void k_constants(device float *d [[buffer(0)]], uint i [[thread_position_in_grid]])
{
	d[i] = d[i] * fc_scale + (fc_offset ? 10.0 : 0.0);
}

// ---- one thing at a time, for when k_gradient fails ----

// The size of texture 0 as a kernel sees it: d[0] = get_width(), d[1] = get_height(). Three ways of holding the
// texture, because a written one is an image to the GPU and a read-only one a texture: write, read_write, read.
kernel void k_sizes(texture2d<float, access::write> t [[texture(0)]], device uint *d [[buffer(0)]],
		uint2 g [[thread_position_in_grid]])
{
	if (g.x == 0 && g.y == 0) {
		d[0] = t.get_width();
		d[1] = t.get_height();
	}
}

kernel void k_sizes_rw(texture2d<float, access::read_write> t [[texture(0)]], device uint *d [[buffer(0)]],
		uint2 g [[thread_position_in_grid]])
{
	if (g.x == 0 && g.y == 0) {
		d[0] = t.get_width();
		d[1] = t.get_height();
	}
}

kernel void k_sizes_ro(texture2d<float, access::read> t [[texture(0)]], device uint *d [[buffer(0)]],
		uint2 g [[thread_position_in_grid]])
{
	if (g.x == 0 && g.y == 0) {
		d[0] = t.get_width();
		d[1] = t.get_height();
	}
}

// k_gradient with the size from buffer 0 instead of the texture's own queries.
kernel void k_gradient_n(texture2d<float, access::write> t [[texture(0)]], constant uint2 &n [[buffer(0)]],
		uint2 g [[thread_position_in_grid]])
{
	if (g.x >= n.x || g.y >= n.y)
		return;
	t.write(float4(float(g.x) / float(n.x - 1), float(g.y) / float(n.y - 1), 0.5, 1.0), g);
}

// The same in halves: a 16-bit value stored, converted to the texture's format.
kernel void k_gradient16(texture2d<half, access::write> t [[texture(0)]], constant uint2 &n [[buffer(0)]],
		uint2 g [[thread_position_in_grid]])
{
	if (g.x >= n.x || g.y >= n.y)
		return;
	t.write(half4(half(g.x) / half(n.x - 1), half(g.y) / half(n.y - 1), 0.5h, 1.0h), g);
}

// Integers into an integer texture (RGBA8Uint): pixel (x, y) = (x, y, 7, 255).
kernel void k_store_uint(texture2d<uint, access::write> t [[texture(0)]], uint2 g [[thread_position_in_grid]])
{
	t.write(uint4(g.x, g.y, 7u, 255u), g);
}
