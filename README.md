Vulkan Demos
============
These are my first experiments with Vulkan graphics API. I'm using [LunarG SDK](http://lunarg.com/vulkan-sdk), [MinGW](http://www.mingw.org) and [SDL2](https://www.libsdl.org).

* [vk-sdl](https://github.com/gecko0307/vulkan-demos/tree/master/vk-sdl) - cube demo from LunarG SDK ported to SDL2. Currently supports only Windows, sorry (relies on GetWindowLong to get HINSTANCE).
* [vk-d](https://github.com/gecko0307/vulkan-demos/tree/master/vk-d) - minimal Vulkan/Win32 demo written in D language. Doesn't draw anything, just clears the screen with blue color. Uses modified [VulkanizeD](https://github.com/Rikarin/VulkanizeD) binding.
* [vk-d-sdl](https://github.com/gecko0307/vulkan-demos/tree/master/vk-d-sdl) - minimal Vulkan/SDL demo written in D language. Doesn't draw anything, just clears the screen with blue color. Uses Derelict 2, SDL 1.2 and modified [VulkanizeD](https://github.com/Rikarin/VulkanizeD) binding. SDL2 version coming soon.

Eventually more demos will be added.
