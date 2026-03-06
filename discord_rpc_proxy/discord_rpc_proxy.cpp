#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifndef ATLAS_LAUNCHER_VERSION
#define ATLAS_LAUNCHER_VERSION "unknown"
#endif

#include <atomic>
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

extern "C" {

struct DiscordUser {
  const char* userId;
  const char* username;
  const char* discriminator;
  const char* avatar;
};

typedef void(__cdecl* readyCallback)(const DiscordUser* request);
typedef void(__cdecl* disconnectedCallback)(int errcode, const char* message);
typedef void(__cdecl* erroredCallback)(int errcode, const char* message);
typedef void(__cdecl* joinGameCallback)(const char* joinSecret);
typedef void(__cdecl* spectateGameCallback)(const char* spectateSecret);
typedef void(__cdecl* joinRequestCallback)(const DiscordUser* request);

struct DiscordEventHandlers {
  readyCallback ready;
  disconnectedCallback disconnected;
  erroredCallback errored;
  joinGameCallback joinGame;
  spectateGameCallback spectateGame;
  joinRequestCallback joinRequest;
};

struct DiscordRichPresence {
  const char* state;
  const char* details;
  std::int64_t startTimestamp;
  std::int64_t endTimestamp;
  const char* largeImageKey;
  const char* largeImageText;
  const char* smallImageKey;
  const char* smallImageText;
  const char* partyId;
  int partySize;
  int partyMax;
  const char* matchSecret;
  const char* joinSecret;
  const char* spectateSecret;
  std::int8_t instance;
};

}  // extern "C"

namespace {

constexpr wchar_t kForwardLibraryName[] = L"discord-rpc-original.dll";

// Edit these strings. Empty string means "keep the original value".
constexpr char kOverrideApplicationId[] = "1465348345122914335";
constexpr char kMainDetailsLine[] = "Playing Fortnite";
constexpr char kAtlasLargeImageKey[] = "atlas-icon";
constexpr char kAtlasSmallImageKey[] = "fortnite-logo";
constexpr char kLargeImageHoverText[] =
    "@cipherfps (v" ATLAS_LAUNCHER_VERSION ")";
constexpr char kBuildHoverPrefix[] = "Build ";
constexpr char kDiscordButtonLabel[] = "ATLAS Discord";
constexpr char kDiscordButtonUrl[] = "https://discord.gg/GqgakxU6bm";

HMODULE gSelfModule = nullptr;
HMODULE gForwardModule = nullptr;
std::once_flag gLoadOnce;
std::atomic<int> gLoggedPresenceUpdates{0};
std::atomic<unsigned long long> gIpcNonceCounter{0};
std::string gDetectedBuildLabel = "Unknown";
std::string gDetectedVersionTag = "Unknown Version";
std::string gEffectiveApplicationId;
std::mutex gEffectiveApplicationIdMutex;
thread_local std::string gPatchedStateStorage;

class DiscordIpcClient {
 public:
  bool SetActivity(const std::string& appId, const std::string& activityJson) {
    if (appId.empty()) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!EnsureConnectedLocked(appId)) return false;

    const std::string payload = BuildSetActivityPayload(activityJson);
    if (!WriteFrameLocked(1, payload)) {
      CloseLocked();
      return false;
    }
    DrainIncomingMessagesLocked();
    return true;
  }

  bool ClearActivity(const std::string& appId) {
    if (appId.empty()) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!EnsureConnectedLocked(appId)) return false;

