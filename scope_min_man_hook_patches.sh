#!/bin/bash
# scope-min manual hook 1.6 patch script
# Patch author: backslashxx @ Github / OmarAlsmehan
# Script style: JackA1ltman <cs2dtzq@163.com>
# Based on: scope-min-manual-hook_1_6-5_4.patch
# Tested kernel versions: 5.4+
# 20260320

patch_files=(
    drivers/input/input.c
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    kernel/reboot.c
)

PATCH_LEVEL="1.6"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Current scope-min hook patch version: $PATCH_LEVEL"
echo "Detected kernel version: $KERNEL_VERSION"

for i in "${patch_files[@]}"; do

    if grep -q "ksu_handle\|ksu_input_hook\|ksu_vfs_read_hook" "$i"; then
        echo "[-] Warning: $i already contains KernelSU hooks"
        echo "[+] Code in here:"
        grep -n "ksu_handle\|ksu_input_hook\|ksu_vfs_read_hook" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    fi

    case $i in

    # drivers/input/input.c
    drivers/input/input.c)
        echo "======================================"

        # Declaration: insert before void input_event(...)
        sed -i '/^void input_event(struct input_dev \*dev,/i\
\
#ifdef CONFIG_KSU\
extern bool ksu_input_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_input_handle_event(\
\t\t\tunsigned int *type, unsigned int *code, int *value);\
#endif\
' drivers/input/input.c

        # Hook call: insert after "unsigned long flags;" (first occurrence = input_event)
        sed -i '0,/\tunsigned long flags;/{s/\tunsigned long flags;/\tunsigned long flags;\n\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_input_hook))\n\t\tksu_handle_input_handle_event(\&type, \&code, \&value);\n#endif\n/}' drivers/input/input.c

        if grep -q "ksu_handle_input_handle_event" "drivers/input/input.c"; then
            echo "[+] drivers/input/input.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_input_handle_event" "drivers/input/input.c")"
        else
            echo "[-] drivers/input/input.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # fs/exec.c
    fs/exec.c)
        echo "======================================"

        # Declaration: insert before int do_execve(...)
        sed -i '/^int do_execve(struct filename \*filename,/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
\t\t\t\tvoid *argv, void *envp, int *flags);\
#endif\
' fs/exec.c

        # Hook call: insert before return do_execveat_common(...)
        sed -i '/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\
#ifdef CONFIG_KSU\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\
#endif\
' fs/exec.c

        if grep -q "ksu_handle_execveat" "fs/exec.c"; then
            echo "[+] fs/exec.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_execveat" "fs/exec.c")"
        else
            echo "[-] fs/exec.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # fs/open.c
    fs/open.c)
        echo "======================================"

        # Declaration: insert before SYSCALL_DEFINE3(faccessat, ...)
        sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *mode, int *flags);\
#endif\
' fs/open.c

        # Hook call: insert before return do_faccessat(...) (kernel >= 5.x)
        # For older kernels that don't have do_faccessat, fall back to if (mode & ~S_IRWXO)
        if grep -q "return do_faccessat(dfd, filename, mode);" "fs/open.c"; then
            sed -i '/return do_faccessat(dfd, filename, mode);/i\
 #ifdef CONFIG_KSU\
    ksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
 #endif\
' fs/open.c
        else
            sed -i '/if (mode & ~S_IRWXO)/i \
#ifdef CONFIG_KSU\
\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif\
' fs/open.c
        fi

        if grep -q "ksu_handle_faccessat" "fs/open.c"; then
            echo "[+] fs/open.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_faccessat" "fs/open.c")"
        else
            echo "[-] fs/open.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # fs/read_write.c
    fs/read_write.c)
        echo "======================================"

        # Declaration: insert before SYSCALL_DEFINE3(read, ...)
        sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\
\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\
#endif\
' fs/read_write.c

        # Hook call: insert before return ksys_read(...) (kernel >= 5.x)
        # For older kernels (< 4.19) that don't have ksys_read, fall back to if (f.file)
        if grep -q "return ksys_read(fd, buf, count);" "fs/read_write.c"; then
            sed -i '/return ksys_read(fd, buf, count);/i\
#ifdef CONFIG_KSU\
\tif (unlikely(ksu_vfs_read_hook))\
\t\tksu_handle_sys_read(fd, \&buf, \&count);\
#endif\
' fs/read_write.c
        else
            sed -i '0,/if (f\.file) {/{s/if (f\.file) {/\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, \&buf, \&count);\n#endif\n\tif (f.file) {/}' fs/read_write.c
        fi

        if grep -q "ksu_handle_sys_read" "fs/read_write.c"; then
            echo "[+] fs/read_write.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_sys_read" "fs/read_write.c")"
        else
            echo "[-] fs/read_write.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # fs/stat.c
    fs/stat.c)
        echo "======================================"

        # Declaration: insert before #if !defined(__ARCH_WANT_STAT64) ...
        sed -i '/#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *flags);\
#endif\
' fs/stat.c

        # Hook call: insert before error = vfs_fstatat(...)
        sed -i '/error = vfs_fstatat(dfd, filename, \&stat, flag);/i\
#ifdef CONFIG_KSU\
\tksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif\
' fs/stat.c

        if grep -q "ksu_handle_stat" "fs/stat.c"; then
            echo "[+] fs/stat.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_stat" "fs/stat.c")"
        else
            echo "[-] fs/stat.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # kernel/reboot.c
    kernel/reboot.c)
        echo "======================================"

        # Declaration: insert before SYSCALL_DEFINE4(reboot, ...)
        sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\
\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif\
' kernel/reboot.c

        # Hook call: insert before if (!ns_capable(...))
        sed -i '/if (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))/i\
#ifdef CONFIG_KSU\
\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif\
' kernel/reboot.c

        if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
            echo "[+] kernel/reboot.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
        else
            echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    esac

done
