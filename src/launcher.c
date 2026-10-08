/* SPDX-License-Identifier: MIT */
/* Pair this entry with metadata normalized for the installed game version. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef int (WINAPI *UnityMainFunction)(HINSTANCE, HINSTANCE, LPWSTR, int);
extern IMAGE_DOS_HEADER __ImageBase;

int WINAPI launcher_entry(void)
{
    HMODULE unity = LoadLibraryExA("UnityPlayer.dll", NULL, 0);
    if (unity == NULL)
        return 1;
    union {
        FARPROC address;
        UnityMainFunction function;
    } entry;
    entry.address = GetProcAddress(unity, "UnityMain");
    if (entry.address == NULL)
        return 1;
    LPWSTR command = GetCommandLineW();
    BOOL quoted = FALSE;
    while (*command != L'\0' && (quoted || *command > L' ')) {
        if (*command == L'\"')
            quoted = !quoted;
        ++command;
    }
    while (*command != L'\0' && *command <= L' ')
        ++command;
    return entry.function((HINSTANCE)&__ImageBase, NULL, command, SW_SHOWDEFAULT);
}
