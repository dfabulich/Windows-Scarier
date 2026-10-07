/*
 * Windows Glk is written as an MFC regular DLL, which MFC's DllMain sets up
 * when Glk.dll loads and shuts down when it unloads.  Scarier links Windows
 * Glk statically instead, so this file does that work for Scarier.exe.
 */

/* Scarier's OS_WINDOWS clashes with an IsOS() constant in MFC's headers. */
#undef OS_WINDOWS

/* As in Windows Glk's StdAfx.h, which selects the MFC libraries to link. */
#define VC_EXTRALEAN
#define _AFX_NO_MFC_CONTROLS_IN_DIALOGS
#define WINVER 0x0600
#define _WIN32_WINNT 0x0600
#include <afxwin.h>

static bool glkInitialized = false;
static bool glkRunning = false;

static void ShutDownGlk(void)
{
  if (!glkRunning)
    return;
  glkRunning = false;

  /* CGlkApp::ExitInstance() saves the player's settings. */
  AfxGetApp()->ExitInstance();
  AfxWinTerm();
}

/*
 * Every Windows Glk entry point begins with
 * AFX_MANAGE_STATE(AfxGetStaticModuleState()), so the first call into Glk
 * starts it, as loading Glk.dll did.
 */
AFX_MODULE_STATE* AFXAPI AfxGetStaticModuleState()
{
  if (!glkInitialized)
  {
    glkInitialized = true;
    if (!AfxWinInit(::GetModuleHandle(NULL), NULL, const_cast<LPTSTR>(_T("")), 0) ||
        !AfxGetApp()->InitInstance())
    {
      ::ExitProcess(1);
    }
    glkRunning = true;

    /* Runs before the static CGlkApp is destroyed, when Scarier returns from WinMain. */
    atexit(ShutDownGlk);
  }
  return AfxGetModuleState();
}

/*
 * glk_exit() ends the process with ExitProcess(), which skips atexit()
 * handlers.  A TLS callback still gets DLL_PROCESS_DETACH, at the same point
 * where Glk.dll's DllMain did.
 */
static void NTAPI GlkTlsCallback(PVOID, DWORD reason, PVOID)
{
  if (reason == DLL_PROCESS_DETACH)
    ShutDownGlk();
}

#pragma section(".CRT$XLB", long, read)
extern "C" __declspec(allocate(".CRT$XLB")) const PIMAGE_TLS_CALLBACK glkTlsCallback = GlkTlsCallback;

/* Scarier is 32-bit only, where C symbols are decorated with a leading underscore. */
#pragma comment(linker, "/INCLUDE:__tls_used")
#pragma comment(linker, "/INCLUDE:_glkTlsCallback")
