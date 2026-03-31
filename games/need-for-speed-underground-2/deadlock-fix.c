/*
 * DeadlockFix ASI mod for NFS Underground 2
 *
 * The game has an AB-BA deadlock between two critical sections during
 * track loading (discovered via GDB + Wine +server trace):
 *   Thread A: holds CS@00864F00, waits for heap CS (held by Thread B)
 *   Thread B: holds heap CS, waits for CS@00864F00 (held by Thread A)
 *
 * This ASI hooks EnterCriticalSection via the game's IAT and applies
 * a 3-second timeout ONLY to CS@00864F00. If the timeout expires
 * (indicating deadlock), it returns without acquiring, allowing the
 * other thread to proceed and break the deadlock.
 *
 * All other critical sections use the original blocking behavior.
 *
 * Loaded by the game's ASI loader (dinput8.dll) from the SCRIPTS directory.
 */
#include <windows.h>

static void (WINAPI *pRealEnterCS)(CRITICAL_SECTION*) = NULL;

void WINAPI HookedEnterCriticalSection(CRITICAL_SECTION *cs) {
    int i;
    if ((DWORD)cs == 0x00864F00) {
        for (i = 0; i < 3000; i++) {
            if (TryEnterCriticalSection(cs))
                return;
            Sleep(1);
        }
        return;
    }
    pRealEnterCS(cs);
}

BOOL __stdcall _DllMainCRTStartup(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        DWORD *iat_entry = (DWORD *)0x007831a8;
        DWORD oldProtect;
        VirtualProtect(iat_entry, 4, PAGE_READWRITE, &oldProtect);
        pRealEnterCS = (void*)(*iat_entry);
        *iat_entry = (DWORD)HookedEnterCriticalSection;
        VirtualProtect(iat_entry, 4, oldProtect, &oldProtect);
    }
    return TRUE;
}