    const std::string payload = BuildSetActivityPayload("null");
    if (!WriteFrameLocked(1, payload)) {
      CloseLocked();
      return false;
    }
    DrainIncomingMessagesLocked();
    return true;
  }

 private:
  bool EnsureConnectedLocked(const std::string& appId) {
    if (pipe_ != INVALID_HANDLE_VALUE && connectedAppId_ == appId) return true;
    CloseLocked();
    if (!ConnectLocked()) return false;
    connectedAppId_ = appId;
    return SendHandshakeLocked(appId);
  }

  bool ConnectLocked() {
    for (int i = 0; i <= 9; ++i) {
      std::ostringstream path;
      path << "\\\\.\\pipe\\discord-ipc-" << i;
      HANDLE pipe = CreateFileA(
          path.str().c_str(),
          GENERIC_READ | GENERIC_WRITE,
          0,
          nullptr,
          OPEN_EXISTING,
          0,
          nullptr);
      if (pipe != INVALID_HANDLE_VALUE) {
        pipe_ = pipe;
        return true;
      }
    }
    return false;
  }

  bool SendHandshakeLocked(const std::string& appId) {
    const std::string payload =
        std::string("{\"v\":1,\"client_id\":\"") + JsonEscape(appId) + "\"}";
    if (!WriteFrameLocked(0, payload)) {
      CloseLocked();
      return false;
    }
    DrainIncomingMessagesLocked();
    return true;
  }

  bool WriteFrameLocked(std::int32_t opcode, const std::string& payload) {
    if (pipe_ == INVALID_HANDLE_VALUE) return false;
    struct Header {
      std::int32_t opcode;
      std::int32_t length;
    } header = {opcode, static_cast<std::int32_t>(payload.size())};

    DWORD written = 0;
    if (!WriteFile(pipe_, &header, sizeof(header), &written, nullptr) ||
        written != sizeof(header)) {
      return false;
    }
    if (!payload.empty()) {
      written = 0;
      if (!WriteFile(
              pipe_,
              payload.data(),
              static_cast<DWORD>(payload.size()),
              &written,
              nullptr) ||
          written != payload.size()) {
        return false;
      }
    }
    return true;
  }

  void DrainIncomingMessagesLocked() {
    if (pipe_ == INVALID_HANDLE_VALUE) return;
    DWORD available = 0;
    while (PeekNamedPipe(pipe_, nullptr, 0, nullptr, &available, nullptr) &&
           available > 0) {
      const DWORD chunk =
          available > static_cast<DWORD>(buffer_.size())
              ? static_cast<DWORD>(buffer_.size())
              : available;
      DWORD read = 0;
      if (!ReadFile(pipe_, buffer_.data(), chunk, &read, nullptr) || read == 0) {
        break;
      }
    }
  }

  void CloseLocked() {
    if (pipe_ != INVALID_HANDLE_VALUE) {
      CloseHandle(pipe_);
      pipe_ = INVALID_HANDLE_VALUE;
    }
    connectedAppId_.clear();
  }

  static std::string JsonEscape(const std::string& value) {
    std::string escaped;
    escaped.reserve(value.size() + 8);
    for (unsigned char c : value) {
      switch (c) {
        case '\"':
          escaped += "\\\"";
          break;
        case '\\':
          escaped += "\\\\";
          break;
        case '\b':
          escaped += "\\b";
          break;
        case '\f':
          escaped += "\\f";
          break;
        case '\n':
          escaped += "\\n";
          break;
        case '\r':
          escaped += "\\r";
          break;
        case '\t':
          escaped += "\\t";
          break;
        default:
          if (c < 0x20) {
            char hex[7] = {};
            std::snprintf(hex, sizeof(hex), "\\u%04x", static_cast<unsigned>(c));
            escaped += hex;
          } else {
            escaped.push_back(static_cast<char>(c));
          }
          break;
      }
    }
    return escaped;
  }

  static std::string BuildSetActivityPayload(const std::string& activityJson) {
    const auto nonce = gIpcNonceCounter.fetch_add(1) + 1;
    std::ostringstream payload;
    payload << "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":"
            << static_cast<unsigned long>(GetCurrentProcessId())
            << ",\"activity\":" << activityJson << "},\"nonce\":\"atlas-"
            << nonce << "\"}";
    return payload.str();
  }

  HANDLE pipe_ = INVALID_HANDLE_VALUE;
  std::string connectedAppId_;
  std::vector<char> buffer_{std::vector<char>(4096, 0)};
  std::mutex mutex_;
};

