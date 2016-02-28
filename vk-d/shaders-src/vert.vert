/*
 * Vertex shader used by Cube demo.
 */
#version 400
#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable
/*
layout(std140, binding = 0) uniform buf {
        mat4 MVP;
        vec4 position[12*3];
        vec4 attr[12*3];
} ubuf;
*/

//layout (location = 0) out vec4 texcoord;

out gl_PerVertex {
        vec4 gl_Position;
};

void main() 
{
   gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
}
