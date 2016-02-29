module vkctx;

import core.sys.windows.windows;

import std.stdio;
import std.conv;
import std.string;
import std.file;

import vulkan;

version = VulkanDebug;

struct SwapchainBuffers
{
    VkImage image;
    VkCommandBuffer cmd;
    VkImageView view;
}

struct Depth
{
    VkFormat format;
    VkImage image;
    VkMemoryAllocateInfo mem_alloc = VkMemoryAllocateInfo(
        VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        null,
        0,
        0
    );
    VkDeviceMemory mem;
    VkImageView view;
}

class VulkanContext
{
    string name;
    const(char)* nameCPtr;
    
    VkInstance inst;
    VkPhysicalDevice gpu;
    VkDevice device;
    VkQueue queue;
    VkPhysicalDeviceMemoryProperties memory_properties;
    
    string gpuName;
    uint gpuID;
    uint gpuVendorID;
    uint numGPUs;
    uint queueCount;
    
    HINSTANCE connection;
    HWND window;
    VkSurfaceKHR surface;
    uint graphics_queue_node_index;
    
    uint windowWidth;
    uint windowHeight;
    
    VkFormat format;
    VkColorSpaceKHR color_space;
    
    bool quit;
    int curFrame;
    
    VkCommandPool cmd_pool;
    
    uint swapchainImageCount;
    VkSwapchainKHR swapchain;
    SwapchainBuffers[] buffers;
    Depth depth;
    
    VkCommandBuffer cmd;
    VkPipelineLayout pipeline_layout;
    VkDescriptorSetLayout desc_layout;
    VkRenderPass render_pass;
    VkPipelineCache pipelineCache;
    VkPipeline pipeline;
    
    VkShaderModule vsModule;
    VkShaderModule fsModule;
    
    VkDescriptorPool desc_pool;
    VkDescriptorSet desc_set;

    VkFramebuffer[] framebuffers;
    
    uint current_buffer;
    
    bool vulkanInitialized = false;
    
    this(string appName, uint width, uint height, HWND hwnd)
    {
        name = appName;
        auto nameCPtr = toStringz(name);
        
        windowWidth = width;
        windowHeight = height;
        
        connection = cast(HINSTANCE)GetWindowLong(hwnd, GWL_HINSTANCE);
        window = hwnd;
        initVulkan();
    }

    void initVulkan()
    {
        if (vulkanInitialized)
            return;

        createInstance();
        enumeratePhysicalDevices();
        createDevice();
        createWin32Surface();
        initSwapchain();

        VkCommandPoolCreateInfo cmd_pool_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            pNext: null,
            flags: 0,
            queueFamilyIndex: graphics_queue_node_index,
        };
        auto res = vkCreateCommandPool(device, &cmd_pool_info, null, &cmd_pool);
        assert(res == VkResult.VK_SUCCESS);
        
