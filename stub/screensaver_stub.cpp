// screensaver_stub.cpp
//
// Minimal Windows screensaver "player" used by the macOS Image-to-Screensaver
// converter. The macOS app appends a payload (config JSON + PNG-encoded images)
// to the end of the compiled binary; this stub reads itself at runtime and
// plays the slideshow.
//
// Implements the standard Windows screensaver command-line protocol:
//   /s          full-screen run
//   /p HWND     child-window preview
//   /c[:HWND]   configuration dialog
//   /a HWND     legacy password (stubbed)
//
// Exit (in /s mode): mouse motion past a jitter threshold, mouse click, or
// any keypress. Behaviour is identical to a standard Windows screensaver.
//
// No networking, no persistence, no privilege use. Strictly the documented
// screensaver protocol.

#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <shellscalingapi.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <random>

using namespace Gdiplus;

// ---------------------------------------------------------------------------
// Payload format (must stay in sync with PayloadBuilder.swift)
//
//   [stub PE bytes ...........................]
//   [u32 metadata_len][metadata JSON utf-8]
//   [u32 image_count]
//     repeated image_count times:
//       [u32 image_len][PNG bytes]
//   [8 bytes magic = "SCRPLD\x01\x00"]
//   [u64 LE offset to start of payload from file start]
// ---------------------------------------------------------------------------

static const char kFooterMagic[8] = { 'S','C','R','P','L','D','\x01','\x00' };
static const size_t kFooterSize = sizeof(kFooterMagic) + sizeof(uint64_t);

// ---------------------------------------------------------------------------
// Config (parsed from JSON; we keep parsing strictly minimal to avoid pulling
// in a JSON library — keys we recognise are listed below).
// ---------------------------------------------------------------------------
struct Config {
    double duration = 5.0;          // seconds per image
    double transitionDuration = 1.0;
    std::wstring transition = L"fade"; // "none" | "fade" | "slide"
    std::wstring fitMode = L"contain"; // "contain" | "cover" | "stretch"
    COLORREF background = RGB(0, 0, 0);
    bool shuffle = false;
};

// ---------------------------------------------------------------------------
// Lightweight, forgiving JSON value extraction. We only need flat key lookups.
// ---------------------------------------------------------------------------
static bool jsonFindString(const std::string& j, const std::string& key, std::string& out) {
    auto p = j.find("\"" + key + "\"");
    if (p == std::string::npos) return false;
    p = j.find(':', p); if (p == std::string::npos) return false;
    p = j.find('"', p); if (p == std::string::npos) return false;
    auto end = j.find('"', p + 1); if (end == std::string::npos) return false;
    out = j.substr(p + 1, end - p - 1);
    return true;
}
static bool jsonFindNumber(const std::string& j, const std::string& key, double& out) {
    auto p = j.find("\"" + key + "\"");
    if (p == std::string::npos) return false;
    p = j.find(':', p); if (p == std::string::npos) return false;
    ++p;
    while (p < j.size() && (j[p] == ' ' || j[p] == '\t')) ++p;
    char* endp = nullptr;
    out = strtod(j.c_str() + p, &endp);
    return endp != j.c_str() + p;
}
static bool jsonFindBool(const std::string& j, const std::string& key, bool& out) {
    auto p = j.find("\"" + key + "\"");
    if (p == std::string::npos) return false;
    p = j.find(':', p); if (p == std::string::npos) return false;
    if (j.compare(p + 1, 4, "true", 0, 4) == 0 || j.find("true", p) == p + 1 || j.find("true", p) == p + 2) { out = true; return true; }
    if (j.find("false", p) != std::string::npos && j.find("false", p) - p < 4) { out = false; return true; }
    return false;
}

static std::wstring widen(const std::string& s) {
    if (s.empty()) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring out(n, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &out[0], n);
    return out;
}

// ---------------------------------------------------------------------------
// Payload loader. Returns true on success.
// ---------------------------------------------------------------------------
struct LoadedImage {
    std::vector<uint8_t> png;
    Image* image = nullptr;
};

