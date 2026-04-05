#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/drm.h>
#include <linux/drm_mode.h>
#include <string.h>
#include <sys/mman.h>

/*
 * KWin DRM/GBM Hook for NVIDIA Allocator in Non-Privileged Containers
 * This intercepts gbm_create_device() and reroutes DRM Master requests to a Render Node.
 */

struct gbm_device;

static struct gbm_device* (*real_gbm_create_device)(int fd) = NULL;

struct gbm_device* gbm_create_device(int fd) {
    if (!real_gbm_create_device) {
        real_gbm_create_device = dlsym(RTLD_NEXT, "gbm_create_device");
    }
    
    // Check if the fd is the card0 node which requires DRM Master
    char fd_path[1024] = {0};
    sprintf(fd_path, "/proc/self/fd/%d", fd);
    char device_path[1024] = {0};
    readlink(fd_path, device_path, sizeof(device_path)-1);
    
    if (strstr(device_path, "/dev/dri/card") != NULL) {
        // Find the corresponding render node
        int render_fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
        if (render_fd >= 0) {
            printf("[DRM HOOK] Intercepted gbm_create_device(fd=%d, path=%s), re-routing to renderD128(fd=%d) for native NVIDIA allocator!\n", fd, device_path, render_fd);
            return real_gbm_create_device(render_fd);
        } else {
            printf("[DRM HOOK] WARNING: Intercepted gbm_create_device for %s, but failed to open /dev/dri/renderD128\n", device_path);
        }
    }
    
    return real_gbm_create_device(fd);
}
