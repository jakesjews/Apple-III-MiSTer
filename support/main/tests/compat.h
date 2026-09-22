#ifdef __APPLE__
#define reboot host_reboot
#include <unistd.h>
#undef reboot
#define __off64_t off_t
#endif