static bool loadPayload(Config& cfg, std::vector<LoadedImage>& images) {
    wchar_t selfPath[MAX_PATH];
    if (!GetModuleFileNameW(nullptr, selfPath, MAX_PATH)) return false;

    HANDLE h = CreateFileW(selfPath, GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER fileSize{};
    if (!GetFileSizeEx(h, &fileSize) || fileSize.QuadPart < (LONGLONG)kFooterSize) {
        CloseHandle(h); return false;
    }

    // Read footer
    LARGE_INTEGER seek; seek.QuadPart = fileSize.QuadPart - (LONGLONG)kFooterSize;
    if (!SetFilePointerEx(h, seek, nullptr, FILE_BEGIN)) { CloseHandle(h); return false; }
    uint8_t footer[kFooterSize];
    DWORD got = 0;
    if (!ReadFile(h, footer, kFooterSize, &got, nullptr) || got != kFooterSize) {
        CloseHandle(h); return false;
    }
    if (memcmp(footer, kFooterMagic, sizeof(kFooterMagic)) != 0) {
        CloseHandle(h); return false;
    }
    uint64_t payloadStart = 0;
    memcpy(&payloadStart, footer + sizeof(kFooterMagic), sizeof(uint64_t));
    if (payloadStart >= (uint64_t)fileSize.QuadPart) { CloseHandle(h); return false; }

    // Seek to payload, read all bytes between payloadStart and footer.
    seek.QuadPart = (LONGLONG)payloadStart;
    if (!SetFilePointerEx(h, seek, nullptr, FILE_BEGIN)) { CloseHandle(h); return false; }

    size_t payloadLen = (size_t)(fileSize.QuadPart - (LONGLONG)payloadStart - (LONGLONG)kFooterSize);
    std::vector<uint8_t> buf(payloadLen);
    DWORD totalRead = 0;
    while (totalRead < payloadLen) {
        DWORD r = 0;
        if (!ReadFile(h, buf.data() + totalRead, (DWORD)(payloadLen - totalRead), &r, nullptr) || r == 0) {
            CloseHandle(h); return false;
        }
        totalRead += r;
    }
    CloseHandle(h);

    // Parse metadata
    if (payloadLen < 4) return false;
    size_t off = 0;
    uint32_t metaLen = 0;
    memcpy(&metaLen, buf.data() + off, 4); off += 4;
    if (off + metaLen > payloadLen) return false;
    std::string meta((const char*)(buf.data() + off), metaLen); off += metaLen;

    std::string s;
    double d; bool b;
    if (jsonFindNumber(meta, "duration", d)) cfg.duration = d;
    if (jsonFindNumber(meta, "transitionDuration", d)) cfg.transitionDuration = d;
    if (jsonFindString(meta, "transition", s)) cfg.transition = widen(s);
    if (jsonFindString(meta, "fitMode", s)) cfg.fitMode = widen(s);
    if (jsonFindBool(meta, "shuffle", b)) cfg.shuffle = b;
    if (jsonFindString(meta, "backgroundColor", s) && s.size() == 7 && s[0] == '#') {
        unsigned int r=0,g=0,bl=0;
        sscanf(s.c_str() + 1, "%02x%02x%02x", &r, &g, &bl);
        cfg.background = RGB(r, g, bl);
    }

    // Parse images
    if (off + 4 > payloadLen) return false;
    uint32_t count = 0;
    memcpy(&count, buf.data() + off, 4); off += 4;
    images.reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
        if (off + 4 > payloadLen) return false;
        uint32_t len = 0;
        memcpy(&len, buf.data() + off, 4); off += 4;
        if (off + len > payloadLen) return false;
        LoadedImage li;
        li.png.assign(buf.data() + off, buf.data() + off + len);
        images.push_back(std::move(li));
        off += len;
    }

    // Decode each PNG into a GDI+ Image (kept resident in memory via IStream).
    for (auto& img : images) {
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, img.png.size());
        if (!hMem) continue;
        void* p = GlobalLock(hMem);
        memcpy(p, img.png.data(), img.png.size());
        GlobalUnlock(hMem);
        IStream* stream = nullptr;
        if (CreateStreamOnHGlobal(hMem, TRUE, &stream) == S_OK) {
            img.image = Image::FromStream(stream);
            stream->Release();
        }
    }
    if (cfg.shuffle) {
        std::random_device rd; std::mt19937 g(rd());
        std::shuffle(images.begin(), images.end(), g);
    }
    return !images.empty();
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
struct AppState {
    Config cfg;
    std::vector<LoadedImage> images;
    size_t index = 0;
    DWORD slideStart = 0;
    bool isPreview = false;
    POINT initialMouse{ -1, -1 };
};

static void drawFitted(Graphics& g, Image* img, const RectF& dst, const std::wstring& fitMode) {
    if (!img) return;
    REAL iw = (REAL)img->GetWidth();
    REAL ih = (REAL)img->GetHeight();
    if (iw <= 0 || ih <= 0) return;
    REAL dx = dst.X, dy = dst.Y, dw = dst.Width, dh = dst.Height;

    if (fitMode == L"stretch") {
        g.DrawImage(img, dst);
        return;
    }
    REAL scale;
    if (fitMode == L"cover") {
        scale = std::max(dw / iw, dh / ih);
    } else { // contain
        scale = std::min(dw / iw, dh / ih);
    }
    REAL w = iw * scale;
    REAL h = ih * scale;
    REAL x = dx + (dw - w) * 0.5f;
    REAL y = dy + (dh - h) * 0.5f;
    g.DrawImage(img, RectF(x, y, w, h));
}