        VkCommandBufferAllocateInfo cmdInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            pNext: null,
            commandPool: cmd_pool,
            level: VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandBufferCount: 1
        };
        
        prepareBuffers();
        prepareDepth();
        prepareTextures(); // TODO
        prepareCubeDataBuffer(); // TODO
        prepareDescriptorLayout();
        prepareRenderPass();
        preparePipeline();
        
        for (uint i = 0; i < swapchainImageCount; i++)
        {
            res = vkAllocateCommandBuffers(device, &cmdInfo, &buffers[i].cmd);
            assert(res == VkResult.VK_SUCCESS);
        }
        
        prepareDescriptorPool();
        prepareDescriptorSet();
        
        prepareFramebuffers();
        
        for (uint i = 0; i < swapchainImageCount; i++)
        {
            current_buffer = i;
            drawBuildCmd(buffers[i].cmd);
        }
        
        flushInitCmd();

        current_buffer = 0;

        vulkanInitialized = true;
    }
    
    void createInstance()
    {
        uint instance_extension_count = 0;
        vkEnumerateInstanceExtensionProperties(null, &instance_extension_count, null);
        version(VulkanDebug) writefln("instance_extension_count: %s", instance_extension_count);
        
        VkExtensionProperties[] instance_extensions;
        if (instance_extension_count > 0)
        {
            instance_extensions = new VkExtensionProperties[instance_extension_count];
            vkEnumerateInstanceExtensionProperties(null, &instance_extension_count, instance_extensions.ptr);
        }
    
        VkApplicationInfo app =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            pNext: null,
            pApplicationName: nameCPtr,
            applicationVersion: 0,
            pEngineName: nameCPtr,
            engineVersion: 0,
            apiVersion: VK_API_VERSION
        };
        
        string e1 = "VK_KHR_surface";
        string e2 = "VK_KHR_win32_surface";
        
        auto instExtNames =
        [
            toStringz(e1),
            toStringz(e2)
        ];

        VkInstanceCreateInfo instanceInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            pNext: null,
            flags: 0,
            pApplicationInfo: &app,
            enabledLayerCount: 0,
            ppEnabledLayerNames: null,
            enabledExtensionCount: 2,
            ppEnabledExtensionNames: instExtNames.ptr
        };
        
        auto res = vkCreateInstance(&instanceInfo, null, &inst);
        version(VulkanDebug) writefln("vkCreateInstance: %s", res);
        if (res != VkResult.VK_SUCCESS)
            throw new Exception("vkCreateInstance failed");
    }
    
    void enumeratePhysicalDevices()
    {
        auto res = vkEnumeratePhysicalDevices(inst, &numGPUs, null);
        version(VulkanDebug) writefln("numGPUs: %s", numGPUs);
        if (res != VkResult.VK_SUCCESS || numGPUs == 0)
            throw new Exception("No GPUs found");
            
        VkPhysicalDevice[] physicalDevices = new VkPhysicalDevice[numGPUs];
        res = vkEnumeratePhysicalDevices(inst, &numGPUs, physicalDevices.ptr);
        if (res != VkResult.VK_SUCCESS)
            throw new Exception("vkEnumeratePhysicalDevices failed");
            
        gpu = physicalDevices[0];

        uint device_extension_count = 0;
        vkEnumerateDeviceExtensionProperties(gpu, null, &device_extension_count, null);
        version(VulkanDebug) writefln("device_extension_count: %s", device_extension_count);
        VkExtensionProperties[] device_extensions = new VkExtensionProperties[device_extension_count];
        vkEnumerateDeviceExtensionProperties(gpu, null, &device_extension_count, device_extensions.ptr);
        
        VkPhysicalDeviceProperties gpuProps;
        vkGetPhysicalDeviceProperties(gpu, &gpuProps);
        gpuName = to!string(gpuProps.deviceName.ptr);
        gpuID = gpuProps.deviceID;
        gpuVendorID = gpuProps.vendorID;
        version(VulkanDebug) 
        {
            writefln("gpuVendorID: %s", gpuVendorID);
            writefln("gpuID: %s", gpuID);
            writefln("gpuName: %s", gpuName);
        }
    }
       
    void createDevice()
    {
        string e3 = "VK_KHR_swapchain";
        
        auto devExtNames =
        [
            toStringz(e3)
        ];
        
        float[1] queue_priorities = [0.0f];
        VkDeviceQueueCreateInfo queueInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            pNext: null,
            queueFamilyIndex: 0,
            queueCount: 1,
            pQueuePriorities: queue_priorities.ptr
        };

        VkDeviceCreateInfo devInfo = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            pNext: null,
            queueCreateInfoCount: 1,
            pQueueCreateInfos: &queueInfo,
            enabledLayerCount: 0,
            ppEnabledLayerNames: null,
            enabledExtensionCount: 1,
            ppEnabledExtensionNames: devExtNames.ptr,
            pEnabledFeatures: null
        };
        
        auto res = vkCreateDevice(gpu, &devInfo, null, &device);
        writefln("vkCreateDevice: %s", res);
        assert(res == VkResult.VK_SUCCESS);
        
        vkGetDeviceQueue(device, 0, 0, &queue);
    }
    
    void createWin32Surface()
    {
        // Create a WSI surface for the window
        VkWin32SurfaceCreateInfoKHR createInfo = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
            pNext: null,
            flags: 0,
            hinstance: connection,
            hwnd: window
        };

        auto res = vkCreateWin32SurfaceKHR(inst, &createInfo, null, &surface);
        assert(res == VkResult.VK_SUCCESS);
        
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &queueCount, null);
        version(VulkanDebug) writefln("queueCount: %s", queueCount);
        assert(queueCount >= 1);
        
        // Iterate over each queue to learn whether it supports presenting:
        VkBool32[] supportsPresent = new VkBool32[queueCount];
        for (size_t i = 0; i < queueCount; i++)
        {
            vkGetPhysicalDeviceSurfaceSupportKHR(gpu, i, surface, &supportsPresent[0]);
        }

        version(VulkanDebug) writefln("supportsPresent: %s", supportsPresent);
        
        auto queue_props = new VkQueueFamilyProperties[queueCount];
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &queueCount, queue_props.ptr);
        
        uint graphicsQueueNodeIndex = uint.max;
        uint presentQueueNodeIndex = uint.max;
        
        for (uint i = 0; i < queueCount; i++)
        {
            if (queue_props[i].queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT)
            {
                if (graphicsQueueNodeIndex == uint.max)
                    graphicsQueueNodeIndex = i;

                if (supportsPresent[i] == VK_TRUE)
                {
                    graphicsQueueNodeIndex = i;
                    presentQueueNodeIndex = i;
                    break;
                }
            }
        }
        version(VulkanDebug) writefln("graphicsQueueNodeIndex: %s", graphicsQueueNodeIndex);
        
        if (presentQueueNodeIndex == uint.max)
        {
            for (uint i = 0; i < queueCount; ++i)
            {
                if (supportsPresent[i] == VK_TRUE)
                {
                    presentQueueNodeIndex = i;
                    break;
                }
            }
        }
        version(VulkanDebug) writefln("presentQueueNodeIndex: %s", presentQueueNodeIndex);
        
        assert(graphicsQueueNodeIndex != uint.max && 
               presentQueueNodeIndex != uint.max && 
               graphicsQueueNodeIndex == presentQueueNodeIndex);
               
        graphics_queue_node_index = graphicsQueueNodeIndex;
    }
    
    void initSwapchain()
    {
        uint formatCount;
        auto res = vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null);
        assert(res == VkResult.VK_SUCCESS);
        version(VulkanDebug) writefln("formatCount: %s", formatCount);
        
        VkSurfaceFormatKHR[] surfFormats = new VkSurfaceFormatKHR[formatCount];
        res = vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, surfFormats.ptr);
        assert(res == VkResult.VK_SUCCESS);
        
        version(VulkanDebug) 
        {
            foreach(f; surfFormats)
                writefln("f.format: %s", surfFormats[0].format);
        }
        
        if (formatCount == 1 && surfFormats[0].format == VkFormat.VK_FORMAT_UNDEFINED)
        {
            format = VkFormat.VK_FORMAT_B8G8R8A8_UNORM;
        }
        else
        {
            assert(formatCount >= 1);
            format = surfFormats[0].format;
        }
        
        version(VulkanDebug) writefln("format: %s", format);
        
        color_space = surfFormats[0].colorSpace;
        quit = false;
        curFrame = 0;
        
        version(VulkanDebug) writefln("color_space: %s", color_space);
        
        vkGetPhysicalDeviceMemoryProperties(gpu, &memory_properties);
    }
    
    void prepareBuffers()
    {
        VkSwapchainKHR oldSwapchain = swapchain;
    
        VkSurfaceCapabilitiesKHR surfCapabilities;
        auto res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &surfCapabilities);
        assert(res == VkResult.VK_SUCCESS);
        
        uint presentModeCount;
        res = vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &presentModeCount, null);
        assert(res == VkResult.VK_SUCCESS);
        
        VkPresentModeKHR[] presentModes = new VkPresentModeKHR[presentModeCount];
        res = vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &presentModeCount, presentModes.ptr);
        assert(res == VkResult.VK_SUCCESS);
        
        VkExtent2D swapchainExtent;
        
        if (surfCapabilities.currentExtent.width == cast(uint)-1)
        {
            swapchainExtent.width = windowWidth;
            swapchainExtent.height = windowHeight;
        }
        else 
        {
            swapchainExtent = surfCapabilities.currentExtent;
            windowWidth = surfCapabilities.currentExtent.width;
            windowHeight = surfCapabilities.currentExtent.height;
        }
        
        VkPresentModeKHR swapchainPresentMode = VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR;
        
        for (size_t i = 0; i < presentModeCount; i++)
        {
            if (presentModes[i] == VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR)
            {
                swapchainPresentMode = VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR;
                break;
            }
            if ((swapchainPresentMode != VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR) &&
                (presentModes[i] == VkPresentModeKHR.VK_PRESENT_MODE_IMMEDIATE_KHR))
            {
                swapchainPresentMode = VkPresentModeKHR.VK_PRESENT_MODE_IMMEDIATE_KHR;
            }
        }
        
        version(VulkanDebug) writefln("swapchainPresentMode: %s", swapchainPresentMode);
        
        uint desiredNumberOfSwapchainImages = surfCapabilities.minImageCount + 1;
        if ((surfCapabilities.maxImageCount > 0) &&
            (desiredNumberOfSwapchainImages > surfCapabilities.maxImageCount))
        {
            desiredNumberOfSwapchainImages = surfCapabilities.maxImageCount;
        }
        
        version(VulkanDebug) writefln("desiredNumberOfSwapchainImages: %s", desiredNumberOfSwapchainImages);
        
        VkSurfaceTransformFlagBitsKHR pTransform;
        if (surfCapabilities.supportedTransforms &
            VkSurfaceTransformFlagBitsKHR.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR)
        {
            pTransform = VkSurfaceTransformFlagBitsKHR.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
        }
        else
        {
            pTransform = surfCapabilities.currentTransform;
        }
        
        version(VulkanDebug) writefln("pTransform: %s", pTransform);
        
        VkSwapchainCreateInfoKHR swapchainInfo = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            pNext: null,
            surface: surface,
            minImageCount: desiredNumberOfSwapchainImages,
            imageFormat: format,
            imageColorSpace: color_space,
            imageExtent:
            {
                width: swapchainExtent.width,
                height: swapchainExtent.height
            },
            imageUsage: VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            preTransform: pTransform,
            compositeAlpha: VkCompositeAlphaFlagBitsKHR.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            imageArrayLayers: 1,
            imageSharingMode: VkSharingMode.VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount: 0,
            pQueueFamilyIndices: null,
            presentMode: swapchainPresentMode,
            oldSwapchain: oldSwapchain,
            clipped: true
        };
        
        res = vkCreateSwapchainKHR(device, &swapchainInfo, null, &swapchain);
        assert(res == VkResult.VK_SUCCESS);
        
        if (oldSwapchain != VK_NULL_HANDLE)
        {
            vkDestroySwapchainKHR(device, oldSwapchain, null);
        }
        
        res = vkGetSwapchainImagesKHR(device, swapchain, &swapchainImageCount, null);
        assert(res == VkResult.VK_SUCCESS);
        
        version(VulkanDebug) writefln("swapchainImageCount: %s", swapchainImageCount);
        
        VkImage[] swapchainImages = new VkImage[swapchainImageCount];
        res = vkGetSwapchainImagesKHR(device, swapchain, &swapchainImageCount, swapchainImages.ptr);
        assert(res == VkResult.VK_SUCCESS);
        
        buffers = new SwapchainBuffers[swapchainImageCount];
        
        for (size_t i = 0; i < swapchainImageCount; i++)
        {
            VkImageViewCreateInfo color_image_view =
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                pNext: null,
                format: this.format,
                components:
                {
                    r: VkComponentSwizzle.VK_COMPONENT_SWIZZLE_R,
                    g: VkComponentSwizzle.VK_COMPONENT_SWIZZLE_G,
                    b: VkComponentSwizzle.VK_COMPONENT_SWIZZLE_B,
                    a: VkComponentSwizzle.VK_COMPONENT_SWIZZLE_A
                },
                subresourceRange: 
                {
                    aspectMask: VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT,
                    baseMipLevel: 0,
                    levelCount: 1,
                    baseArrayLayer: 0,
                    layerCount: 1
                },
                viewType: VkImageViewType.VK_IMAGE_VIEW_TYPE_2D,
                flags: 0
            };

            buffers[i].image = swapchainImages[i];

            setImageLayout(
                buffers[i].image, 
                VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT, 
                VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED,
                VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

            color_image_view.image = buffers[i].image;

            res = vkCreateImageView(device, &color_image_view, null, &buffers[i].view);
            assert(res == VkResult.VK_SUCCESS);
        }
    }
    
    void prepareDepth()
    {
        VkFormat depth_format = VkFormat.VK_FORMAT_D16_UNORM;
        
        VkImageCreateInfo imageInfo = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            pNext: null,
            imageType: VkImageType.VK_IMAGE_TYPE_2D,
            format: depth_format,
            extent: {windowWidth, windowHeight, 1},
            mipLevels: 1,
            arrayLayers: 1,
            samples: VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT,
            tiling: VkImageTiling.VK_IMAGE_TILING_OPTIMAL,
            usage: VkImageUsageFlagBits.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            flags: 0
        };
        
        VkImageViewCreateInfo viewInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            pNext: null,
            image: VK_NULL_HANDLE,
            format: depth_format,
            subresourceRange:
            {
                aspectMask: VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT,
                baseMipLevel: 0,
                levelCount: 1,
                baseArrayLayer: 0,
                layerCount: 1
            },
            flags: 0,
            viewType: VkImageViewType.VK_IMAGE_VIEW_TYPE_2D
        };
        
        VkMemoryRequirements mem_reqs;
        VkResult res;
        bool pass;
        
        depth.format = depth_format;
        
        res = vkCreateImage(device, &imageInfo, null, &depth.image);
        assert(res == VkResult.VK_SUCCESS);
        
        vkGetImageMemoryRequirements(device, depth.image, &mem_reqs);        
        depth.mem_alloc.allocationSize = mem_reqs.size;
        
        pass = memoryTypeFromProperties(mem_reqs.memoryTypeBits, 0, &depth.mem_alloc.memoryTypeIndex);
        assert(pass);
        
        res = vkAllocateMemory(device, &depth.mem_alloc, null, &depth.mem);
        assert(res == VkResult.VK_SUCCESS);
        
        res = vkBindImageMemory(device, depth.image, depth.mem, 0);
        assert(res == VkResult.VK_SUCCESS);
        
        setImageLayout(depth.image,
            VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT,
            VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED,
            VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
            
        viewInfo.image = depth.image;
        res = vkCreateImageView(device, &viewInfo, null, &depth.view);
        assert(res == VkResult.VK_SUCCESS);
    }
    
    void prepareTextures()
    {
    }
    
    void prepareCubeDataBuffer()
    {
    /*
        VkBufferCreateInfo buf_info;
        VkMemoryRequirements mem_reqs;
        
        ubyte* pData;
    */
    }
    
    void prepareDescriptorLayout()
    {
    /*
        VkDescriptorSetLayoutBinding[2] layout_bindings =
        [
            {
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: VK_SHADER_STAGE_VERTEX_BIT,
                pImmutableSamplers: null
            },
            {
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1, //DEMO_TEXTURE_COUNT
                stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,
                pImmutableSamplers: null
            }
        ];
    */
    
        VkDescriptorSetLayoutCreateInfo descriptor_layout = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            pNext: null,
            bindingCount: 0, //2,
            pBindings: null  // layout_bindings.ptr,
        };
        
        auto res = vkCreateDescriptorSetLayout(device, &descriptor_layout, null, &desc_layout);
        assert(res == VkResult.VK_SUCCESS);
        
        VkPipelineLayoutCreateInfo pPipelineLayoutCreateInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            pNext: null,
            setLayoutCount: 1,
            pSetLayouts: &desc_layout,
        };
        
        res = vkCreatePipelineLayout(device, &pPipelineLayoutCreateInfo, null, &pipeline_layout);
        assert(res == VkResult.VK_SUCCESS);
    }
    
    void prepareRenderPass()
    {
        VkAttachmentDescription[3] attachments =
        [
            {
                format: this.format,
                samples: VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT,
                loadOp: VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR,
                storeOp: VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE,
                stencilLoadOp: VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                stencilStoreOp: VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                initialLayout: VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                finalLayout: VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
            },
            {
                format: depth.format,
                samples: VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT,
                loadOp: VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR,
                storeOp: VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                stencilLoadOp: VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                stencilStoreOp: VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                initialLayout: VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                finalLayout: VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            }
        ];
        
        VkAttachmentReference color_reference =
        {
            attachment: 0, 
            layout: VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        };
        
        VkAttachmentReference depth_reference =
        {
            attachment: 1,
            layout: VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        };
        
        VkSubpassDescription subpass =
        {
            pipelineBindPoint: VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS,
            flags: 0,
            inputAttachmentCount: 0,
            pInputAttachments: null,
            colorAttachmentCount: 1,
            pColorAttachments: &color_reference,
            pResolveAttachments: null,
            pDepthStencilAttachment: &depth_reference,
            preserveAttachmentCount: 0,
            pPreserveAttachments: null,
        };
        
        VkRenderPassCreateInfo rp_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            pNext: null,
            attachmentCount: 2,
            pAttachments: attachments.ptr,
            subpassCount: 1,
            pSubpasses: &subpass,
            dependencyCount: 0,
            pDependencies: null,
        };
        
        VkResult res = vkCreateRenderPass(device, &rp_info, null, &render_pass);
        assert(res == VkResult.VK_SUCCESS);
    }
    
    void preparePipeline()
    {
        VkDynamicState[VkDynamicState.VK_DYNAMIC_STATE_RANGE_SIZE] dynamicStateEnables;
        foreach(ref s; dynamicStateEnables)
            s = cast(VkDynamicState)0;
        
        VkPipelineDynamicStateCreateInfo dynamicState = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            dynamicStateCount: 0,
            pDynamicStates: dynamicStateEnables.ptr
        };
        
        VkPipelineVertexInputStateCreateInfo vi = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            vertexBindingDescriptionCount: 0,
            pVertexBindingDescriptions: null,
            vertexAttributeDescriptionCount: 0,
            pVertexAttributeDescriptions: null
        };
        
        VkPipelineInputAssemblyStateCreateInfo ia =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            topology: VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: false
        };
        
        VkPipelineRasterizationStateCreateInfo rs = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            depthClampEnable: false,
            rasterizerDiscardEnable: false,
            polygonMode: VkPolygonMode.VK_POLYGON_MODE_FILL,
            cullMode: VkCullModeFlagBits.VK_CULL_MODE_BACK_BIT,
            frontFace: VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            depthBiasEnable: false,
            depthBiasConstantFactor: 0.0f,
            depthBiasClamp: 0.0f,
            depthBiasSlopeFactor: 0.0f,
            lineWidth: 1.0f
        };
        
        VkPipelineColorBlendAttachmentState att_state;
        att_state.colorWriteMask = 0;
        att_state.blendEnable = false;
        
        VkPipelineColorBlendStateCreateInfo cb =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            logicOpEnable: false,
            logicOp: VkLogicOp.VK_LOGIC_OP_CLEAR,
            attachmentCount: 1,
            pAttachments: &att_state,
            blendConstants: [0.0f, 0.0f, 0.0f, 0.0f]
        };
        
        VkPipelineViewportStateCreateInfo vp = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            viewportCount: 1,
            pViewports: null,
            scissorCount: 1,
            pScissors: null
        };
        
        dynamicStateEnables[dynamicState.dynamicStateCount++] = VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT;
        dynamicStateEnables[dynamicState.dynamicStateCount++] = VkDynamicState.VK_DYNAMIC_STATE_SCISSOR;
        
        VkPipelineDepthStencilStateCreateInfo ds = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            depthTestEnable: true,
            depthWriteEnable: true,
            depthCompareOp: VkCompareOp.VK_COMPARE_OP_LESS_OR_EQUAL,
            depthBoundsTestEnable: false,
            stencilTestEnable: true,
            front:
            {
                failOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                passOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                depthFailOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                compareOp: VkCompareOp.VK_COMPARE_OP_ALWAYS,
                compareMask: 0,
                writeMask: 0,
                reference: 0
            },
            back: 
            {
                failOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                passOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                depthFailOp: VkStencilOp.VK_STENCIL_OP_KEEP,
                compareOp: VkCompareOp.VK_COMPARE_OP_ALWAYS,
                compareMask: 0,
                writeMask: 0,
                reference: 0
            },
            minDepthBounds: 0.0f,
            maxDepthBounds: 0.0f
        };
        
        VkPipelineMultisampleStateCreateInfo ms =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            pNext: null,
            flags: 0,
            rasterizationSamples: VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT,
            sampleShadingEnable: false,
            minSampleShading: 0.0f,
            pSampleMask: null,
            alphaToCoverageEnable: false,
            alphaToOneEnable: false
        };
        
        string mainStr = "main";
        auto mainStrPtr = toStringz(mainStr);
        
        vsModule = loadShader("vert.spv");
        fsModule = loadShader("frag.spv");
        
        VkPipelineShaderStageCreateInfo[2] shaderStages =
        [
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                pNext: null,
                flags: 0,
                stage: VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT,
                module_: vsModule,
                pName: mainStrPtr,
                pSpecializationInfo: null
            },
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                pNext: null,
                flags: 0,
                stage: VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT,
                module_: fsModule,
                pName: mainStrPtr,
                pSpecializationInfo: null
            }
        ];
        
        VkPipelineCacheCreateInfo pipelineCacheInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
            pNext: null,
            flags: 0,
            initialDataSize: 0,
            pInitialData: null
        };
        
        auto res = vkCreatePipelineCache(device, &pipelineCacheInfo, null, &pipelineCache);
        assert(res == VkResult.VK_SUCCESS);
   
        VkGraphicsPipelineCreateInfo pipelineInfo = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            pNext: null,
            flags: 0,
            stageCount: 2, //vs and fs
            pStages: shaderStages.ptr,
            pVertexInputState: &vi,
            pInputAssemblyState: &ia,
            pTessellationState: null,
            pViewportState: &vp,
            pRasterizationState: &rs,
            pMultisampleState: &ms,
            pDepthStencilState: &ds,
            pColorBlendState: &cb,
            pDynamicState: &dynamicState,
            layout: pipeline_layout,
            renderPass: render_pass,
            subpass: 0,
            basePipelineHandle: VK_NULL_HANDLE,
            basePipelineIndex: 0
        };
        
        res = vkCreateGraphicsPipelines(device, pipelineCache, 1, &pipelineInfo, null, &pipeline);
        assert(res == VkResult.VK_SUCCESS);
    }
    
    void prepareDescriptorPool()
    {
        VkDescriptorPoolSize[2] type_counts =
        [
            {
                type: VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 0 //VERTEX_BUFFERS_COUNT
            },
            {
                type: VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 0 //DEMO_TEXTURE_COUNT
            }
        ];
        
        VkDescriptorPoolCreateInfo descriptor_pool =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            pNext: null,
            maxSets: 1,
            poolSizeCount: 2,
            pPoolSizes: type_counts.ptr
        };
        
        auto res = vkCreateDescriptorPool(device, &descriptor_pool, null, &desc_pool);
        assert(res == VkResult.VK_SUCCESS);
    }
    
    void prepareDescriptorSet()
    {
        //VkDescriptorImageInfo tex_descs[DEMO_TEXTURE_COUNT];
        /*
        memset(&tex_descs, 0, sizeof(tex_descs));
        for (i = 0; i < DEMO_TEXTURE_COUNT; i++) {
            tex_descs[i].sampler = demo->textures[i].sampler;
            tex_descs[i].imageView = demo->textures[i].view;
            tex_descs[i].imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        }
        */
        /*
        VkWriteDescriptorSet[2] writes = 
        [
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                pNext: null,
                dstSet: desc_set,
                dstBinding: 0,
                dstArrayElement: 0,
                descriptorCount: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                pImageInfo: null,
                pBufferInfo: //
                pTexelBufferView: null
            },
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                pNext: null,
                dstSet: desc_set,
                dstBinding: 0,
                dstArrayElement: 0,
                descriptorCount: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                pImageInfo: //,
                pBufferInfo: null,
                pTexelBufferView: null
            }
        ];
        */
        
        VkDescriptorSetAllocateInfo alloc_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            pNext: null,
            descriptorPool: desc_pool,
            descriptorSetCount: 1,
            pSetLayouts: &desc_layout
        };
        
        auto res = vkAllocateDescriptorSets(device, &alloc_info, &desc_set);
        assert(res == VkResult.VK_SUCCESS);
        
        //vkUpdateDescriptorSets(device, 2, writes, 0, null);
    }
    
    void prepareFramebuffers()
    {
        VkImageView[2] attachments;
        attachments[1] = depth.view;

        VkFramebufferCreateInfo fb_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            pNext: null,
            renderPass: render_pass,
            attachmentCount: 2,
            pAttachments: attachments.ptr,
            width: windowWidth,
            height: windowHeight,
            layers: 1,
        };

        framebuffers = new VkFramebuffer[swapchainImageCount];

        for (uint i = 0; i < swapchainImageCount; i++)
        {
            attachments[0] = buffers[i].view;
            auto res = vkCreateFramebuffer(device, &fb_info, null, &framebuffers[i]);
            assert(res == VkResult.VK_SUCCESS);
        }
    }
    
    VkShaderModule prepareShaderModule(const void* code, size_t size)
    {
        VkShaderModule _module;
        VkShaderModuleCreateInfo moduleCreateInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            pNext: null,
            flags: 0,
            codeSize: size,
            pCode: cast(uint*)code
        };
    
        auto res = vkCreateShaderModule(device, &moduleCreateInfo, null, &_module);
        assert(res == VkResult.VK_SUCCESS);

        return _module;
    }
    
    VkShaderModule loadShader(string filename)
    {
        size_t size = cast(size_t)getSize(filename);
        ubyte[] data = cast(ubyte[])std.file.read(filename);
        void* vertShaderCode = data.ptr;
        return prepareShaderModule(vertShaderCode, size);
    }
    
    void setImageLayout(VkImage img,
                        VkImageAspectFlagBits aspectMask,
                        VkImageLayout old_image_layout,
                        VkImageLayout new_image_layout)
    {
        VkResult res;
        
        if (cmd is null)
        {
            VkCommandBufferAllocateInfo cmdInfo = 
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                pNext: null,
                commandPool: cmd_pool,
                level: VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                commandBufferCount: 1
            };
            
            res = vkAllocateCommandBuffers(device, &cmdInfo, &cmd);
            assert(res == VkResult.VK_SUCCESS);
            
            VkCommandBufferInheritanceInfo cmd_buf_hinfo = 
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
                pNext: null,
                renderPass: VK_NULL_HANDLE,
                subpass: 0,
                framebuffer: VK_NULL_HANDLE,
                occlusionQueryEnable: VK_FALSE,
                queryFlags: 0,
                pipelineStatistics: 0
            };
            
            VkCommandBufferBeginInfo cmd_buf_info =
            {
                sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                pNext: null,
                flags: 0,
                pInheritanceInfo: &cmd_buf_hinfo
            };
            
            res = vkBeginCommandBuffer(cmd, &cmd_buf_info);
            assert(res == VkResult.VK_SUCCESS);
        }
        
        VkImageMemoryBarrier image_memory_barrier =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            pNext: null,
            srcAccessMask: 0,
            dstAccessMask: 0,
            oldLayout: old_image_layout,
            newLayout: new_image_layout,
            image: img,
            subresourceRange: {aspectMask, 0, 1, 0, 1}
        };
       
    
        if (new_image_layout == VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
            image_memory_barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_READ_BIT;
            
        if (new_image_layout == VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
            image_memory_barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            
        if (new_image_layout == VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
            image_memory_barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
            
        if (new_image_layout == VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
            image_memory_barrier.dstAccessMask =
                VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT | 
                VkAccessFlagBits.VK_ACCESS_INPUT_ATTACHMENT_READ_BIT;
                
        VkImageMemoryBarrier* pmemory_barrier = &image_memory_barrier;
        
        VkPipelineStageFlags src_stages = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        VkPipelineStageFlags dest_stages = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        
        vkCmdPipelineBarrier(cmd, src_stages, dest_stages, 0, 0, null, 0, null, 1, pmemory_barrier);
    }
    
    bool memoryTypeFromProperties(uint typeBits, VkFlags requirements_mask, uint* typeIndex)
    {
        // Search memtypes to find first index with those properties
        for (uint i = 0; i < 32; i++)
        {
            if ((typeBits & 1) == 1)
            {
                // Type is available, does it match user properties?
                if ((memory_properties.memoryTypes[i].propertyFlags & requirements_mask) == requirements_mask)
                {
                    *typeIndex = i;
                    return true;
                }
            }
            typeBits >>= 1;
        }
        // No memory types matched, return failure
        return false;
    }
    
    void drawBuildCmd(VkCommandBuffer cmd_buf)
    {
        VkCommandBufferInheritanceInfo cmd_buf_hinfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
            pNext: null,
            renderPass: VK_NULL_HANDLE,
            subpass: 0,
            framebuffer: VK_NULL_HANDLE,
            occlusionQueryEnable: false,
            queryFlags: 0,
            pipelineStatistics: 0
        };
        
        const VkCommandBufferBeginInfo cmd_buf_info = 
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            pNext: null,
            flags: 0,
            pInheritanceInfo: &cmd_buf_hinfo
        };
        
        VkClearValue[2] clear_values;
        clear_values[0].color.float32 = [0.0f, 0.0f, 0.2f, 1.0f]; // clear color
        clear_values[1].depthStencil = VkClearDepthStencilValue(1.0f, 0); // clear depth
        
        VkRenderPassBeginInfo rp_begin =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            pNext: null,
            renderPass: render_pass,
            framebuffer: framebuffers[current_buffer],
            renderArea:
            {
                offset: {x: 0, y: 0},
                extent: {width: windowWidth, height: windowHeight}
            },
            clearValueCount: 2,
            pClearValues: clear_values.ptr
        };
        
        auto res = vkBeginCommandBuffer(cmd_buf, &cmd_buf_info);
        assert(res == VkResult.VK_SUCCESS); 
        
        vkCmdBeginRenderPass(cmd_buf, &rp_begin, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);
        
        vkCmdBindPipeline(cmd_buf, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdBindDescriptorSets(cmd_buf, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_layout, 0, 1, &desc_set, 0, null);

        VkViewport viewport =
        {
            x: 0.0f,
            y: 0.0f,
            width: windowWidth,
            height: windowHeight,
            minDepth: 0.0f,
            maxDepth: 0.0f
        };
        
        vkCmdSetViewport(cmd_buf, 0, 1, &viewport);
        
        VkRect2D scissor = 
        {
            offset: {x: 0, y: 0},
            extent: {width: windowWidth, height: windowHeight}
        };
        
        vkCmdSetScissor(cmd_buf, 0, 1, &scissor);
        
        vkCmdDraw(cmd_buf, 12 * 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd_buf);

        VkImageMemoryBarrier prePresentBarrier =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            pNext: null,
            srcAccessMask: VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            dstAccessMask: VkAccessFlagBits.VK_ACCESS_MEMORY_READ_BIT,
            oldLayout: VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            newLayout: VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            image: buffers[current_buffer].image,
            subresourceRange: 
            {
                aspectMask: VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT, 
                baseMipLevel: 0, 
                levelCount: 1, 
                baseArrayLayer: 0, 
                layerCount: 1
            }
        };
        
        VkImageMemoryBarrier* pmemory_barrier = &prePresentBarrier;
        
        vkCmdPipelineBarrier(cmd_buf, 
            VkPipelineStageFlagBits.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
            VkPipelineStageFlagBits.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 
            0, 0, null, 0, null, 1, pmemory_barrier);

        res = vkEndCommandBuffer(cmd_buf);
        assert(res == VkResult.VK_SUCCESS); 
    }
    
    void flushInitCmd()
    {
        if (cmd is null)
            return;

        auto res = vkEndCommandBuffer(cmd);
        assert(res == VkResult.VK_SUCCESS); 

        VkCommandBuffer[1] cmd_bufs = [cmd];
        VkFence nullFence = VK_NULL_HANDLE;
        VkSubmitInfo submit_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext: null,
            waitSemaphoreCount: 0,
            pWaitSemaphores: null,
            pWaitDstStageMask: null,
            commandBufferCount: 1,
            pCommandBuffers: cmd_bufs.ptr,
            signalSemaphoreCount: 0,
            pSignalSemaphores: null
        };

        res = vkQueueSubmit(queue, 1, &submit_info, nullFence);
        assert(res == VkResult.VK_SUCCESS); 

        res = vkQueueWaitIdle(queue);
        assert(res == VkResult.VK_SUCCESS); 

        vkFreeCommandBuffers(device, cmd_pool, 1, cmd_bufs.ptr);
        cmd = null;
    }

    void render()
    {            
        if (!vulkanInitialized)
            return;
            
        vkDeviceWaitIdle(device);
        
        updateDataBuffer();
        draw();
        
        vkDeviceWaitIdle(device);
        
        curFrame++;
        /*
        if (app.frameCount != INT_MAX && 
            app.curFrame == app.frameCount)
        {
            app.quit = true;
            //demo_cleanup(demo);
            //ExitProcess(0);
        }
        */
    }
    
    void updateDataBuffer()
    {
        //mat4x4 MVP, Model, VP;
        //int matrixSize = sizeof(MVP);
        //uint8_t *pData;
        //mat4x4_mul(VP, demo->projection_matrix, demo->view_matrix);

        // Rotate 22.5 degrees around the Y axis
        //mat4x4_dup(Model, demo->model_matrix);
        //mat4x4_rotate(demo->model_matrix, Model, 0.0f, 1.0f, 0.0f,
        //   (float)degreesToRadians(demo->spin_angle));
        //mat4x4_mul(MVP, VP, demo->model_matrix);

        //err = vkMapMemory(demo->device, demo->uniform_data.mem, 0,
        //              demo->uniform_data.mem_alloc.allocationSize, 0,
        //              (void **)&pData);
        //assert(!err);

        //memcpy(pData, (const void *)&MVP[0][0], matrixSize);

        //vkUnmapMemory(demo->device, demo->uniform_data.mem);
    }
    
    void draw()
    {
        VkSemaphore presentCompleteSemaphore;
        VkSemaphoreCreateInfo presentCompleteSemaphoreCreateInfo =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            pNext: null,
            flags: 0
        };
        
        VkFence nullFence = VK_NULL_HANDLE;
        
        auto res = vkCreateSemaphore(device, 
            &presentCompleteSemaphoreCreateInfo, null, &presentCompleteSemaphore);
        assert(res == VkResult.VK_SUCCESS); 
        
        res = vkAcquireNextImageKHR(device, swapchain, ulong.max,
            presentCompleteSemaphore,
            cast(VkFence)0, // TODO: Show use of fence
            &current_buffer);
        if (res == VkResult.VK_ERROR_OUT_OF_DATE_KHR)
        {
            // demo->swapchain is out of date (e.g. the window was resized) and
            // must be recreated:
            //demo_resize(demo);
            //demo_draw(demo);
            //vkDestroySemaphore(demo->device, presentCompleteSemaphore, NULL);
            return;
        }
        else if (res == VkResult.VK_SUBOPTIMAL_KHR)
        {
            // demo->swapchain is not as optimal as it could be, but the platform's
            // presentation engine will still present the image correctly.
        }
        else 
        {
            assert(res == VkResult.VK_SUCCESS); 
        }
        
        setImageLayout(buffers[current_buffer].image,
            VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT,
            VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
            
        flushInitCmd();
        
        VkPipelineStageFlags pipe_stage_flags = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        
        VkSubmitInfo submit_info =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext: null,
            waitSemaphoreCount: 1,
            pWaitSemaphores: &presentCompleteSemaphore,
            pWaitDstStageMask: &pipe_stage_flags,
            commandBufferCount: 1,
            pCommandBuffers: &buffers[current_buffer].cmd,
            signalSemaphoreCount: 0,
            pSignalSemaphores: null
        };
        
        res = vkQueueSubmit(queue, 1, &submit_info, nullFence);
        assert(res == VkResult.VK_SUCCESS); 
        
        VkPresentInfoKHR present =
        {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            pNext: null,
            swapchainCount: 1,
            pSwapchains: &swapchain,
            pImageIndices: &current_buffer,
        };
        
        res = vkQueuePresentKHR(queue, &present);
        if (res == VkResult.VK_ERROR_OUT_OF_DATE_KHR)
        {
            // demo->swapchain is out of date (e.g. the window was resized) and
            // must be recreated:
            // TODO:
            // demo_resize(demo);
        }
        else if (res == VkResult.VK_SUBOPTIMAL_KHR)
        {
            // demo->swapchain is not as optimal as it could be, but the platform's
            // presentation engine will still present the image correctly.
        }
        else
        {
            assert(res == VkResult.VK_SUCCESS); 
        }
        
        res = vkQueueWaitIdle(queue);
        assert(res == VkResult.VK_SUCCESS); 
        
        vkDestroySemaphore(device, presentCompleteSemaphore, null);
    }
    
    void deinit()
    {
        vulkanInitialized = false;
        
        for (size_t i = 0; i < swapchainImageCount; i++)
        {
            vkDestroyFramebuffer(device, framebuffers[i], null);
        }
        
        vkDestroyDescriptorPool(device, desc_pool, null);
        
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineCache(device, pipelineCache, null);
        vkDestroyRenderPass(device, render_pass, null);
        vkDestroyPipelineLayout(device, pipeline_layout, null);
        vkDestroyDescriptorSetLayout(device, desc_layout, null);
        
        //Delete textures here
        
        vkDestroySwapchainKHR(device, swapchain, null);
        
        vkDestroyImageView(device, depth.view, null);
        vkDestroyImage(device, depth.image, null);
        vkFreeMemory(device, depth.mem, null);

        //vkDestroyBuffer(device, uniform_data.buf, null);
        //vkFreeMemory(device, uniform_data.mem, null);

        for (size_t i = 0; i < swapchainImageCount; i++)
        {
            vkDestroyImageView(device, buffers[i].view, null);
            vkFreeCommandBuffers(device, cmd_pool, 1, &buffers[i].cmd);
        }
        
        vkDestroyCommandPool(device, cmd_pool, null);
        vkDestroyDevice(device, null);

        vkDestroySurfaceKHR(inst, surface, null);
        vkDestroyInstance(inst, null);
    }
}