DiscordIpcClient gDiscordIpcClient;

using FnDiscord_Initialize = void(__cdecl*)(
    const char* applicationId,
    DiscordEventHandlers* handlers,
    int autoRegister,
    const char* optionalSteamId);
using FnDiscord_Shutdown = void(__cdecl*)();
using FnDiscord_RunCallbacks = void(__cdecl*)();
using FnDiscord_UpdatePresence =
    void(__cdecl*)(const DiscordRichPresence* presence);
using FnDiscord_ClearPresence = void(__cdecl*)();
using FnDiscord_Respond = void(__cdecl*)(const char* userId, int reply);
using FnDiscord_UpdateHandlers =
    void(__cdecl*)(DiscordEventHandlers* handlers);
using FnDiscord_Register =
    void(__cdecl*)(const char* applicationId, const char* command);
using FnDiscord_RegisterSteamGame =
    void(__cdecl*)(const char* applicationId, const char* steamId);

std::wstring BuildForwardModulePath() {
  wchar_t modulePath[MAX_PATH] = {};
  const DWORD written = GetModuleFileNameW(gSelfModule, modulePath, MAX_PATH);
  if (written == 0 || written >= MAX_PATH) return std::wstring();

  std::wstring fullPath(modulePath, written);
  const size_t slash = fullPath.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return std::wstring(kForwardLibraryName);
  fullPath.resize(slash + 1);
  fullPath.append(kForwardLibraryName);
  return fullPath;
}

std::wstring BuildLogPath() {
  wchar_t tempPath[MAX_PATH] = {};
  const DWORD tempLen = GetTempPathW(MAX_PATH, tempPath);
  if (tempLen == 0 || tempLen >= MAX_PATH) {
    return L"atlas_discord_rpc_proxy.log";
  }

  std::wstring fullPath(tempPath, tempLen);
  if (!fullPath.empty() && fullPath.back() != L'\\' && fullPath.back() != L'/') {
    fullPath.push_back(L'\\');
  }
  fullPath.append(L"atlas_discord_rpc_proxy.log");
  return fullPath;
}

const char* SafeText(const char* value) {
  return value != nullptr ? value : "<null>";
}

