#pragma once
// Reconstructed for 3.6.1: the recovered 3.6.0 kit omitted this header.
// Reads Steam metadata only; never executes a discovered game.
#include "core.hpp"
#include <cctype>

namespace discovery_detail {
class VdfReader {
  const std::string &text;
  size_t position = 0, tokens = 0;
  void space() {
    for (;;) {
      while (position < text.size() && std::isspace(static_cast<unsigned char>(text[position]))) ++position;
      if (position + 1 < text.size() && text[position] == '/' && text[position + 1] == '/') {
        while (position < text.size() && text[position] != '\n') ++position;
      } else return;
    }
  }
  std::string quoted() {
    space();
    if (position >= text.size() || text[position++] != '"' || ++tokens > 100000) throw std::runtime_error("Invalid VDF token");
    std::string value;
    while (position < text.size()) {
      char c = text[position++];
      if (c == '"') return value;
      if (c == '\\' && position < text.size() && (text[position] == '\\' || text[position] == '"')) c = text[position++];
      if (!c || value.size() >= 32768) throw std::runtime_error("Invalid VDF string");
      value += c;
    }
    throw std::runtime_error("Unterminated VDF string");
  }
  J object(int depth, bool nested) {
    if (depth > 32) throw std::runtime_error("VDF depth exceeded");
    J result = J::object();
    for (;;) {
      space();
      if (position == text.size()) { if (nested) throw std::runtime_error("Unterminated VDF object"); return result; }
      if (text[position] == '}') { if (!nested) throw std::runtime_error("Unexpected VDF closing brace"); ++position; return result; }
      auto key = quoted();
      if (result.contains(key)) throw std::runtime_error("Duplicate VDF key");
      space();
      if (position < text.size() && text[position] == '{') { ++position; result[key] = object(depth + 1, true); }
      else result[key] = quoted();
    }
  }
public:
  explicit VdfReader(const std::string &s) : text(s) { if (text.size() >= 3 && text.compare(0, 3, "\xef\xbb\xbf") == 0) position = 3; }
  J read() { return object(0, false); }
};
inline J readVdf(const fs::path &path) {
  try {
    std::error_code ec;
    if (!fs::is_regular_file(path, ec) || fs::file_size(path, ec) > 4 * 1024 * 1024 || ec) return J::object();
    std::ifstream stream(path, std::ios::binary);
    std::string text((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    return VdfReader(text).read();
  } catch (...) { return J::object(); }
}
inline fs::path canonical(const fs::path &path) {
  std::error_code ec;
  auto result = fs::weakly_canonical(path, ec);
  return ec ? path.lexically_normal() : result;
}
inline std::wstring key(const fs::path &path) { return lower(discovery_detail::canonical(path).wstring()); }
inline bool below(const fs::path &root, const fs::path &file) {
  auto base = key(root), target = key(file);
  if (base.empty()) return false;
  if (base.back() != L'\\') base += L'\\';
  return target.size() > base.size() && target.compare(0, base.size(), base) == 0;
}
inline std::wstring registry(HKEY hive, const wchar_t *keyName, const wchar_t *value, REGSAM view = 0) {
  wchar_t buffer[32768]{}; DWORD bytes = sizeof(buffer);
  if (RegGetValueW(hive, keyName, value, RRF_RT_REG_SZ | view, nullptr, buffer, &bytes) != ERROR_SUCCESS) return {};
  return buffer;
}
}

inline std::vector<fs::path> steamLibrariesFrom(const std::vector<fs::path> &roots) {
  std::vector<fs::path> result; std::set<std::wstring> seen;
  auto add = [&](const fs::path &path) {
    std::error_code ec;
    if (!path.is_absolute() || !fs::is_directory(path / L"steamapps", ec)) return;
    auto normal = discovery_detail::canonical(path);
    if (seen.insert(discovery_detail::key(normal)).second) result.push_back(normal);
  };
  for (const auto &root : roots) {
    add(root);
    auto document = discovery_detail::readVdf(root / L"steamapps/libraryfolders.vdf");
    if (!document.contains("libraryfolders") || !document["libraryfolders"].is_object()) continue;
    for (const auto &entry : document["libraryfolders"].items()) {
      if (entry.key().empty() || !std::all_of(entry.key().begin(), entry.key().end(), [](unsigned char c){ return std::isdigit(c); })) continue;
      if (entry.value().is_string()) add(wide(entry.value().get<std::string>()));
      else if (entry.value().is_object() && entry.value().contains("path") && entry.value()["path"].is_string()) add(wide(entry.value()["path"].get<std::string>()));
    }
  }
  return result;
}

inline std::vector<fs::path> steamLibraries() {
  std::vector<fs::path> roots;
  for (const auto &path : {
      discovery_detail::registry(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath"),
      discovery_detail::registry(HKEY_LOCAL_MACHINE, L"Software\\Valve\\Steam", L"InstallPath", RRF_SUBKEY_WOW6432KEY),
      discovery_detail::registry(HKEY_LOCAL_MACHINE, L"Software\\Valve\\Steam", L"InstallPath", RRF_SUBKEY_WOW6464KEY)}) if (!path.empty()) roots.emplace_back(path);
  return steamLibrariesFrom(roots);
}

inline J discoverSteamGames(const std::vector<fs::path> &libraries) {
  struct Known { const char *id, *name; const wchar_t *exe; };
  const Known games[] = {{"714010", "Aimlabs", L"AimLab_tb.exe"}, {"730", "Counter-Strike 2", L"game/bin/win64/cs2.exe"}, {"578080", "PUBG", L"TslGame/Binaries/Win64/TslGame.exe"}};
  J result = J::array(); std::set<std::wstring> seen;
  for (const auto &library : libraries) for (const auto &game : games) {
    auto manifest = discovery_detail::readVdf(library / L"steamapps" / (L"appmanifest_" + wide(game.id) + L".acf"));
    if (!manifest.contains("AppState") || !manifest["AppState"].is_object()) continue;
    const auto &state = manifest["AppState"];
    if (!state.contains("appid") || !state["appid"].is_string() || state["appid"] != game.id || !state.contains("installdir") || !state["installdir"].is_string()) continue;
    auto name = wide(state["installdir"].get<std::string>());
    if (name.empty() || name == L"." || name == L".." || name.find_first_of(L"/\\:") != std::wstring::npos) continue;
    auto common = library / L"steamapps/common", executable = common / name / game.exe;
    std::error_code ec;
    if (!discovery_detail::below(common, executable) || !fs::is_regular_file(executable, ec)) continue;
    executable = discovery_detail::canonical(executable);
    if (!seen.insert(discovery_detail::key(executable)).second) continue;
    result.push_back({{"Name", game.name}, {"Path", utf8(executable.wstring())}, {"SteamAppId", game.id}, {"AddedUtc", now()}});
  }
  return result;
}

inline int mergeDetectedGames(J &config, const J &found) {
  if (!config.is_object() || (config.contains("Games") && !config["Games"].is_array()) || !found.is_array()) throw std::runtime_error("Configuration des jeux invalide");
  J games = config.value("Games", J::array()); std::set<std::wstring> seen;
  for (const auto &game : games) if (game.is_object() && game.contains("Path") && game["Path"].is_string()) seen.insert(discovery_detail::key(wide(game["Path"].get<std::string>())));
  int added = 0;
  for (const auto &game : found) {
    if (!game.is_object() || !game.contains("Path") || !game["Path"].is_string()) continue;
    fs::path path = wide(game["Path"].get<std::string>()); std::error_code ec;
    if (!path.is_absolute() || lower(path.extension().wstring()) != L".exe" || !fs::is_regular_file(path, ec)) continue;
    Proc proc{0, 0, path.wstring(), lower(path.stem().wstring()), false};
    try { if (blocked(proc, config)) continue; } catch (...) { continue; }
    if (seen.insert(discovery_detail::key(path)).second) { games.push_back(game); ++added; }
  }
  if (added) config["Games"] = std::move(games);
  return added;
}