static void paint(HWND hwnd, AppState* st) {
    RECT rc; GetClientRect(hwnd, &rc);
    int w = rc.right - rc.left, h = rc.bottom - rc.top;
    if (w <= 0 || h <= 0) return;

    HDC hdc = GetDC(hwnd);
    // Double buffer
    HDC mem = CreateCompatibleDC(hdc);
    HBITMAP bmp = CreateCompatibleBitmap(hdc, w, h);
    HGDIOBJ old = SelectObject(mem, bmp);

    HBRUSH bg = CreateSolidBrush(st->cfg.background);
    RECT full = { 0, 0, w, h };
    FillRect(mem, &full, bg);
    DeleteObject(bg);

    {
        Graphics g(mem);
        g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);

        DWORD now = GetTickCount();
        DWORD elapsed = now - st->slideStart;
        DWORD slideMs = (DWORD)(st->cfg.duration * 1000.0);
        DWORD transMs = (DWORD)(st->cfg.transitionDuration * 1000.0);
        if (transMs > slideMs) transMs = slideMs / 2;

        Image* current = st->images[st->index].image;
        size_t nextIdx = (st->index + 1) % st->images.size();
        Image* next = st->images[nextIdx].image;

        RectF dst(0, 0, (REAL)w, (REAL)h);

        if (st->cfg.transition == L"none" || transMs == 0 || elapsed < slideMs - transMs) {
            drawFitted(g, current, dst, st->cfg.fitMode);
        } else {
            // Transition phase
            REAL t = (REAL)(elapsed - (slideMs - transMs)) / (REAL)transMs;
            if (t < 0) t = 0; if (t > 1) t = 1;

            if (st->cfg.transition == L"slide") {
                RectF a(-t * w, 0, (REAL)w, (REAL)h);
                RectF b((1.0f - t) * w, 0, (REAL)w, (REAL)h);
                drawFitted(g, current, a, st->cfg.fitMode);
                drawFitted(g, next, b, st->cfg.fitMode);
            } else { // fade (default)
                drawFitted(g, current, dst, st->cfg.fitMode);
                ColorMatrix cm = {
                    1,0,0,0,0,
                    0,1,0,0,0,
                    0,0,1,0,0,
                    0,0,0,t,0,
                    0,0,0,0,1
                };
                ImageAttributes attrs;
                attrs.SetColorMatrix(&cm, ColorMatrixFlagsDefault, ColorAdjustTypeBitmap);
                if (next) {
                    REAL iw = (REAL)next->GetWidth();
                    REAL ih = (REAL)next->GetHeight();
                    REAL scale = (st->cfg.fitMode == L"cover")
                        ? std::max((REAL)w / iw, (REAL)h / ih)
                        : std::min((REAL)w / iw, (REAL)h / ih);
                    if (st->cfg.fitMode == L"stretch") {
                        g.DrawImage(next, RectF(0, 0, (REAL)w, (REAL)h),
                                    0, 0, iw, ih, UnitPixel, &attrs);
                    } else {
                        REAL nw = iw * scale, nh = ih * scale;
                        REAL nx = ((REAL)w - nw) * 0.5f;
                        REAL ny = ((REAL)h - nh) * 0.5f;
                        g.DrawImage(next, RectF(nx, ny, nw, nh),
                                    0, 0, iw, ih, UnitPixel, &attrs);
                    }
                }
            }
        }
    }

    BitBlt(hdc, 0, 0, w, h, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    ReleaseDC(hwnd, hdc);
}

