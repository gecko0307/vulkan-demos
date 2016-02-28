module main;

import core.runtime;
import core.sys.windows.windows;
import std.string;
import vkapp;
 
extern (Windows) int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    int result;
 
    try
    {
        Runtime.initialize();
        result = myWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);
        Runtime.terminate();
    }
    catch(Throwable e) 
    {
        MessageBoxA(null, e.toString().toStringz(), "Error",
                    MB_OK | MB_ICONEXCLAMATION);
        result = 0;
    }
 
    return result;
}
 
int myWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    VulkanApplication app = new VulkanApplication("Vulkan Test", hInstance);
    app.run();
    return 0;
}