shader_type canvas_item;
uniform bool remove_white = false;
uniform float bottom_cutoff = 1.0;
// 旧第二幕 Boss 帧附带不透明白底。仅在显示时去掉中性白色，原美术文件保持不变。
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float white = min(source.r, min(source.g, source.b));
	float matte = remove_white ? smoothstep(0.88, 0.97, white) : 0.0;
	if (UV.y > bottom_cutoff) { discard; }
	COLOR *= vec4(1.0, 1.0, 1.0, 1.0 - matte);
}