// ---------------------------------------------------------------------------
// Window procedure
// ---------------------------------------------------------------------------
static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    AppState* st = (AppState*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCT* cs = (CREATESTRUCT*)lp;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
        SetTimer(hwnd, 1, 33, nullptr); // ~30 FPS
        if (!((AppState*)cs->lpCreateParams)->isPreview) ShowCursor(FALSE);
        ((AppState*)cs->lpCreateParams)->slideStart = GetTickCount();
        return 0;
    }
    case WM_TIMER: {
        if (!st) return 0;
        DWORD elapsed = GetTickCount() - st->slideStart;
        DWORD slideMs = (DWORD)(st->cfg.duration * 1000.0);
        if (elapsed >= slideMs) {
            st->index = (st->index + 1) % st->images.size();
            st->slideStart = GetTickCount();
        }
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps; BeginPaint(hwnd, &ps);
        if (st) paint(hwnd, st);
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_ERASEBKGND: return 1;
    case WM_MOUSEMOVE: {
        if (!st || st->isPreview) return 0;
        POINTS p = MAKEPOINTS(lp);
        if (st->initialMouse.x < 0) {
            st->initialMouse.x = p.x; st->initialMouse.y = p.y; return 0;
        }
        int dx = p.x - st->initialMouse.x;
        int dy = p.y - st->initialMouse.y;
        if (dx*dx + dy*dy > 100) PostMessageW(hwnd, WM_CLOSE, 0, 0);
        return 0;
    }
    case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN:
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
        if (st && !st->isPreview) PostMessageW(hwnd, WM_CLOSE, 0, 0);
        return 0;
    case WM_DESTROY:
        if (st && !st->isPreview) ShowCursor(TRUE);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// Mode runners
// ---------------------------------------------------------------------------
static int runFullscreen(HINSTANCE hInst, AppState& st) {
    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = L"ImageScreensaverWnd";
    RegisterClassW(&wc);

    int sx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int sy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int sw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int sh = GetSystemMetrics(SM_CYVIRTUALSCREEN);

    HWND hwnd = CreateWindowExW(WS_EX_TOPMOST, wc.lpszClassName, L"",
        WS_POPUP | WS_VISIBLE, sx, sy, sw, sh, nullptr, nullptr, hInst, &st);
    if (!hwnd) return 1;
    SetForegroundWindow(hwnd);
    SetCapture(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}

static int runPreview(HINSTANCE hInst, AppState& st, HWND parent) {
    st.isPreview = true;
    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = L"ImageScreensaverPrev";
    RegisterClassW(&wc);

    RECT pr; GetClientRect(parent, &pr);
    HWND hwnd = CreateWindowW(wc.lpszClassName, L"", WS_CHILD | WS_VISIBLE,
        0, 0, pr.right, pr.bottom, parent, nullptr, hInst, &st);
    if (!hwnd) return 1;

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}

static int runConfig(HINSTANCE, AppState& st) {
    wchar_t buf[512];
    swprintf(buf, 512,
        L"Image Slideshow Screensaver\n\n"
        L"Images: %zu\nDuration: %.1fs per image\nTransition: %s\nFit: %s\n\n"
        L"Settings are baked into this screensaver. To change them, "
        L"re-export from the macOS Image-to-Screensaver app.",
        st.images.size(), st.cfg.duration, st.cfg.transition.c_str(), st.cfg.fitMode.c_str());
    MessageBoxW(nullptr, buf, L"Screensaver Settings", MB_OK | MB_ICONINFORMATION);
    return 0;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR cmdLine, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    GdiplusStartupInput gsi;
    ULONG_PTR gdiplusToken = 0;
    GdiplusStartup(&gdiplusToken, &gsi, nullptr);

    AppState st;
    if (!loadPayload(st.cfg, st.images) || st.images.empty()) {
        MessageBoxW(nullptr,
            L"This screensaver file has no embedded slideshow payload "
            L"or the payload is corrupt.",
            L"Screensaver Error", MB_OK | MB_ICONERROR);
        GdiplusShutdown(gdiplusToken);
        return 1;
    }

    // Parse the cmdLine. Windows passes /s, /p HWND, /c, /c:HWND, /a HWND.
    std::wstring args = cmdLine ? cmdLine : L"";
    wchar_t mode = L's';
    HWND parentHwnd = nullptr;
    if (!args.empty()) {
        // Take first non-space token.
        size_t i = 0;
        while (i < args.size() && iswspace(args[i])) ++i;
        if (i < args.size() && (args[i] == L'/' || args[i] == L'-') && i + 1 < args.size()) {
            mode = (wchar_t)towlower(args[i + 1]);
            // optional :HWND or space HWND
            size_t j = i + 2;
            if (j < args.size() && args[j] == L':') ++j;
            while (j < args.size() && iswspace(args[j])) ++j;
            if (j < args.size()) {
                unsigned long long h = wcstoull(args.c_str() + j, nullptr, 0);
                parentHwnd = (HWND)(uintptr_t)h;
            }
        }
    }

    int rc = 0;
    switch (mode) {
    case L'p':
        if (parentHwnd && IsWindow(parentHwnd)) rc = runPreview(hInst, st, parentHwnd);
        break;
    case L'c': rc = runConfig(hInst, st); break;
    case L'a': rc = 0; break;
    case L's': default: rc = runFullscreen(hInst, st); break;
    }

    for (auto& img : st.images) delete img.image;
    GdiplusShutdown(gdiplusToken);
    return rc;
}
