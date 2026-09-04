// PS/2 set-2 scancodes for driving hps_io-style ps2_key[10:0] = {toggle, pressed, ext, code}
#pragma once
#include <cstdint>
#include <string>
#include <deque>
struct Ps2Event { uint8_t code; bool ext; bool pressed; };
static inline bool ascii_to_ps2(char c, uint8_t& code, bool& shift, bool& ctrl) {
    shift = false; ctrl = false;
    static const char* lower = "abcdefghijklmnopqrstuvwxyz";
    static const uint8_t letters[26] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
    if (c >= 'a' && c <= 'z') { code = letters[c - 'a']; return true; }
    if (c >= 'A' && c <= 'Z') { code = letters[c - 'A']; shift = true; return true; }
    if (c >= 1 && c <= 26) { code = letters[c - 1]; ctrl = true; return true; } // control chars
    static const char* digits = "0123456789";
    static const uint8_t dcodes[10] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
    if (c >= '0' && c <= '9') { code = dcodes[c - '0']; return true; }
    static const char* shifted = ")!@#$%^&*(";
    for (int i = 0; i < 10; i++) if (c == shifted[i]) { code = dcodes[i]; shift = true; return true; }
    switch (c) {
        case ' ': code = 0x29; return true;  case '\r': case '\n': code = 0x5A; return true;
        case 27: code = 0x76; return true;   case '\t': code = 0x0D; return true;
        case 8: code = 0x66; return true;    case 127: code = 0x66; return true;
        case '-': code = 0x4E; return true;  case '_': code = 0x4E; shift = true; return true;
        case '=': code = 0x55; return true;  case '+': code = 0x55; shift = true; return true;
        case '[': code = 0x54; return true;  case '{': code = 0x54; shift = true; return true;
        case ']': code = 0x5B; return true;  case '}': code = 0x5B; shift = true; return true;
        case '\\': code = 0x5D; return true; case '|': code = 0x5D; shift = true; return true;
        case ';': code = 0x4C; return true;  case ':': code = 0x4C; shift = true; return true;
        case '\'': code = 0x52; return true; case '"': code = 0x52; shift = true; return true;
        case ',': code = 0x41; return true;  case '<': code = 0x41; shift = true; return true;
        case '.': code = 0x49; return true;  case '>': code = 0x49; shift = true; return true;
        case '/': code = 0x4A; return true;  case '?': code = 0x4A; shift = true; return true;
        case '`': code = 0x0E; return true;  case '~': code = 0x0E; shift = true; return true;
    }
    return false;
}
// Build a press/release event sequence for a string. Special names in braces: {UP} {DOWN} {LEFT} {RIGHT} {F1}.. {ENTER} {ESC} {TAB} {DEL} {CAPS} {OA} {CA} {CTRL}x
static inline void string_to_events(const std::string& s, std::deque<Ps2Event>& out) {
    for (size_t i = 0; i < s.size(); i++) {
        char c = s[i];
        if (c == '{') {
            size_t e = s.find('}', i); if (e == std::string::npos) return;
            std::string name = s.substr(i + 1, e - i - 1); i = e;
            uint8_t code = 0; bool ext = false;
            if (name == "UP") { code = 0x75; ext = true; } else if (name == "DOWN") { code = 0x72; ext = true; }
            else if (name == "LEFT") { code = 0x6B; ext = true; } else if (name == "RIGHT") { code = 0x74; ext = true; }
            else if (name == "ENTER") { code = 0x5A; } else if (name == "ESC") { code = 0x76; } else if (name == "TAB") { code = 0x0D; }
            else if (name == "DEL") { code = 0x71; ext = true; } else if (name == "BS") { code = 0x66; }
            else if (name == "CAPS") { code = 0x58; } else if (name == "KPENTER") { code = 0x5A; ext = true; }
            else if (name == "F1") { code = 0x05; } else if (name == "F2") { code = 0x06; } else if (name == "F3") { code = 0x04; }
            else if (name == "F4") { code = 0x0C; } else if (name == "F5") { code = 0x03; } else if (name == "F6") { code = 0x0B; }
            else if (name == "F7") { code = 0x83; } else if (name == "F8") { code = 0x0A; } else if (name == "F9") { code = 0x01; }
            else if (name == "F10") { code = 0x09; } else if (name == "F11") { code = 0x78; } else if (name == "F12") { code = 0x07; }
            else if (name == "LALT") { code = 0x11; } else if (name == "RALT") { code = 0x11; ext = true; }
            else if (name == "LGUI") { code = 0x1F; ext = true; } else if (name == "RGUI") { code = 0x27; ext = true; }
            else continue;
            out.push_back({code, ext, true}); out.push_back({code, ext, false});
            continue;
        }
        uint8_t code; bool shift, ctrl;
        if (!ascii_to_ps2(c, code, shift, ctrl)) continue;
        if (shift) out.push_back({0x12, false, true});
        if (ctrl) out.push_back({0x14, false, true});
        out.push_back({code, false, true}); out.push_back({code, false, false});
        if (ctrl) out.push_back({0x14, false, false});
        if (shift) out.push_back({0x12, false, false});
    }
}
