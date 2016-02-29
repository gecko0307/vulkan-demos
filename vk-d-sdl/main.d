module mainsdl;

import core.sys.windows.windows;
import std.stdio;
import std.string;
import derelict.sdl.sdl;
import vkctx;
 
void main()
{
    DerelictSDL.load();
 
    uint width = 640;
    uint height = 480;
    string caption = "Vulkan Test";

    SDL_Init(SDL_INIT_VIDEO);
    SDL_Surface* screen = SDL_SetVideoMode(width, height, 0, 0);
    
    SDL_WM_SetCaption(toStringz(caption), null);
    
    // Get window info from SDL
    SDL_SysWMinfo systemInfo; 
    SDL_GetWMInfo(&systemInfo);
    HWND hwnd = systemInfo.window;

    VulkanContext vkCtx = new VulkanContext("Vulkan Test", width, height, hwnd);
    
    bool running = true;
    SDL_Event event;
    while(running)
    {
        if (SDL_PollEvent(&event))
        {
            if (event.type == SDL_QUIT)
                running = false;
        }
        
        vkCtx.render();
    }
    
    vkCtx.deinit();
    SDL_Quit();
}