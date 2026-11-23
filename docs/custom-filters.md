# Your own screen filters

A filter is a `.glsl` file. Its first line is a JSON header that names it; the rest is GLSL 1.00 fragment code that changes one color.
Add it from the inspector: Screen Filter › Add Filter…. RenChan copies it into `~/Library/Application Support/RenChan/Filters`;
adding a file with the same name again replaces it.

```glsl
// {"name": "Sepia"}
c = mix(c, vec3(dot(c, vec3(0.393, 0.769, 0.189)),
                dot(c, vec3(0.349, 0.686, 0.168)),
                dot(c, vec3(0.272, 0.534, 0.131))), s);
```

What the code can use:

| Name | What it is |
| --- | --- |
| `c` | `vec3`, the pixel's color, 0 to 1. Change it. |
| `s` | `float`, the Strength slider, 0 to 1. Changes live while the game runs. |
| `px` | `vec2`, one pixel in texture coordinates. |
| `tex0`, `v_tex_coord` | the screen and this pixel's place on it, to read neighbors: `texture2D(tex0, v_tex_coord + vec2(px.x, 0.0)).rgb`. |

Filters need Ren'Py 7.4.6 or later. A mistake in the code shows as a Ren'Py error when the game starts; choose None and play again.
