#include <windows.h>
#include <tlhelp32.h>

static DWORD find_pid(const char *exe)
{
    PROCESSENTRY32 entry;
    DWORD pid = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (snap == INVALID_HANDLE_VALUE)
        return 0;

    entry.dwSize = sizeof entry;
    if (Process32First(snap, &entry)) {
        do {
            if (lstrcmpiA(entry.szExeFile, exe) == 0) {
                pid = entry.th32ProcessID;
                break;
            }
        } while (Process32Next(snap, &entry));
    }

    CloseHandle(snap);
    return pid;
}

/* The supervisor runs where nothing can watch it: no console, and on
   Android no wine stderr reaches anywhere readable. So it says what
   it did, beside itself in the game directory, where both a desktop
   and a phone can read it afterwards. Truncated each run; a few KB. */
static HANDLE logfile = INVALID_HANDLE_VALUE;

static void log_open(void)
{
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    while (n > 0 && path[n - 1] != '\\')
        n--;
    lstrcpyA(path + n, "strom-ff8-supervisor.log");
    logfile = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                          CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

static void log_line(const char *s)
{
    DWORD written;
    SYSTEMTIME t;
    char stamp[32];

    if (logfile == INVALID_HANDLE_VALUE)
        return;
    GetLocalTime(&t);
    wsprintfA(stamp, "%02d:%02d:%02d ", t.wHour, t.wMinute, t.wSecond);
    WriteFile(logfile, stamp, lstrlenA(stamp), &written, NULL);
    WriteFile(logfile, s, lstrlenA(s), &written, NULL);
    WriteFile(logfile, "\r\n", 2, &written, NULL);
    FlushFileBuffers(logfile);
}

/* Every running image name, so a launcher that starts something
   under a name we did not expect is visible rather than invisible. */
static void log_processes(void)
{
    PROCESSENTRY32 entry;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    char line[1024];
    int len = 0;

    if (snap == INVALID_HANDLE_VALUE)
        return;

    lstrcpyA(line, "processes:");
    len = lstrlenA(line);
    entry.dwSize = sizeof entry;
    if (Process32First(snap, &entry)) {
        do {
            int add = lstrlenA(entry.szExeFile) + 1;
            if (len + add > (int)sizeof line - 2)
                break;
            line[len++] = ' ';
            lstrcpyA(line + len, entry.szExeFile);
            len += add - 1;
        } while (Process32Next(snap, &entry));
    }
    CloseHandle(snap);
    log_line(line);
}

/* FFNx cannot start without a Steam-style user folder, and a fresh
   wineprefix has none.

   get_userdata_path (common.cpp:2937) builds
   Documents\Square Enix\FINAL FANTASY VIII Steam and then looks for
   the first "user_*" child. When there is none it leaves the path
   without one, and Metadata::init (metadata.cpp:70) immediately does
   userID.assign(strrchr(userPath, '_') + 1) -- strrchr returns NULL
   and the game dies dereferencing 0x1. Measured on an AYN Thor: the
   launcher's PLAY started FF8_EN.exe, FFNx.log stopped exactly after
   "Metadata: Initializing manager", and the process was gone within
   four seconds.

   On the desktop the folder already exists (~/.strom/<game>/FINAL
   FANTASY VIII Steam/user_1, created on first run and relocated by
   saveLocations), which is why this only ever bit on a phone. The
   name matches that one so saves stay interchangeable between them. */
static void ensure_userdata_dir(void)
{
    static const char *parts[] = {
        "Documents", "Square Enix", "FINAL FANTASY VIII Steam", "user_1"
    };
    char path[MAX_PATH];
    DWORD n = GetEnvironmentVariableA("USERPROFILE", path, MAX_PATH);
    int i;

    if (n == 0 || n >= MAX_PATH) {
        log_line("ensure_userdata_dir: no USERPROFILE");
        return;
    }

    for (i = 0; i < 4; i++) {
        if (lstrlenA(path) + lstrlenA(parts[i]) + 2 > MAX_PATH)
            return;
        lstrcatA(path, "\\");
        lstrcatA(path, parts[i]);
        CreateDirectoryA(path, NULL);
    }

    if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES)
        log_line("ensure_userdata_dir: FAILED to create the user folder");
    else
        log_line(path);
}

int WINAPI WinMain(HINSTANCE self, HINSTANCE prev, LPSTR args, int show)
{
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char cmd[] = "FF8_Launcher.exe";
    DWORD game = 0;
    int i;

    (void)self; (void)prev; (void)args; (void)show;

    ZeroMemory(&si, sizeof si);
    si.cb = sizeof si;

    log_open();
    log_line("supervisor start");
    ensure_userdata_dir();

    /* Mirrors what the desktop wrapper exports, because on Android
       nothing outside the payload runs and GameNative's per-container
       environment cannot be reached from a launch intent. FFNx
       force-enables Steam achievements as soon as it sees af3dn.p and
       then calls SteamAPI_Init unconditionally (common.cpp:845),
       dying on "Steam must be running to play this game with
       achievements"; this variable is the documented escape hatch,
       read to detect its author's macOS wrapper (utils.cpp:169).
       Inherited by the launcher and by the FF8_EN.exe it spawns. */
    SetEnvironmentVariableA("__CFBundleIdentifier",
                            "com.julianxhokaxhiu.SummonKit");

    if (!CreateProcessA("FF8_Launcher.exe", cmd, NULL, NULL, FALSE, 0,
                        NULL, NULL, &si, &pi)) {
        log_line("CreateProcess FF8_Launcher.exe FAILED");
        return 2;
    }
    log_line("launcher started, waiting for FF8_EN.exe");

    /* Wait for PLAY. Bounded so a session that is never started
       still terminates instead of hanging forever. */
    for (i = 0; i < 3600 && game == 0; i++) {
        game = find_pid("FF8_EN.exe");
        if (game == 0) {
            if (i % 15 == 0)
                log_processes();
            Sleep(1000);
        }
    }
    log_line(game != 0 ? "FF8_EN.exe found" : "gave up waiting");

    if (game != 0) {
        HANDLE handle;

        /* Let the engine finish taking over the display first. */
        Sleep(4000);
        TerminateProcess(pi.hProcess, 0);

        handle = OpenProcess(SYNCHRONIZE, FALSE, game);
        if (handle) {
            WaitForSingleObject(handle, INFINITE);
            CloseHandle(handle);
        }
    } else {
        WaitForSingleObject(pi.hProcess, INFINITE);
    }

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
