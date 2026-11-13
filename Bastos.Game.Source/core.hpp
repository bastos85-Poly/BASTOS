#pragma once
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#define NOMINMAX
#include <windows.h>

#include "json.hpp"
#include <algorithm>
#include <cmath>
#include <commctrl.h>
#include <commdlg.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <shellapi.h>
#include <sstream>
#include <tlhelp32.h>
#include <vector>

using J = nlohmann::json;
namespace fs = std::filesystem;
inline std::string utf8(const std::wstring &s) {
  if (s.empty())
    return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), 0, 0, 0, 0);
  std::string r(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), r.data(), n, 0, 0);
  return r;
}
inline std::wstring wide(const std::string &s) {
  if (s.empty())
    return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), 0, 0);
  std::wstring r(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), r.data(), n);
  return r;
}
inline std::wstring lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(), towlower);
  return s;
}
inline std::string now() {
  SYSTEMTIME t;
  GetSystemTime(&t);
  char b[48];
  sprintf(b, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", t.wYear, t.wMonth, t.wDay,
          t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
  return b;
}
inline J readJson(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  if (!f)
    throw std::runtime_error("Fichier inaccessible : " + utf8(p.wstring()));
  return J::parse(f);
}
inline void atomicJson(const fs::path &p, const J &j) {
  fs::create_directories(p.parent_path());
  auto tmp = p;
  tmp += L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
  std::string s = j.dump(2);
  HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, 0, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, 0);
  if (h == INVALID_HANDLE_VALUE)
    throw std::runtime_error("Écriture impossible");
  DWORD n = 0;
  bool ok = WriteFile(h, s.data(), (DWORD)s.size(), &n, 0) && n == s.size() &&
            FlushFileBuffers(h);
  CloseHandle(h);
  if (!ok || !MoveFileExW(tmp.c_str(), p.c_str(),
                          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("Enregistrement atomique impossible : " +
                             utf8(p.wstring()));
}
struct Handle {
  HANDLE h = 0;
  Handle(HANDLE x = 0) : h(x) {}
  ~Handle() {
    if (h && h != INVALID_HANDLE_VALUE)
      CloseHandle(h);
  }
  operator HANDLE() const { return h; }
  Handle(const Handle &) = delete;
};
inline uint64_t creation(HANDLE h) {
  FILETIME a, b, c, d;
  if (!GetProcessTimes(h, &a, &b, &c, &d))
    return 0;
  return (uint64_t(a.dwHighDateTime) << 32) | a.dwLowDateTime;
}
inline std::wstring pathOf(HANDLE h) {
  wchar_t b[32768];
  DWORD n = 32768;
  return QueryFullProcessImageNameW(h, 0, b, &n) ? std::wstring(b, n) : L"";
}
struct Paths {
  fs::path config, status, stop, log, recovery, app, icon, profiles, sessions;
};
inline Paths pathsFrom(int argc, wchar_t **argv) {
  wchar_t env[32768];
  GetEnvironmentVariableW(L"LOCALAPPDATA", env, 32768);
  fs::path root = fs::path(env) / L"BASTOS" / L"Bastos Game";
  Paths p{root / L"Config.json",
          root / L"Status.json",
          root / L"Stop.request",
          root.parent_path() / L"Logs" / L"Bastos-Game.log",
          root / L"Recovery.json",
          fs::path(env) / L"Programs/BASTOS/Bastos.Native/BASTOS-Native.exe",
          fs::path(env) / L"Programs/BASTOS/Assets/Bastos-Game-Tray.ico"};
  for (int i = 1; i + 1 < argc; i++) {
    std::wstring k = argv[i];
    fs::path v = argv[i + 1];
    if (k == L"--config")
      p.config = v;
    else if (k == L"--status")
      p.status = v;
    else if (k == L"--stop")
      p.stop = v;
    else if (k == L"--recovery")
      p.recovery = v;
    else if (k == L"--log")
      p.log = v;
    else if (k == L"--app")
      p.app = v;
    else if (k == L"--icon")
      p.icon = v;
  }
  p.profiles = p.config.parent_path() / L"Profiles.json";
  p.sessions = p.config.parent_path() / L"Sessions";
  return p;
}
inline J defaultProfiles() {
  return {{"Version", 3},
          {"ObserveOnly", false},
          {"OptimizeAuxiliary", true},
          {"ThreadPriorities", true},
          {"BackgroundEcoQoS", true},
          {"BackgroundIoPriority", true},
          {"DefaultPriority", "AboveNormal"},
          {"Games", J::object()}};
}
inline J loadProfiles(const Paths &p) {
  return fs::exists(p.profiles) ? readJson(p.profiles) : defaultProfiles();
}
inline DWORD priorityValue(const std::string &s) {
  if (s == "Normal")
    return ABOVE_NORMAL_PRIORITY_CLASS; // Migrate old profiles to the game
                                        // minimum.
  if (s == "AboveNormal")
    return ABOVE_NORMAL_PRIORITY_CLASS;
  if (s == "High")
    return HIGH_PRIORITY_CLASS;
  throw std::runtime_error("Priorité invalide");
}
inline std::string priorityLabel(DWORD v) {
  if (v == 32)
    return "Normale";
  if (v == 128)
    return "Élevée";
  if (v == 32768)
    return "Supérieure à la normale";
  if (v == 16384)
    return "Inférieure à la normale";
  return std::to_string(v);
}
struct Proc {
  DWORD pid;
  uint64_t born;
  std::wstring path, name;
  bool window = false;
};
inline bool blocked(const Proc &p, const J &config) {
  static const std::set<std::wstring> names = {L"steam",
                                               L"steamservice",
                                               L"steamwebhelper",
                                               L"epicgameslauncher",
                                               L"galaxyclient",
                                               L"battle.net",
                                               L"agent",
                                               L"discord",
                                               L"obs32",
                                               L"obs64",
                                               L"streamlabs obs",
                                               L"streamlabs",
                                               L"sharex",
                                               L"radeonsoftware",
                                               L"gamebar",
                                               L"gamebarftserver",
                                               L"xboxgamebar",
                                               L"overwolf",
                                               L"medal",
                                               L"chrome",
                                               L"msedge",
                                               L"firefox",
                                               L"opera",
                                               L"brave",
                                               L"explorer",
                                               L"powershell",
                                               L"pwsh",
                                               L"cmd",
                                               L"code",
                                               L"devenv",
                                               L"bastos-game",
                                               L"bastos-native",
                                               L"execpubg",
                                               L"tslgame_be",
                                               L"beservice",
                                               L"easyanticheat",
                                               L"easyanticheat_eos",
                                               L"battleye",
                                               L"zksvc"};
  if (names.count(p.name))
    return true;
  for (auto &a : config.value("BlockedApps", J::array())) {
    auto n = lower(fs::path(wide(a.value("Name", ""))).stem().wstring());
    auto path = lower(fs::path(wide(a.value("Path", ""))).lexically_normal().make_preferred().wstring());
    auto processPath = lower(fs::path(p.path).lexically_normal().make_preferred().wstring());
    if ((!n.empty() && n == p.name) || (!path.empty() && path == processPath))
      return true;
  }
  return false;
}
inline bool automatic(const Proc &p, const J &c) {
  if (!c.value("AutoDetect", true) || !p.window || blocked(p, c))
    return false;
  auto s = lower(p.path);
  for (auto m : {L"\\steamapps\\common\\", L"\\epic games\\", L"\\xboxgames\\",
                 L"\\gog galaxy\\games\\", L"\\gog games\\", L"\\riot games\\",
                 L"\\battle.net\\",
                 L"\\ubisoft\\ubisoft game launcher\\games\\", L"\\ea games\\"})
    if (s.find(m) != s.npos)
      return true;
  return false;
}
inline std::vector<Proc> processes() {
  std::set<DWORD> windows;
  EnumWindows(
      [](HWND w, LPARAM p) -> BOOL {
        DWORD id;
        GetWindowThreadProcessId(w, &id);
        if (IsWindowVisible(w) && GetWindow(w, GW_OWNER) == 0)
          ((std::set<DWORD> *)p)->insert(id);
        return TRUE;
      },
      (LPARAM)&windows);
  Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  PROCESSENTRY32W e{sizeof(e)};
  std::vector<Proc> out;
  DWORD session = 0;
  ProcessIdToSessionId(GetCurrentProcessId(), &session);
  if (Process32FirstW(snap, &e))
    do {
      DWORD s = 0;
      if (!ProcessIdToSessionId(e.th32ProcessID, &s) || s != session ||
          e.th32ProcessID == GetCurrentProcessId())
        continue;
      Handle h(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                           e.th32ProcessID));
      if (!h.h)
        continue;
      auto path = pathOf(h);
      auto born = creation(h);
      if (!path.empty() && born)
        out.push_back({e.th32ProcessID, born, path,
                       lower(fs::path(path).stem().wstring()),
                       windows.count(e.th32ProcessID) > 0});
    } while (Process32NextW(snap, &e));
  return out;
}
struct Power {
  ULONG Version = 1, ControlMask = 0, StateMask = 0;
};
// GDI32 exports the documented D3DKMT process-scheduling API. Resolve it at
// runtime so systems without the export can keep the CPU optimizations.
using GetGpuPriority = LONG(WINAPI *)(HANDLE, int *);
using SetGpuPriority = LONG(WINAPI *)(HANDLE, int);
struct GpuPriorityApi {
  GetGpuPriority get = nullptr;
  SetGpuPriority set = nullptr;
};
inline GpuPriorityApi gpuPriorityApi() {
  static GpuPriorityApi api = [] {
    HMODULE gdi = GetModuleHandleW(L"gdi32.dll");
    if (!gdi)
      gdi = LoadLibraryW(L"gdi32.dll");
    return gdi ? GpuPriorityApi{reinterpret_cast<GetGpuPriority>(GetProcAddress(
                                    gdi,
                                    "D3DKMTGetProcessSchedulingPriorityClass")),
                                reinterpret_cast<SetGpuPriority>(GetProcAddress(
                                    gdi,
                                    "D3DKMTSetProcessSchedulingPriorityClass"))}
               : GpuPriorityApi{};
  }();
  return api;
}
// Optional native I/O priority API: failures remain visible in the action
// report.
using QueryProcessInfo = LONG(WINAPI *)(HANDLE, ULONG, PVOID, ULONG, PULONG);
using SetProcessInfo = LONG(WINAPI *)(HANDLE, ULONG, PVOID, ULONG);
inline auto queryIoApi() {
  return reinterpret_cast<QueryProcessInfo>(GetProcAddress(
      GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationProcess"));
}
inline auto setIoApi() {
  return reinterpret_cast<SetProcessInfo>(GetProcAddress(
      GetModuleHandleW(L"ntdll.dll"), "NtSetInformationProcess"));
}
inline uint64_t threadCreation(HANDLE h) {
  FILETIME c{}, e{}, k{}, u{};
  return GetThreadTimes(h, &c, &e, &k, &u)
             ? (uint64_t(c.dwHighDateTime) << 32) | c.dwLowDateTime
             : 0;
}
inline J snapshot(HANDLE h) {
  J j = J::object();
  DWORD pri = GetPriorityClass(h);
  if (pri)
    j["Priority"] = pri;
  ULONG io = 0;
  if (auto q = queryIoApi();
      q && setIoApi() && q(h, 33, &io, sizeof(io), nullptr) == 0)
    j["IoPriority"] = io;
  BOOL boost;
  if (GetProcessPriorityBoost(h, &boost))
    j["BoostDisabled"] = bool(boost);
  Power p;
  if (GetProcessInformation(h, (PROCESS_INFORMATION_CLASS)4, &p, sizeof(p)))
    j["Power"] = {{"Control", p.ControlMask}, {"State", p.StateMask}};
  ULONG m = 0;
  if (GetProcessInformation(h, (PROCESS_INFORMATION_CLASS)0, &m, sizeof(m)))
    j["Memory"] = m;
  auto gpu = gpuPriorityApi();
  int gpuPriority = 0;
  if (gpu.get && gpu.set && gpu.get(h, &gpuPriority) == 0 && gpuPriority >= 0 &&
      gpuPriority <= 5)
    j["GpuPriority"] = gpuPriority;
  return j;
}
inline bool setSetting(HANDLE h, const std::string &k, const J &v) {
  if (k == "IoPriority") {
    ULONG io = v.get<ULONG>();
    auto fn = setIoApi();
    LONG status = fn ? fn(h, 33, &io, sizeof(io)) : LONG(0xC0000002);
    if (status != 0) {
      using Translate = ULONG(WINAPI *)(LONG);
      auto translate = reinterpret_cast<Translate>(GetProcAddress(
          GetModuleHandleW(L"ntdll.dll"), "RtlNtStatusToDosError"));
      SetLastError(translate ? translate(status) : ERROR_GEN_FAILURE);
    }
    return status == 0;
  }
  if (k == "Priority")
    return SetPriorityClass(h, v.get<DWORD>());
  if (k == "GpuPriority") {
    auto gpu = gpuPriorityApi();
    return gpu.set && gpu.set(h, v.get<int>()) == 0;
  }
  if (k == "BoostDisabled")
    return SetProcessPriorityBoost(h, v.get<bool>());
  if (k == "Power") {
    Power p;
    p.ControlMask = v.at("Control");
    p.StateMask = v.at("State");
    return SetProcessInformation(h, (PROCESS_INFORMATION_CLASS)4, &p,
                                 sizeof(p));
  }
  if (k == "Memory") {
    ULONG m = v;
    return SetProcessInformation(h, (PROCESS_INFORMATION_CLASS)0, &m,
                                 sizeof(m));
  }
  return false;
}
inline std::string settingLabel(const std::string &k, const J &v) {
  if (v.is_null())
    return "Non lisible";
  if (k == "IoPriority")
    return v == 0   ? "Très faible"
           : v == 1 ? "Faible"
           : v == 2 ? "Normale"
                    : v.dump();
  if (k == "Priority")
    return priorityLabel(v.get<DWORD>());
  if (k == "GpuPriority") {
    static const char *names[] = {"Inactive", "Inférieure à la normale",
                                  "Normale",  "Supérieure à la normale",
                                  "Haute",    "Temps réel"};
    int level = v.get<int>();
    return level >= 0 && level <= 5 ? names[level] : std::to_string(level);
  }
  if (k == "BoostDisabled")
    return v.get<bool>() ? "Boost limité" : "Boost actif";
  if (k == "Power") {
    unsigned c = v.at("Control"), s = v.at("State");
    return !(c & 1) ? "Géré par Windows"
                    : ((s & 1) ? "EcoQoS actif" : "EcoQoS désactivé");
  }
  if (k == "Memory")
    return v.get<int>() == 5 ? "Normale" : std::to_string(v.get<int>());
  return v.dump();
}
inline std::string settingName(const std::string &k) {
  if (k == "IoPriority")
    return "Priorité des entrées/sorties";
  if (k == "Priority")
    return "Priorité CPU";
  if (k == "GpuPriority")
    return "Priorité GPU du processus";
  if (k == "Power")
    return "Économie d'énergie";
  if (k == "BoostDisabled")
    return "Boost de priorité";
  if (k == "Memory")
    return "Priorité mémoire";
  return k;
}
inline J desired(const J &original, DWORD priority, bool game, bool eco = false,
                 bool io = false) {
  J j;
  j["Priority"] = priority;
  if (game) {
    if (original.contains("GpuPriority"))
      j["GpuPriority"] = 4; // D3DKMT_SCHEDULINGPRIORITYCLASS_HIGH.
    j["BoostDisabled"] = false;
    if (original.contains("Power")) {
      auto v = original["Power"];
      unsigned c = v["Control"], s = v["State"];
      j["Power"] = {{"Control", c | 1u}, {"State", s & ~1u}};
    }
    j["Memory"] = 5;
  }
  if (!game && eco && original.contains("Power")) {
    unsigned c = original["Power"]["Control"], s = original["Power"]["State"];
    j["Power"] = {{"Control", c | 1u}, {"State", s | 1u}};
  }
  if (!game && io)
    j["IoPriority"] = 0;
  return j;
}
struct Entry {
  Proc proc;
  J original, applied = J::object(), report = J::array(), threads = J::object();
  std::string role, policy, start;
};
class Engine {
public:
  Paths p;
  std::map<DWORD, Entry> entries;
  J status, restoration = J::array();
  std::string error, lastJournal;
  bool observe = false;
  explicit Engine(Paths x) : p(x) {}
  void log(const std::string &s) {
    try {
      fs::create_directories(p.log.parent_path());
      std::ofstream f(p.log, std::ios::app);
      f << now() << " " << s << "\n";
    } catch (...) {
    }
  }
  J record(const Entry &e) {
    return {{"Pid", e.proc.pid},         {"Creation", e.proc.born},
            {"Path", utf8(e.proc.path)}, {"Original", e.original},
            {"Applied", e.applied},      {"Role", e.role},
            {"StartedUtc", e.start},     {"Threads", e.threads}};
  }
  void journal() {
    J a = J::array();
    for (auto &[id, e] : entries)
      a.push_back(record(e));
    J doc = {{"Version", 3}, {"Processes", a}};
    auto serialized = doc.dump();
    if (serialized != lastJournal) {
      atomicJson(p.recovery, doc);
      lastJournal = serialized;
    }
  }
  bool restore(Entry &e) {
    Handle h(OpenProcess(PROCESS_QUERY_INFORMATION |
                             PROCESS_QUERY_LIMITED_INFORMATION |
                             PROCESS_SET_INFORMATION,
                         FALSE, e.proc.pid));
    if (!h.h) {
      Handle q(
          OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, e.proc.pid));
      if (q.h && creation(q) == e.proc.born) {
        restoration.push_back(
            {{"Name", utf8(e.proc.name)}, {"Outcome", "Échec : accès refusé"}});
        return false;
      }
      if (GetLastError() == ERROR_ACCESS_DENIED) {
        restoration.push_back({{"Name", utf8(e.proc.name)},
                               {"Outcome", "Échec : identité inaccessible"}});
        return false;
      }
      return true;
    }
    if (creation(h) != e.proc.born || lower(pathOf(h)) != lower(e.proc.path))
      return true;
    DWORD exit = 0;
    if (GetExitCodeProcess(h, &exit) && exit != STILL_ACTIVE)
      return true;
    bool ok = true;
    bool threadsOk = restoreThreads(e);
    ok = ok && threadsOk;
    J cur = snapshot(h);
    for (auto it = e.applied.begin(); it != e.applied.end();) {
      std::string k = it.key();
      std::string result;
      bool done = false;
      if (!cur.contains(k)) {
        result = "Restauration non vérifiable";
        ok = false;
      } else if (cur[k] != it.value()) {
        result = "Changement externe conservé";
        done = true;
      } else if (e.original.contains(k) && setSetting(h, k, e.original[k]) &&
                 snapshot(h).value(k, J()) == e.original[k]) {
        result = "Restauré et vérifié";
        done = true;
      } else {
        result = "Échec de restauration";
        ok = false;
      }
      restoration.push_back({{"Name", utf8(e.proc.name)},
                             {"Setting", settingName(k)},
                             {"Outcome", result}});
      if (done)
        it = e.applied.erase(it);
      else
        ++it;
    }
    return ok;
  }
  void finish(Entry &e) {
    if (e.role == "Game") {
      fs::create_directories(p.sessions);
      atomicJson(p.sessions / (std::to_wstring(e.proc.born) + L"-" +
                               std::to_wstring(e.proc.pid) + L"-" +
                               std::to_wstring(GetTickCount64()) + L".json"),
                 {{"Version", 3},
                  {"Game", utf8(e.proc.path)},
                  {"StartedUtc", e.start},
                  {"EndedUtc", now()},
                  {"Policy", e.policy},
                  {"Actions", e.report},
                  {"FrameMetrics", nullptr},
                  {"Note", "Historique des réglages appliqués. Aucun FPS mesuré."}});
    }
  }
  void recover() {
    if (!fs::exists(p.recovery))
      return;
    J r = readJson(p.recovery);
    for (auto &a : r.at("Processes")) {
      Entry e;
      e.proc = {a.at("Pid"), a.at("Creation"), wide(a.at("Path")), L"", false};
      e.proc.name = lower(fs::path(e.proc.path).stem().wstring());
      e.role = a.value("Role", "Recovery");
      e.start = a.value("StartedUtc", now());
      if (a.contains("Original")) {
        e.original = a.at("Original");
        e.applied = a.at("Applied");
        e.threads = a.value("Threads", J::object());
      } else { // Migration from the original Win32 engine. No last-applied
               // values were recorded.
        Handle h(
            OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, e.proc.pid));
        if (!h.h || creation(h) != e.proc.born ||
            lower(pathOf(h)) != lower(e.proc.path))
          continue;
        e.original["Priority"] = a.at("Priority");
        if (a.value("BoostValid", false))
          e.original["BoostDisabled"] = a.at("BoostDisabled");
        if (a.value("PowerValid", false))
          e.original["Power"] = {{"Control", a.at("PowerControl")},
                                 {"State", a.at("PowerState")}};
        if (a.value("MemoryValid", false))
          e.original["Memory"] = a.at("Memory");
        e.applied = snapshot(h);
        for (auto it = e.applied.begin(); it != e.applied.end();)
          if (!e.original.contains(it.key()))
            it = e.applied.erase(it);
          else
            ++it;
        log("Migration de la sauvegarde v1 pour " + utf8(e.proc.name));
      }
      if (!restore(e))
        entries[e.proc.pid] = e;
    }
    journal();
    log("Récupération des réglages précédents terminée ; échecs conservés pour "
        "réessai.");
  }
  void clear() {
    for (auto it = entries.begin(); it != entries.end();) {
      if (restore(it->second)) {
        finish(it->second);
        it = entries.erase(it);
      } else
        ++it;
    }
    journal();
  }
  void optimize(const Proc &proc, const std::string &role, DWORD pri,
                bool watch, bool threads = false, bool eco = false,
                bool io = false) {
    std::string policy =
        role + ":" + std::to_string(pri) + (watch ? ":Observe" : ":Apply") +
        (threads ? ":Threads" : "") + (eco ? ":Eco" : "") + (io ? ":Io" : "");
    auto found = entries.find(proc.pid);
    if (found != entries.end() && (found->second.proc.born != proc.born ||
                                   found->second.policy != policy)) {
      if (!restore(found->second))
        return;
      finish(found->second);
      entries.erase(found);
      journal();
    }
    Handle h(OpenProcess(PROCESS_QUERY_INFORMATION |
                             PROCESS_QUERY_LIMITED_INFORMATION |
                             PROCESS_SET_INFORMATION,
                         FALSE, proc.pid));
    DWORD openError = h.h ? 0 : GetLastError();
    Handle q(
        h.h ? nullptr
            : OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, proc.pid));
    HANDLE access = h.h ? h.h : q.h;
    if (access && (creation(access) != proc.born ||
                   lower(pathOf(access)) != lower(proc.path)))
      access = nullptr;
    auto &e = entries[proc.pid];
    bool fresh = e.start.empty();
    if (fresh) {
      e.proc = proc;
      e.original = access ? snapshot(access) : J::object();
      e.role = role;
      e.policy = policy;
      e.start = now();
      journal();
    }
    J cur = access ? snapshot(access) : J::object();
    // A new game may not have created its GPU context on the first scan.
    // Capture the original class when it becomes readable, before changing it.
    if (role == "Game" && !e.original.contains("GpuPriority") &&
        cur.contains("GpuPriority")) {
      e.original["GpuPriority"] = cur["GpuPriority"];
      journal();
    }
    J target = desired(e.original, pri, role == "Game", eco, io);
    e.report = J::array();
    for (auto &[k, v] : target.items()) {
      std::string outcome;
      DWORD err = 0;
      if (!cur.contains(k) || !e.original.contains(k)) {
        outcome = "Non lisible — non modifié";
        err = openError;
      } else if (watch) {
        outcome = "Observation — non modifié";
      } else if (fresh ||
                 (role == "Game" && (k == "Priority" || k == "GpuPriority") &&
                  cur[k] != v) ||
                 (k == "GpuPriority" && !e.applied.contains(k))) {
        if (cur[k] == v)
          outcome = "Déjà conforme";
        else if (!h.h || !access) {
          outcome = "Refusé par Windows";
          err = openError;
        } else {
          e.applied[k] = v;
          journal();
          SetLastError(0);
          if (!setSetting(h, k, v)) {
            err = GetLastError();
            outcome = "Refusé par Windows";
            e.applied.erase(k);
            journal();
          } else {
            cur = snapshot(h);
            outcome =
                cur.value(k, J()) == v ? "Appliqué et vérifié" : "Non confirmé";
          }
        }
      } else {
        outcome = cur[k] == v
                      ? "Conforme et vérifié"
                      : (e.applied.contains(k) ? "Changement externe détecté"
                                               : "Non appliqué");
      }
      e.report.push_back({{"Setting", settingName(k)},
                          {"Before", settingLabel(k, e.original.value(k, J()))},
                          {"Requested", settingLabel(k, v)},
                          {"Actual", settingLabel(k, cur.value(k, J()))},
                          {"Outcome", outcome},
                          {"Win32Error", err}});
    }
    if (role == "Game" && threads && access && creation(access) == proc.born)
      tuneThreads(e, watch);
  }
  // Thread records are durable before a write and tied to both owner and
  // creation time.
  bool restoreThreads(Entry &e) {
    bool ok = true;
    for (auto it = e.threads.begin(); it != e.threads.end();) {
      DWORD tid = std::stoul(it.key());
      Handle h(OpenThread(THREAD_QUERY_INFORMATION | THREAD_SET_INFORMATION,
                          FALSE, tid));
      bool done = false;
      std::string outcome;
      if (!h.h) {
        done = GetLastError() == ERROR_INVALID_PARAMETER;
        outcome = done ? "Thread terminé" : "Échec : accès au thread refusé";
      } else if (GetProcessIdOfThread(h) != e.proc.pid ||
                 threadCreation(h) !=
                     it.value().at("Creation").get<uint64_t>()) {
        done = true;
        outcome = "Identité remplacée — ignorée";
      } else {
        int cur = GetThreadPriority(h), applied = it.value().at("Applied"),
            original = it.value().at("Original");
        if (cur == THREAD_PRIORITY_ERROR_RETURN)
          outcome = "Restauration non vérifiable";
        else if (cur != applied) {
          done = true;
          outcome = "Changement externe conservé";
        } else {
          done = SetThreadPriority(h, original) &&
                 GetThreadPriority(h) == original;
          outcome = done ? "Restauré et vérifié" : "Échec de restauration";
        }
      }
      restoration.push_back({{"Name", utf8(e.proc.name)},
                             {"Setting", "Thread " + it.key()},
                             {"Outcome", outcome}});
      if (done)
        it = e.threads.erase(it);
      else {
        ok = false;
        ++it;
      }
    }
    return ok;
  }
  void tuneThreads(Entry &e, bool watch) {
    // Reap only confirmed exits/reused ids; unreadable live threads remain
    // recoverable.
    for (auto it = e.threads.begin(); it != e.threads.end();) {
      Handle h(OpenThread(THREAD_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE,
                          std::stoul(it.key())));
      bool gone = !h.h && GetLastError() == ERROR_INVALID_PARAMETER;
      if (h.h)
        gone = WaitForSingleObject(h, 0) == WAIT_OBJECT_0 ||
               GetProcessIdOfThread(h) != e.proc.pid ||
               (threadCreation(h) != 0 &&
                threadCreation(h) != it.value().at("Creation").get<uint64_t>());
      if (gone)
        it = e.threads.erase(it);
      else
        ++it;
    }
    journal();
    Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0));
    THREADENTRY32 t{sizeof(t)};
    if (!snap.h || snap.h == INVALID_HANDLE_VALUE || !Thread32First(snap, &t)) {
      e.report.push_back(
          {{"Setting", "Priorités des threads"},
           {"Outcome", "Inventaire inaccessible — non modifié"}});
      return;
    }
    struct Candidate {
      DWORD id;
      uint64_t born;
      std::wstring name;
    };
    std::vector<Candidate> candidates;
    using Description = HRESULT(WINAPI *)(HANDLE, PWSTR *);
    auto describe = reinterpret_cast<Description>(GetProcAddress(
        GetModuleHandleW(L"kernel32.dll"), "GetThreadDescription"));
    do {
      if (t.th32OwnerProcessID == e.proc.pid) {
        Handle h(OpenThread(THREAD_QUERY_INFORMATION, FALSE, t.th32ThreadID));
        if (!h.h || GetProcessIdOfThread(h) != e.proc.pid)
          continue;
        auto born = threadCreation(h);
        if (!born)
          continue;
        PWSTR text = nullptr;
        std::wstring name;
        if (describe && SUCCEEDED(describe(h, &text)) && text) {
          name = lower(text);
          LocalFree(text);
        }
        candidates.push_back({t.th32ThreadID, born, name});
      }
    } while (Thread32Next(snap, &t));
    uint64_t earliest = UINT64_MAX;
    for (auto &c : candidates)
      earliest = std::min(earliest, c.born);
    // Do not discard unobserved threads: access may be temporarily denied.
    for (auto &c : candidates) {
      bool selected = c.born == earliest;
      for (auto token : {L"render", L"audio", L"wasapi", L"input", L"rhi",
                         L"game thread", L"gamethread"})
        if (c.name.find(token) != std::wstring::npos)
          selected = true;
      if (!selected)
        continue;
      auto key = std::to_string(c.id);
      Handle h(OpenThread(THREAD_QUERY_INFORMATION |
                              (watch ? 0 : THREAD_SET_INFORMATION),
                          FALSE, c.id));
      std::string outcome;
      int before = THREAD_PRIORITY_ERROR_RETURN, actual = before;
      if (!h.h || GetProcessIdOfThread(h) != e.proc.pid ||
          threadCreation(h) != c.born)
        outcome = "Refusé ou identité changée";
      else {
        before = actual = GetThreadPriority(h);
        if (watch)
          outcome = "Observation — non modifié";
        else if (e.threads.contains(key) &&
                 e.threads[key]["Creation"] != c.born) {
          e.threads.erase(key);
          journal();
          outcome = "Identité remplacée — nouvel essai au prochain cycle";
        } else if (e.threads.contains(key))
          outcome = actual == e.threads[key]["Applied"]
                        ? "Conforme et vérifié"
                        : "Changement externe conservé";
        // Respect priorities already chosen by the game, including
        // negative/background values.
        else if (before != THREAD_PRIORITY_NORMAL)
          outcome = "Priorité choisie par le jeu conservée";
        else {
          e.threads[key] = {{"Creation", c.born},
                            {"Original", before},
                            {"Applied", THREAD_PRIORITY_ABOVE_NORMAL}};
          journal();
          if (!SetThreadPriority(h, THREAD_PRIORITY_ABOVE_NORMAL)) {
            outcome = "Refusé par Windows";
            e.threads.erase(key);
            journal();
          } else {
            actual = GetThreadPriority(h);
            outcome = actual == THREAD_PRIORITY_ABOVE_NORMAL
                          ? "Appliqué et vérifié"
                          : "Non confirmé";
          }
        }
      }
      e.report.push_back(
          {{"Setting",
            "Thread " + key +
                (c.name.empty() ? " (principal)" : " " + utf8(c.name))},
           {"Before", std::to_string(before)},
           {"Requested", "Supérieure à la normale (+1)"},
           {"Actual", std::to_string(actual)},
           {"Outcome", outcome}});
    }
  }
  void cycle() {
    try {
      J c = readJson(p.config), pr = loadProfiles(p);
      if (!c.is_object() || !c.value("Games", J::array()).is_array() ||
          !pr.is_object())
        throw std::runtime_error("Configuration invalide");
      observe = pr.value("ObserveOnly", false);
      DWORD defaultPri =
          priorityValue(pr.value("DefaultPriority", "AboveNormal"));
      auto all = processes();
      std::set<DWORD> wanted;
      J games = J::array(), aux = J::array(), background = J::array();
      std::vector<std::wstring> pubgRoots;
      bool applyingGame = false;
      auto overrides = pr.value("Games", J::object());
      for (auto &proc : all) {
        bool forced = false;
        for (auto &g : c.value("Games", J::array()))
          if (lower(wide(g.value("Path", ""))) == lower(proc.path))
            forced = true;
        if (!c.value("Enabled", true) || blocked(proc, c) ||
            (!forced && !automatic(proc, c)))
          continue;
        DWORD pri = defaultPri;
        bool watch = observe;
        bool threadPriority = pr.value("ThreadPriorities", true);
        bool auxiliary = pr.value("OptimizeAuxiliary", true);
        auto key = utf8(lower(proc.path));
        if (overrides.contains(key)) {
          auto v = overrides[key];
          pri = priorityValue(
              v.value("Priority", pr.value("DefaultPriority", "AboveNormal")));
          watch = observe || v.value("ObserveOnly", false);
          threadPriority = v.value("ThreadPriorities", threadPriority);
          auxiliary = v.value("OptimizeAuxiliary", auxiliary);
        }
        optimize(proc, "Game", pri, watch, threadPriority);
        wanted.insert(proc.pid);
        if (!watch)
          applyingGame = true;
        auto &e = entries.at(proc.pid);
        games.push_back(
            {{"Name", utf8(proc.name)},
             {"Path", utf8(proc.path)},
             {"ProcessId", proc.pid},
             {"Detection", forced ? "Forced" : "Automatic"},
             {"Profile", proc.name == L"tslgame" ? "PUBG" : "Personnalisable"},
             {"Applied", watch ? "Observation sans modification"
                               : "Consulter les résultats vérifiés"},
             {"Actions", e.report},
             {"ObserveOnly", watch}});
        if (proc.name == L"tslgame" && !watch && auxiliary) {
          auto s = lower(proc.path);
          auto pos = s.find(L"\\pubg\\");
          if (pos != s.npos)
            pubgRoots.push_back(s.substr(0, pos + 6));
        }
      }
      static const std::set<std::wstring> bg = {
          L"discord",    L"chrome",  L"msedge",         L"firefox",
          L"opera",      L"brave",   L"steamwebhelper", L"epicgameslauncher",
          L"battle.net", L"onedrive"};
      if (applyingGame && !observe)
        for (auto &proc : all) {
          if (wanted.count(proc.pid))
            continue;
          bool helper = false;
          if (proc.name == L"execpubg")
            for (auto &root : pubgRoots)
              if (lower(proc.path).rfind(root, 0) == 0)
                helper = true;
          bool other =
              c.value("OptimizeBackground", false) && bg.count(proc.name);
          if (!helper && !other)
            continue; // Exclusions also protect background applications.
          bool userBlocked = false;
          for (auto &b : c.value("BlockedApps", J::array()))
            if (lower(wide(b.value("Path", ""))) == lower(proc.path) ||
                lower(fs::path(wide(b.value("Name", ""))).stem().wstring()) ==
                    proc.name)
              userBlocked = true;
          if (userBlocked)
            continue;
          optimize(proc, helper ? "Auxiliary" : "Background",
                   BELOW_NORMAL_PRIORITY_CLASS, false, false,
                   other && pr.value("BackgroundEcoQoS", true),
                   other && pr.value("BackgroundIoPriority", true));
          wanted.insert(proc.pid);
          J item = {{"Name", utf8(proc.name)},
                    {"ProcessId", proc.pid},
                    {"Actions", entries.at(proc.pid).report}};
          (helper ? aux : background).push_back(item);
        }
      for (auto it = entries.begin(); it != entries.end();)
        if (!wanted.count(it->first)) {
          if (restore(it->second)) {
            finish(it->second);
            it = entries.erase(it);
          } else
            ++it;
        } else
          ++it;
      journal();
      error.clear();
      status = {{"Version", 3},
                {"Engine", "Native Win32"},
                {"EngineVersion", "3.6.1"},
                {"UpdatedUtc", now()},
                {"ProcessId", GetCurrentProcessId()},
                {"State", c.value("Enabled", true) ? "Ready" : "Stopped"},
                {"Error", ""},
                {"ObserveOnly", observe},
                {"ActiveGames", games},
                {"AuxiliaryProcesses", aux},
                {"BackgroundProcesses", background},
                {"OptimizedAuxiliary", aux.size()},
                {"OptimizedBackground", background.size()},
                {"Restoration", restoration}};
      if (restoration.size() > 100)
        restoration.erase(restoration.begin(), restoration.end() - 100);
      atomicJson(p.status, status);
    } catch (const std::exception &ex) {
      error = ex.what();
      try {
        clear();
      } catch (...) {
      }
      status = {{"Version", 3},
                {"EngineVersion", "3.6.1"},
                {"UpdatedUtc", now()},
                {"ProcessId", GetCurrentProcessId()},
                {"State", "Error"},
                {"Error", error},
                {"ActiveGames", J::array()},
                {"Restoration", restoration}};
      atomicJson(p.status, status);
      log(error);
    }
  }
  void stop() {
    clear();
    status["UpdatedUtc"] = now();
    status["State"] = error.empty() ? "Stopped" : "Error";
    status["ActiveGames"] = J::array();
    status["Restoration"] = restoration;
    status["PendingRestoration"] = entries.size();
    atomicJson(p.status, status);
    log("Moteur arrêté ; restauration vérifiée, " +
        std::to_string(entries.size()) + " processus en attente.");
  }
};
