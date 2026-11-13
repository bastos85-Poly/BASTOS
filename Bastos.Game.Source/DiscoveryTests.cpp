#include "discovery.hpp"
#include <iostream>
int wmain(int argc, wchar_t **argv) {
  int count = 0;
  auto check = [&](bool ok, const char *name) { if (!ok) throw std::runtime_error(name); ++count; std::cout << "OK : " << name << '\n'; };
  try {
    if (argc != 2) throw std::runtime_error("Supply a new fixture directory");
    fs::path root = fs::absolute(argv[1]);
    if (fs::exists(root)) throw std::runtime_error("Fixture already exists");
    fs::create_directories(root);
    auto write = [](const fs::path &p, const std::string &s) { fs::create_directories(p.parent_path()); std::ofstream(p, std::ios::binary) << s; };
    auto steam = root / L"Steam", other = root / L"Autre bibliotheque";
    fs::create_directories(steam / L"steamapps");fs::create_directories(other / L"steamapps");
    auto folderText = "\xef\xbb\xbf// fixture\n\"libraryfolders\" { \"0\" { \"path\" " + J(utf8(steam.wstring())).dump() + " } \"1\" { \"path\" " + J(utf8(other.wstring())).dump() + " } \"2\" " + J(utf8(other.wstring())).dump() + " }";
    write(steam / L"steamapps/libraryfolders.vdf", folderText);
    auto libraries = steamLibrariesFrom({steam, steam});
    check(libraries.size() == 2, "Modern and legacy library entries, duplicates removed");
    auto manifest = [&](const fs::path &library, const char *id, const char *dir, const char *manifestId = nullptr) {
      write(library / L"steamapps" / (L"appmanifest_" + wide(id) + L".acf"), "\"AppState\" { \"appid\" " + J(manifestId ? manifestId : id).dump() + " \"installdir\" " + J(dir).dump() + " }");
    };
    auto aim = steam / L"steamapps/common/Aimlabs/AimLab_tb.exe";
    auto cs = other / L"steamapps/common/Counter Strike/game/bin/win64/cs2.exe";
    auto pubg = other / L"steamapps/common/PUBG/TslGame/Binaries/Win64/TslGame.exe";
    write(aim, "");write(cs, "");write(pubg, "");
    write(other / L"steamapps/common/PUBG/ExecPubg.exe", "");
    manifest(steam, "714010", "Aimlabs");manifest(other, "730", "Counter Strike");manifest(other, "578080", "PUBG");
    auto found = discoverSteamGames(libraries);
    check(found.size() == 3, "Three supported games discovered without execution");
    check(found[2]["Path"].get<std::string>().find("TslGame.exe") != std::string::npos, "PUBG launcher not confused with game executable");
    check(discoverSteamGames({steam, other, other}).size() == 3, "Repeated libraries do not duplicate games");
    J config = {{"Enabled", false}, {"CustomField", "keep"}, {"Games", J::array()}, {"BlockedApps", J::array()}};
    check(mergeDetectedGames(config, found) == 3, "New games merged");
    check(config["Enabled"] == false && config["CustomField"] == "keep", "User settings preserved");
    config["Games"][0]["Name"] = "Personal label";
    auto before = config;
    check(mergeDetectedGames(config, found) == 0 && config == before, "Idempotence and personal labels preserved");
    J excluded = {{"Games", J::array()}, {"BlockedApps", J::array({{{"Name", "AimLab_tb.exe"}}, {{"Path", utf8(pubg.wstring())}}})}};
    check(mergeDetectedGames(excluded, found) == 1, "Exclusions by executable name and full path respected");
    auto upper = aim.wstring();std::transform(upper.begin(), upper.end(), upper.begin(), towupper);
    J existing = {{"Games", J::array({{{"Path", utf8(upper)}}})}, {"BlockedApps", J::array()}};
    check(mergeDetectedGames(existing, found) == 2, "Case-insensitive path deduplication");
    fs::remove(pubg);
    check(discoverSteamGames(libraries).size() == 2, "Missing executable rejected");write(pubg, "");
    manifest(other, "578080", "../outside");
    check(discoverSteamGames(libraries).size() == 2, "Parent traversal in manifest rejected");
    manifest(other, "578080", "C:\\outside");
    check(discoverSteamGames(libraries).size() == 2, "Absolute install directory rejected");
    manifest(other, "578080", "PUBG", "730");
    check(discoverSteamGames(libraries).size() == 2, "Wrong app ID rejected");
    write(other / L"steamapps/appmanifest_578080.acf", "\"AppState\" { \"appid\" \"578080\"");
    check(discoverSteamGames(libraries).size() == 2, "Malformed manifest isolated from other games");
    manifest(other, "578080", "PUBG");
    write(steam / L"steamapps/libraryfolders.vdf", "\"libraryfolders\" {} \"libraryfolders\" {}");
    check(steamLibrariesFrom({steam}).size() == 1, "Duplicate VDF keys rejected; primary library retained");
    write(steam / L"steamapps/libraryfolders.vdf", std::string(4 * 1024 * 1024 + 1, 'x'));
    check(steamLibrariesFrom({steam}).size() == 1, "Oversized VDF rejected");
    auto helper = other / L"steamapps/common/PUBG/ExecPubg.exe";
    check(mergeDetectedGames(config, J::array({{{"Path", utf8(helper.wstring())}}})) == 0, "Excluded helper cannot be added manually");
    check(mergeDetectedGames(config, J::array({{{"Path", "relative.exe"}}})) == 0, "Relative executable rejected");
    write(root / L"manual.txt", "");
    check(mergeDetectedGames(config, J::array({{{"Path", utf8((root / L"manual.txt").wstring())}}})) == 0, "Non-executable entry rejected");
    J invalid = {{"Games", "invalid"}};auto original = invalid;bool refused = false;
    try { mergeDetectedGames(invalid, found); } catch (...) { refused = true; }
    check(refused && invalid == original, "Malformed config rejected without replacement");
    atomicJson(root / L"DiscoveryResult.json", {{"Passed", true}, {"Checks", count}, {"Scope", "Synthetic files only; no game launched"}});
    std::cout << "PASS : " << count << " discovery checks.\n";
    return 0;
  } catch (const std::exception &e) { std::cerr << "FAIL : " << e.what() << '\n';return 1; }
}