void AppendLog(const std::string& message) {
  static std::mutex logMutex;
  std::lock_guard<std::mutex> lock(logMutex);

  const std::wstring logPath = BuildLogPath();
  const HANDLE fileHandle = CreateFileW(
      logPath.c_str(),
      FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (fileHandle == INVALID_HANDLE_VALUE) return;

  SYSTEMTIME now = {};
  GetLocalTime(&now);

  char prefix[128] = {};
  const int prefixLen = std::snprintf(
      prefix,
      sizeof(prefix),
      "%04u-%02u-%02u %02u:%02u:%02u.%03u [pid:%lu] ",
      static_cast<unsigned>(now.wYear),
      static_cast<unsigned>(now.wMonth),
      static_cast<unsigned>(now.wDay),
      static_cast<unsigned>(now.wHour),
      static_cast<unsigned>(now.wMinute),
      static_cast<unsigned>(now.wSecond),
      static_cast<unsigned>(now.wMilliseconds),
      static_cast<unsigned long>(GetCurrentProcessId()));

  std::string line;
  if (prefixLen > 0) {
    line.append(prefix, static_cast<size_t>(prefixLen));
  }
  line.append(message);
  line.append("\r\n");

  DWORD written = 0;
  WriteFile(
      fileHandle,
      line.data(),
      static_cast<DWORD>(line.size()),
      &written,
      nullptr);
  CloseHandle(fileHandle);
}

void EnsureForwardModuleLoaded() {
  std::call_once(gLoadOnce, []() {
    const std::wstring explicitPath = BuildForwardModulePath();
    if (!explicitPath.empty()) {
      gForwardModule = LoadLibraryW(explicitPath.c_str());
      if (gForwardModule != nullptr) {
        AppendLog("Loaded forward module from explicit path.");
      }
    }
    if (gForwardModule == nullptr) {
      gForwardModule = LoadLibraryW(kForwardLibraryName);
      if (gForwardModule != nullptr) {
        AppendLog("Loaded forward module by name lookup.");
      } else {
        const DWORD err = GetLastError();
        AppendLog("Failed to load forward module. WinErr=" + std::to_string(err));
      }
    }
  });
}

template <typename T>
T ResolveExport(const char* name) {
  EnsureForwardModuleLoaded();
  if (gForwardModule == nullptr) return nullptr;
  return reinterpret_cast<T>(GetProcAddress(gForwardModule, name));
}

const char* OverrideOrOriginal(const char* original, const char* overrideText) {
  if (overrideText != nullptr && overrideText[0] != '\0') return overrideText;
  return original;
}

std::string ToLower(std::string value) {
  std::transform(
      value.begin(),
      value.end(),
      value.begin(),
      [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  return value;
}

std::wstring ToLowerWide(std::wstring value) {
  std::transform(
      value.begin(),
      value.end(),
      value.begin(),
      [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
  return value;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int required = WideCharToMultiByte(
      CP_UTF8,
      0,
      value.c_str(),
      static_cast<int>(value.size()),
      nullptr,
      0,
      nullptr,
      nullptr);
  if (required <= 0) return std::string();
  std::string result(static_cast<size_t>(required), '\0');
  WideCharToMultiByte(
      CP_UTF8,
      0,
      value.c_str(),
      static_cast<int>(value.size()),
      result.data(),
      required,
      nullptr,
      nullptr);
  return result;
}

std::string DetectBuildLabelFromModulePath() {
  wchar_t modulePath[MAX_PATH] = {};
  const DWORD written = GetModuleFileNameW(gSelfModule, modulePath, MAX_PATH);
  if (written == 0 || written >= MAX_PATH) return "Unknown";

  std::wstring path(modulePath, written);
  std::replace(path.begin(), path.end(), L'\\', L'/');
  const std::wstring lowerPath = ToLowerWide(path);
  const std::wstring marker =
      L"/fortnitegame/binaries/thirdparty/discord/win64/discord-rpc.dll";
  const size_t markerPos = lowerPath.rfind(marker);
  if (markerPos == std::wstring::npos) return "Unknown";

  std::wstring prefix = path.substr(0, markerPos);
  while (!prefix.empty() && (prefix.back() == L'/' || prefix.back() == L'\\')) {
    prefix.pop_back();
  }
  if (prefix.empty()) return "Unknown";

  const size_t slash = prefix.find_last_of(L"/\\");
  const std::wstring buildName =
      slash == std::wstring::npos ? prefix : prefix.substr(slash + 1);
  if (buildName.empty()) return "Unknown";

  return WideToUtf8(buildName);
}

std::string ExtractVersionToken(const std::string& text) {
  for (size_t i = 0; i < text.size(); ++i) {
    if (!std::isdigit(static_cast<unsigned char>(text[i]))) continue;
    size_t j = i;
    while (j < text.size() &&
           std::isdigit(static_cast<unsigned char>(text[j]))) {
      ++j;
    }
    if (j >= text.size() || text[j] != '.') continue;
    if (j + 1 >= text.size() ||
        !std::isdigit(static_cast<unsigned char>(text[j + 1]))) {
      continue;
    }
    ++j;
    while (j < text.size() &&
           std::isdigit(static_cast<unsigned char>(text[j]))) {
      ++j;
    }
    if (j < text.size() && text[j] == '.' && j + 1 < text.size() &&
        std::isdigit(static_cast<unsigned char>(text[j + 1]))) {
      ++j;
      while (j < text.size() &&
             std::isdigit(static_cast<unsigned char>(text[j]))) {
        ++j;
      }
    }
    return text.substr(i, j - i);
  }
  return std::string();
}

std::string BuildVersionTagFromBuildLabel(const std::string& buildLabel) {
  const std::string version = ExtractVersionToken(buildLabel);
  if (!version.empty()) return "v" + version;
  return "Unknown Version";
}

bool ContainsToken(const char* text, const char* token) {
  if (text == nullptr || token == nullptr) return false;
  std::string haystack = ToLower(text);
  std::string needle = ToLower(token);
  return haystack.find(needle) != std::string::npos;
}

bool ContainsAnyToken(const DiscordRichPresence& presence,
                      const std::vector<const char*>& tokens) {
  for (const char* token : tokens) {
    if (ContainsToken(presence.state, token) ||
        ContainsToken(presence.details, token)) {
      return true;
    }
  }
  return false;
}

bool LooksLikeLobby(const DiscordRichPresence& presence) {
  static const std::vector<const char*> tokens = {
      "lobby",
      "menu",
      "front end",
      "frontend",
      "battle pass",
      "locker",
      "item shop",
      "playlist",
      "matchmaking",
      "queue",
      "party",
      "ready up",
      "pre-game",
      "pregame",
  };
  return ContainsAnyToken(presence, tokens);
}

int InferAliveCount(const DiscordRichPresence& presence) {
  // In many FN builds these are reused as in-match counters.
  if (presence.partySize > 0 && presence.partyMax >= 90 &&
      presence.partyMax <= 200 && presence.partySize <= presence.partyMax) {
    return presence.partySize;
  }
  return -1;
}

bool LooksLikeInGame(const DiscordRichPresence& presence) {
  static const std::vector<const char*> tokens = {
      "in game",
      "in-game",
      "match",
      "storm",
      "elims",
      "elimination",
      "bus",
      "alive",
      "spectating",
      "spectate",
      "top ",
      "victory",
  };
  if (ContainsAnyToken(presence, tokens)) return true;
  if (InferAliveCount(presence) > 0) return true;
  return false;
}

std::string BuildStateLine(const DiscordRichPresence& presence) {
  if (LooksLikeLobby(presence)) {
    return "In Lobby";
  }
  if (LooksLikeInGame(presence)) {
    return "In-Game";
  }
  return "In-Game";
}

std::string BuildHoverText(const DiscordRichPresence& presence) {
  const int alive = InferAliveCount(presence);
  std::string text = std::string(kBuildHoverPrefix) + gDetectedBuildLabel;
  if (alive > 0) {
    text += " | ";
    text += std::to_string(alive);
    text += " Left";
  }
  return text;
}

std::string JsonEscape(const char* text) {
  if (text == nullptr) return std::string();
  std::string escaped;
  escaped.reserve(std::strlen(text) + 8);
  for (const unsigned char c : std::string(text)) {
    switch (c) {
      case '\"':
        escaped += "\\\"";
        break;
      case '\\':
        escaped += "\\\\";
        break;
      case '\b':
        escaped += "\\b";
        break;
      case '\f':
        escaped += "\\f";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        if (c < 0x20) {
          char hex[7] = {};
          std::snprintf(hex, sizeof(hex), "\\u%04x", static_cast<unsigned>(c));
          escaped += hex;
        } else {
          escaped.push_back(static_cast<char>(c));
        }
        break;
    }
  }
  return escaped;
}

void AppendJsonStringField(
    std::string& json,
    bool& firstField,
    const char* key,
    const char* value) {
  if (value == nullptr || value[0] == '\0') return;
  if (!firstField) json += ",";
  firstField = false;
  json += "\"";
  json += key;
  json += "\":\"";
  json += JsonEscape(value);
  json += "\"";
}

std::string BuildActivityJson(const DiscordRichPresence& presence) {
  std::string json = "{";
  bool first = true;

  AppendJsonStringField(json, first, "state", presence.state);
  AppendJsonStringField(json, first, "details", presence.details);

  if (presence.startTimestamp > 0 || presence.endTimestamp > 0) {
    if (!first) json += ",";
    first = false;
    json += "\"timestamps\":{";
    bool tsFirst = true;
    if (presence.startTimestamp > 0) {
      json += "\"start\":";
      json += std::to_string(presence.startTimestamp);
      tsFirst = false;
    }
    if (presence.endTimestamp > 0) {
      if (!tsFirst) json += ",";
      json += "\"end\":";
      json += std::to_string(presence.endTimestamp);
    }
    json += "}";
  }

  if ((presence.largeImageKey != nullptr && presence.largeImageKey[0] != '\0') ||
      (presence.largeImageText != nullptr &&
       presence.largeImageText[0] != '\0') ||
      (presence.smallImageKey != nullptr && presence.smallImageKey[0] != '\0') ||
      (presence.smallImageText != nullptr &&
       presence.smallImageText[0] != '\0')) {
    if (!first) json += ",";
    first = false;
    json += "\"assets\":{";
    bool assetsFirst = true;
    AppendJsonStringField(
        json, assetsFirst, "large_image", presence.largeImageKey);
    AppendJsonStringField(
        json, assetsFirst, "large_text", presence.largeImageText);
    AppendJsonStringField(
        json, assetsFirst, "small_image", presence.smallImageKey);
    AppendJsonStringField(
        json, assetsFirst, "small_text", presence.smallImageText);
    json += "}";
  }

  if (kDiscordButtonLabel[0] != '\0' && kDiscordButtonUrl[0] != '\0') {
    if (!first) json += ",";
    first = false;
    json += "\"buttons\":[{\"label\":\"";
    json += JsonEscape(kDiscordButtonLabel);
    json += "\",\"url\":\"";
    json += JsonEscape(kDiscordButtonUrl);
    json += "\"}]";
  }

  json += "}";
  return json;
}

void UpdateEffectiveApplicationId(const char* appId) {
  std::lock_guard<std::mutex> lock(gEffectiveApplicationIdMutex);
  gEffectiveApplicationId = appId != nullptr ? appId : "";
}

std::string ReadEffectiveApplicationId() {
  std::lock_guard<std::mutex> lock(gEffectiveApplicationIdMutex);
  if (!gEffectiveApplicationId.empty()) return gEffectiveApplicationId;
  if (kOverrideApplicationId[0] != '\0') return kOverrideApplicationId;
  return std::string();
}

void PushActivityWithButton(const DiscordRichPresence& presence) {
  const std::string appId = ReadEffectiveApplicationId();
  if (appId.empty()) return;
  const std::string activityJson = BuildActivityJson(presence);
  if (!gDiscordIpcClient.SetActivity(appId, activityJson)) {
    AppendLog("Discord IPC overlay SetActivity failed.");
  }
}

void ClearActivityWithButton() {
  const std::string appId = ReadEffectiveApplicationId();
  if (appId.empty()) return;
  if (!gDiscordIpcClient.ClearActivity(appId)) {
    AppendLog("Discord IPC overlay ClearActivity failed.");
  }
}

}  // namespace

extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    gSelfModule = instance;
    DisableThreadLibraryCalls(instance);
    gDetectedBuildLabel = DetectBuildLabelFromModulePath();
    gDetectedVersionTag = BuildVersionTagFromBuildLabel(gDetectedBuildLabel);
    AppendLog("Proxy DLL attached.");
    AppendLog("Detected build label: " + gDetectedBuildLabel);
    AppendLog("Detected version tag: " + gDetectedVersionTag);
  }
  return TRUE;
}

extern "C" __declspec(dllexport) void __cdecl Discord_Initialize(
    const char* applicationId,
    DiscordEventHandlers* handlers,
    int autoRegister,
    const char* optionalSteamId) {
  const auto fn =
      ResolveExport<FnDiscord_Initialize>("Discord_Initialize");
  AppendLog(
      std::string("Discord_Initialize appId=") + SafeText(applicationId) +
      " autoRegister=" + std::to_string(autoRegister) +
      " steamId=" + SafeText(optionalSteamId));
  const char* effectiveAppId = applicationId;
  if (kOverrideApplicationId[0] != '\0') {
    effectiveAppId = kOverrideApplicationId;
  }
  UpdateEffectiveApplicationId(effectiveAppId);
  if (fn != nullptr) {
    fn(effectiveAppId, handlers, autoRegister, optionalSteamId);
  } else {
    AppendLog("Discord_Initialize skipped: forward export not found.");
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_Shutdown() {
  const auto fn = ResolveExport<FnDiscord_Shutdown>("Discord_Shutdown");
  if (fn != nullptr) {
    fn();
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_RunCallbacks() {
  const auto fn = ResolveExport<FnDiscord_RunCallbacks>("Discord_RunCallbacks");
  if (fn != nullptr) {
    fn();
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_UpdatePresence(
    const DiscordRichPresence* presence) {
  const auto fn =
      ResolveExport<FnDiscord_UpdatePresence>("Discord_UpdatePresence");
  if (fn == nullptr) {
    AppendLog("Discord_UpdatePresence skipped: forward export not found.");
    return;
  }

  if (presence == nullptr) {
    AppendLog("Discord_UpdatePresence called with null presence.");
    fn(nullptr);
    return;
  }

  DiscordRichPresence patched = *presence;
  gPatchedStateStorage = BuildStateLine(*presence);
  patched.state = gPatchedStateStorage.c_str();
  patched.details = kMainDetailsLine;
  patched.largeImageKey =
      OverrideOrOriginal(patched.largeImageKey, kAtlasLargeImageKey);
  patched.smallImageKey =
      OverrideOrOriginal(patched.smallImageKey, kAtlasSmallImageKey);
  patched.largeImageText = kLargeImageHoverText;
  patched.smallImageText = gDetectedVersionTag.c_str();

  const int seen = gLoggedPresenceUpdates.fetch_add(1);
  if (seen < 12) {
    AppendLog(
        std::string("Discord_UpdatePresence incoming(state=") +
        SafeText(presence->state) + ", details=" + SafeText(presence->details) +
        ", partySize=" + std::to_string(presence->partySize) +
        ", partyMax=" + std::to_string(presence->partyMax) +
        ", largeImageKey=" + SafeText(presence->largeImageKey) +
        ", smallImageKey=" + SafeText(presence->smallImageKey) +
        ") outgoing(state=" + SafeText(patched.state) +
        ", details=" + SafeText(patched.details) +
        ", largeImageKey=" + SafeText(patched.largeImageKey) +
        ", smallImageKey=" + SafeText(patched.smallImageKey) +
        ", smallImageText=" + SafeText(patched.smallImageText) + ")");
  }
  fn(&patched);
}

extern "C" __declspec(dllexport) void __cdecl Discord_ClearPresence() {
  const auto fn = ResolveExport<FnDiscord_ClearPresence>("Discord_ClearPresence");
  if (fn != nullptr) {
    fn();
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_Respond(
    const char* userId,
    int reply) {
  const auto fn = ResolveExport<FnDiscord_Respond>("Discord_Respond");
  if (fn != nullptr) {
    fn(userId, reply);
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_UpdateHandlers(
    DiscordEventHandlers* handlers) {
  const auto fn =
      ResolveExport<FnDiscord_UpdateHandlers>("Discord_UpdateHandlers");
  if (fn != nullptr) {
    fn(handlers);
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_Register(
    const char* applicationId,
    const char* command) {
  const auto fn = ResolveExport<FnDiscord_Register>("Discord_Register");
  if (fn != nullptr) {
    fn(applicationId, command);
  }
}

extern "C" __declspec(dllexport) void __cdecl Discord_RegisterSteamGame(
    const char* applicationId,
    const char* steamId) {
  const auto fn = ResolveExport<FnDiscord_RegisterSteamGame>(
      "Discord_RegisterSteamGame");
  if (fn != nullptr) {
    fn(applicationId, steamId);
  }
}
