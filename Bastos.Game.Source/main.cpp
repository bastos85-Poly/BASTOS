#include "core.hpp"
#include "discovery.hpp"
#include <d3d11.h>
#include <iomanip>
Paths paths;
HWND window = 0, detailBox = 0, gameList = 0, priorityBox = 0, observeCheck = 0,
     auxCheck = 0, gameObserve = 0, backgroundCheck = 0, threadCheck = 0,
     ecoCheck = 0, ioCheck = 0, gamePriorityBox = 0, gameThreadCheck = 0,
     gameCustomCheck = 0, gameHint = 0, auxHelp = 0, gamePath = 0;
HFONT font = 0;
J selectedConfig;
std::vector<std::string> gameKeys;
UINT taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
UINT trayMessage = WM_APP + 1;
NOTIFYICONDATAW tray{};
Engine *engine = nullptr;
bool settingsMode = false;
HWND control(const wchar_t *, const wchar_t *, int, DWORD, int, int, int, int);
void loadControls();
void refreshDetails();
void loadSelection();
void refreshActiveGames(const J &);
bool selectedIsActive();
bool selectedIsPubg();
void personalOptions();
void detectInstalledGames(bool notify);
void addGameFile();
void backgroundOptions() {
  bool enabled =
      SendMessageW(backgroundCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  EnableWindow(ecoCheck, enabled);
  EnableWindow(ioCheck, enabled);
}
#include "interface.hpp"
void launch(const fs::path &exe, const std::wstring &args) {
  SHELLEXECUTEINFOW s{sizeof(s)};
  s.fMask = SEE_MASK_NOCLOSEPROCESS;
  s.lpFile = exe.c_str();
  s.lpParameters = args.c_str();
  s.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&s))
    throw std::runtime_error("Lancement impossible");
  if (s.hProcess)
    CloseHandle(s.hProcess);
}
std::vector<std::string> csvRow(std::string s) {
  std::vector<std::string> out;
  std::string v;
  bool quoted = false;
  for (size_t i = 0; i < s.size(); i++) {
    char c = s[i];
    if (c == '"') {
      if (quoted && i + 1 < s.size() && s[i + 1] == '"') {
        v += '"';
        i++;
      } else
        quoted = !quoted;
    } else if (c == ',' && !quoted) {
      out.push_back(v);
      v.clear();
    } else if (c != '\r')
      v += c;
  }
  out.push_back(v);
  return out;
}
J metrics(const fs::path &path) {
  std::ifstream f(path);
  std::string line;
  if (!std::getline(f, line))
    throw std::runtime_error("CSV vide");
  if (line.rfind("\xEF\xBB\xBF", 0) == 0)
    line.erase(0, 3);
  auto head = csvRow(line);
  auto index = [&](const std::string &k) {
    auto i = std::find(head.begin(), head.end(), k);
    return i == head.end() ? -1 : int(i - head.begin());
  };
  int col = index("MsBetweenPresents");
  if (col < 0)
    col = index("FrameTime");
  if (col < 0)
    throw std::runtime_error(
        "CSV PresentMon attendu : MsBetweenPresents ou FrameTime (ms).");
  int process = index("ProcessID"), app = index("Application"),
      swap = index("SwapChainAddress");
  std::map<std::string, std::vector<double>> groups;
  size_t rejected = 0;
  while (std::getline(f, line)) {
    auto row = csvRow(line);
    if (col >= (int)row.size()) {
      rejected++;
      continue;
    }
    try {
      size_t pos = 0;
      double v = std::stod(row[col], &pos);
      if (pos != row[col].size() || !std::isfinite(v) || v <= 0) {
        rejected++;
        continue;
      }
      auto val = [&](int i) {
        return i >= 0 && i < (int)row.size() ? row[i] : "";
      };
      auto key =
          val(app) + " | PID " + val(process) + " | swapchain " + val(swap);
      groups[key].push_back(v);
    } catch (...) {
      rejected++;
    }
  }
  if (groups.empty())
    throw std::runtime_error("Aucun temps de trame valide");
  auto best =
      std::max_element(groups.begin(), groups.end(), [](auto &a, auto &b) {
        return a.second.size() < b.second.size();
      });
  auto frames = best->second;
  if (frames.size() < 100)
    throw std::runtime_error("Au moins 100 trames valides nécessaires");
  double total = 0;
  for (double v : frames)
    total += v;
  std::sort(frames.begin(), frames.end());
  size_t slow = std::max<size_t>(1, (size_t)std::ceil(frames.size() * .01));
  double tail = 0;
  for (size_t i = frames.size() - slow; i < frames.size(); i++)
    tail += frames[i];
  return {{"File", utf8(path.wstring())},
          {"Stream", best->first},
          {"StreamsFound", groups.size()},
          {"Frames", frames.size()},
          {"InvalidRows", rejected},
          {"DurationSeconds", total / 1000},
          {"AverageFps", 1000 * frames.size() / total},
          {"OnePercentLowFps", 1000 * slow / tail},
          {"P99FrameMs", frames[(size_t)std::ceil(frames.size() * .99) - 1]},
          {"Definition",
           "FPS = 1000 / moyenne des temps de trame ; 1% low = 1000 / moyenne "
           "du 1% de trames les plus lentes. Flux majoritaire uniquement."}};
}
std::string selectedKey() {
  int n = (int)SendMessageW(gameList, CB_GETCURSEL, 0, 0);
  return n >= 0 && n < (int)gameKeys.size() ? gameKeys[n] : "";
}
J liveGames = J::array();
std::vector<std::string> displayedGameLabels;
std::string preferredSelection;
bool selectedIsActive() {
  auto key = selectedKey();
  for (auto &g : liveGames)
    if (utf8(lower(wide(g.value("Path", "")))) == key)
      return true;
  return false;
}
bool selectedIsPubg() {
  return !selectedKey().empty() &&
         lower(fs::path(wide(selectedKey())).stem().wstring()) == L"tslgame";
}
void personalOptions() {
  bool available = !selectedKey().empty();
  bool custom = available &&
                SendMessageW(gameCustomCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  wchar_t shownPath[32768]{};
  GetWindowTextW(gamePath, shownPath, 32768);
  auto selectedPath = wide(selectedKey());
  if (selectedPath != shownPath)
    SetWindowTextW(gamePath, selectedPath.c_str());
  EnableWindow(gameCustomCheck, available);
  EnableWindow(gamePriorityBox, custom);
  EnableWindow(gameThreadCheck, custom);
  EnableWindow(gameObserve, custom);
  EnableWindow(auxCheck, custom && selectedIsPubg());
  std::wstring hint = !available ? L"Ajoutez vos jeux autorisés dans Bastos "
                                   L"pour préparer leurs profils."
                      : custom   ? L"Réglages personnels réservés à ce jeu."
                                 : L"Ce jeu reprend vos réglages standards.";
  if (available)
    hint += selectedIsActive()
                ? L" Jeu actuellement en cours."
                : L" Application automatique à son prochain lancement.";
  SetWindowTextW(gameHint, hint.c_str());
  ShowWindow(auxCheck,
             currentPage == 1 && selectedIsPubg() ? SW_SHOW : SW_HIDE);
  ShowWindow(auxHelp, currentPage == 1 && selectedIsPubg() ? SW_SHOW : SW_HIDE);
}
void loadSelection() {
  auto p = loadProfiles(paths);
  auto key = selectedKey();
  auto games = p.value("Games", J::object());
  bool custom = !key.empty() && games.contains(key);
  J v = custom ? games[key] : J::object();
  SendMessageW(gameCustomCheck, BM_SETCHECK,
               custom ? BST_CHECKED : BST_UNCHECKED, 0);
  SendMessageW(gamePriorityBox, CB_SETCURSEL,
               v.value("Priority", p.value("DefaultPriority", "AboveNormal")) ==
                       "High"
                   ? 1
                   : 0,
               0);
  SendMessageW(gameThreadCheck, BM_SETCHECK,
               v.value("ThreadPriorities", p.value("ThreadPriorities", true))
                   ? BST_CHECKED
                   : BST_UNCHECKED,
               0);
  SendMessageW(gameObserve, BM_SETCHECK,
               v.value("ObserveOnly", false) ? BST_CHECKED : BST_UNCHECKED, 0);
  SendMessageW(auxCheck, BM_SETCHECK,
               v.value("OptimizeAuxiliary", p.value("OptimizeAuxiliary", true))
                   ? BST_CHECKED
                   : BST_UNCHECKED,
               0);
  currentSelection = (int)SendMessageW(gameList, CB_GETCURSEL, 0, 0);
  personalOptions();
}
void refreshActiveGames(const J &status) {
  liveGames = freshStatus(status) && status.value("State", "") == "Ready"
                  ? status.value("ActiveGames", J::array())
                  : J::array();
  std::vector<std::string> next;
  std::set<std::string> seen;
  for (auto &g : liveGames) {
    auto key = utf8(lower(wide(g.value("Path", ""))));
    if (!key.empty() && seen.insert(key).second)
      next.push_back(key);
  }
  // Live games come first on opening; registered games and saved profiles
  // remain editable offline.
  auto config = readJson(paths.config), profiles = loadProfiles(paths);
  auto add = [&](const std::string &path) {
    auto key = utf8(lower(wide(path)));
    if (!key.empty() && seen.insert(key).second)
      next.push_back(key);
  };
  for (auto &g : config.value("Games", J::array()))
    add(g.value("Path", ""));
  auto storedProfiles = profiles.value("Games", J::object());
  for (auto &[key, value] : storedProfiles.items())
    add(key);
  std::vector<std::string> labels;
  for (auto &key : next) {
    bool active = false;
    for (auto &g : liveGames)
      if (utf8(lower(wide(g.value("Path", "")))) == key)
        active = true;
    labels.push_back(utf8(gameLabel(key)) + (active ? " — en cours" : ""));
  }
  if (!dirty && (next != gameKeys || labels != displayedGameLabels)) {
    auto old = preferredSelection.empty() ? selectedKey() : preferredSelection;
    preferredSelection.clear();
    gameKeys = next;
    displayedGameLabels = labels;
    SendMessageW(gameList, CB_RESETCONTENT, 0, 0);
    for (auto &label : labels)
      SendMessageW(gameList, CB_ADDSTRING, 0, (LPARAM)wide(label).c_str());
    if (gameKeys.empty())
      SendMessageW(gameList, CB_ADDSTRING, 0, (LPARAM)L"Aucun jeu enregistré");
    auto found = std::find(gameKeys.begin(), gameKeys.end(), old);
    SendMessageW(gameList, CB_SETCURSEL,
                 found == gameKeys.end() ? 0 : found - gameKeys.begin(), 0);
    loadSelection();
  }
  EnableWindow(gameList, !gameKeys.empty());
  personalOptions();
}
void loadControls() {
  auto c = readJson(paths.config), p = loadProfiles(paths);
  SendMessageW(priorityBox, CB_SETCURSEL,
               p.value("DefaultPriority", "AboveNormal") == "High" ? 1 : 0, 0);
  SendMessageW(
      backgroundCheck, BM_SETCHECK,
      c.value("OptimizeBackground", false) ? BST_CHECKED : BST_UNCHECKED, 0);
  SendMessageW(observeCheck, BM_SETCHECK,
               p.value("ObserveOnly", false) ? BST_CHECKED : BST_UNCHECKED, 0);
  SendMessageW(threadCheck, BM_SETCHECK,
               p.value("ThreadPriorities", true) ? BST_CHECKED : BST_UNCHECKED,
               0);
  SendMessageW(ecoCheck, BM_SETCHECK,
               p.value("BackgroundEcoQoS", true) ? BST_CHECKED : BST_UNCHECKED,
               0);
  SendMessageW(
      ioCheck, BM_SETCHECK,
      p.value("BackgroundIoPriority", true) ? BST_CHECKED : BST_UNCHECKED, 0);
  backgroundOptions();
  priorityExplanation();
  preferredSelection = selectedKey();
  gameKeys = {"__reload__"};
  refreshActiveGames(fs::exists(paths.status) ? readJson(paths.status)
                                              : J::object());
  loadSelection();
}
void saveControls() {
  auto p = loadProfiles(paths);
  p["Version"] = 3;
  p["ObserveOnly"] =
      SendMessageW(observeCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  p["ThreadPriorities"] =
      SendMessageW(threadCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  p["BackgroundEcoQoS"] =
      SendMessageW(ecoCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  p["BackgroundIoPriority"] =
      SendMessageW(ioCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  p["DefaultPriority"] = SendMessageW(priorityBox, CB_GETCURSEL, 0, 0) == 1
                             ? "High"
                             : "AboveNormal";
  auto key = selectedKey();
  if (!key.empty()) {
    if (SendMessageW(gameCustomCheck, BM_GETCHECK, 0, 0) == BST_CHECKED) {
      auto v = p.value("Games", J::object()).value(key, J::object());
      v["Priority"] = SendMessageW(gamePriorityBox, CB_GETCURSEL, 0, 0) == 1
                          ? "High"
                          : "AboveNormal";
      v["ThreadPriorities"] =
          SendMessageW(gameThreadCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
      v["ObserveOnly"] =
          SendMessageW(gameObserve, BM_GETCHECK, 0, 0) == BST_CHECKED;
      if (selectedIsPubg())
        v["OptimizeAuxiliary"] =
            SendMessageW(auxCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
      p["Games"][key] = v;
    } else if (p.contains("Games"))
      p["Games"].erase(key);
  }
  atomicJson(paths.profiles, p);
  auto c = readJson(paths.config);
  c["OptimizeBackground"] =
      SendMessageW(backgroundCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
  atomicJson(paths.config, c);
  dirty = false;
  loadControls();
  setNote(L"Réglages enregistrés. Les profils personnels prennent le relais "
          L"des réglages standards.");
}
void detectInstalledGames(bool notify) {
  if (dirty) {
    setNote(L"Enregistrez ou annulez vos modifications avant de rechercher des "
            L"jeux.");
    return;
  }
  auto config = readJson(paths.config);
  auto found = discoverSteamGames(steamLibraries());
  int added = mergeDetectedGames(config, found);
  if (added)
    atomicJson(paths.config, config);
  loadControls();
  if (notify)
    setNote(std::to_wstring(added) + L" jeu(x) ajouté(s). Recherche Steam : "
                                     L"Aimlabs, Counter-Strike 2 et PUBG.");
}
void addGameFile() {
  if (dirty) {
    setNote(
        L"Enregistrez ou annulez vos modifications avant d'ajouter un jeu.");
    return;
  }
  wchar_t file[32768]{};
  OPENFILENAMEW dialog{sizeof(dialog)};
  dialog.hwndOwner = window;
  dialog.lpstrFilter = L"Exécutables de jeu (*.exe)\0*.exe\0\0";
  dialog.lpstrFile = file;
  dialog.nMaxFile = 32768;
  dialog.lpstrTitle = L"Choisir l'exécutable du jeu";
  dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
  if (!GetOpenFileNameW(&dialog))
    return;
  fs::path exe = file;
  std::error_code ec;
  if (lower(exe.extension().wstring()) != L".exe" ||
      !fs::is_regular_file(exe, ec)) {
    setNote(L"Choisissez un fichier exécutable .exe existant.");
    return;
  }
  auto config = readJson(paths.config);
  J game = {{"Name", utf8(gameLabel(utf8(exe.wstring())))},
            {"Path", utf8(exe.wstring())},
            {"AddedUtc", now()}};
  int added = mergeDetectedGames(config, J::array({game}));
  if (added)
    atomicJson(paths.config, config);
  preferredSelection = utf8(lower(exe.wstring()));
  gameKeys = {"__reload__"};
  refreshActiveGames(fs::exists(paths.status) ? readJson(paths.status)
                                              : J::object());
  setNote(added ? L"Jeu ajouté. Son profil est prêt à être personnalisé."
                : L"Jeu déjà enregistré ou exclu. Vérifiez vos exclusions si "
                  L"nécessaire.");
}
void refreshDetails() {
  try {
    auto s = readJson(paths.status);
    updateSummary(s);
    refreshActiveGames(s);
    std::ostringstream o;
    o << "BASTOS GAME " << s.value("EngineVersion", "ancienne version") << " — "
      << s.value("State", "")
      << "\r\nDernier état : " << s.value("UpdatedUtc", "") << "\r\n";
    auto err = s.value("Error", "");
    if (!err.empty())
      o << "Erreur : " << err << "\r\n";
    o << "\r\n";
    for (auto pair :
         {std::pair{"ActiveGames", "JEUX"},
          std::pair{"AuxiliaryProcesses", "AUXILIAIRES DU JEU"},
          std::pair{"BackgroundProcesses", "AUTRES APPLICATIONS"}}) {
      o << pair.second << "\r\n";
      auto items = s.value(pair.first, J::array());
      if (items.empty())
        o << "Aucun\r\n";
      for (auto &item : items) {
        o << item.value("Name", "") << " (PID " << item.value("ProcessId", 0)
          << ")\r\n";
        for (auto &a : item.value("Actions", J::array()))
          o << "  " << a.value("Setting", "") << " : " << a.value("Before", "")
            << " → " << a.value("Requested", "")
            << "\r\n    Lu : " << a.value("Actual", "") << " — "
            << a.value("Outcome", "")
            << (a.value("Win32Error", 0)
                    ? " (Windows " + std::to_string(a.value("Win32Error", 0)) +
                          ")"
                    : "")
            << "\r\n";
      }
      o << "\r\n";
    }
    o << "DERNIÈRES RESTAURATIONS\r\n";
    auto r = s.value("Restoration", J::array());
    for (size_t i = r.size() > 12 ? r.size() - 12 : 0; i < r.size(); i++)
      o << r[i].value("Name", "") << " — " << r[i].value("Setting", "") << " : "
        << r[i].value("Outcome", "") << "\r\n";
    auto text = wide(o.str());
    int n = GetWindowTextLengthW(detailBox);
    std::wstring old(n + 1, 0);
    GetWindowTextW(detailBox, old.data(), n + 1);
    old.resize(n);
    if (old != text) {
      int pos = (int)SendMessageW(detailBox, EM_GETFIRSTVISIBLELINE, 0, 0);
      SetWindowTextW(detailBox, text.c_str());
      SendMessageW(detailBox, EM_SETSEL, 0, 0);
      SendMessageW(detailBox, EM_SCROLLCARET, 0, 0);
      SendMessageW(detailBox, EM_LINESCROLL, 0, pos);
    }
  } catch (const std::exception &e) {
    SetWindowTextW(detailBox, wide(e.what()).c_str());
    SetWindowTextW(heroTitle, L"État temporairement indisponible");
    SetWindowTextW(heroSub,
                   L"Le moteur ne fournit pas encore de résultat récent.");
  }
}
HWND control(const wchar_t *cls, const wchar_t *text, int id, DWORD style,
             int x, int y, int w, int h) {
  HWND c =
      CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h,
                      window, (HMENU)(INT_PTR)id, GetModuleHandleW(0), 0);
  SendMessageW(c, WM_SETFONT, (WPARAM)font, TRUE);
  return c;
}
void showSettings() {
  wchar_t exe[32768];
  GetModuleFileNameW(0, exe, 32768);
  launch(exe, L"--settings --config \"" + paths.config.wstring() +
                  L"\" --status \"" + paths.status.wstring() + L"\"");
}
LRESULT CALLBACK wndProc(HWND w, UINT msg, WPARAM wp, LPARAM lp) {
  try {
    if (msg == taskbarCreated && !settingsMode && tray.hWnd) {
      Shell_NotifyIconW(NIM_ADD, &tray);
      return 0;
    }
    switch (msg) {
    case WM_PAINT:
      if (settingsMode) {
        paintSurface();
        return 0;
      }
      break;
    case WM_DRAWITEM:
      if (settingsMode)
        return drawButton((DRAWITEMSTRUCT *)lp);
      break;
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX:
    case WM_CTLCOLORBTN:
      if (settingsMode) {
        HDC dc = (HDC)wp;
        int id = GetDlgCtrlID((HWND)lp);
        bool base = id == 301 || id == 360;
        SetTextColor(dc, (id == 301 || id == 302 || id == 310 || id == 320 ||
                          id == 340 || id == 350 || id == 351 || id == 353 ||
                          id == 355)
                             ? textColor
                             : mutedColor);
        SetBkColor(dc, base ? bgColor : cardColor);
        return (LRESULT)(base ? bgBrush : cardBrush);
      }
      break;
    case WM_CLOSE:
      if (settingsMode && dirty &&
          MessageBoxW(w, L"Fermer sans enregistrer vos modifications ?",
                      L"Bastos Game", MB_YESNO | MB_ICONQUESTION) != IDYES)
        return 0;
      DestroyWindow(w);
      return 0;
    case WM_COMMAND:
      if (settingsMode) {
        switch (LOWORD(wp)) {
        case 101:
          if (HIWORD(wp) == CBN_SELCHANGE) {
            if (dirty) {
              SendMessageW(gameList, CB_SETCURSEL, currentSelection, 0);
              setNote(L"Enregistrez ou annulez vos modifications avant de "
                      L"changer de jeu.");
            } else
              loadSelection();
          }
          break;
        case 107:
          backgroundOptions();
          markDirty();
          break;
        case 116:
          personalOptions();
          markDirty();
          break;
        case 102:
        case 103:
        case 105:
        case 108:
        case 109:
        case 114:
        case 117:
          markDirty();
          break;
        case 115:
          if (HIWORD(wp) == CBN_SELCHANGE)
            markDirty();
          break;
        case 104:
          if (HIWORD(wp) == CBN_SELCHANGE) {
            priorityExplanation();
            markDirty();
          }
          break;
        case 120:
        case 121:
        case 122:
          page(LOWORD(wp) - 120);
          personalOptions();
          break;
        case 123:
          launch(paths.app, L"--page game");
          break;
        case 118:
          addGameFile();
          break;
        case 119:
          detectInstalledGames(true);
          break;
        case 110:
          saveControls();
          break;
        case 112:
          fs::create_directories(paths.sessions);
          launch(paths.sessions, L"");
          break;
        case 113:
          dirty = false;
          loadControls();
          setNote(L"Modifications annulées. Les réglages enregistrés sont "
                  L"affichés.");
          break;
        }
      } else {
        if (LOWORD(wp) == 201)
          showSettings();
        if (LOWORD(wp) == 202)
          launch(paths.app, L"--page game");
        if (LOWORD(wp) == 203)
          DestroyWindow(w);
      }
      return 0;
    case WM_TIMER:
      if (settingsMode) {
        refreshDetails();
        return 0;
      }
      if (fs::exists(paths.stop)) {
        DestroyWindow(w);
        return 0;
      }
      engine->cycle();
      {
        auto label = engine->error.empty()
                         ? (engine->status.value("ObserveOnly", false)
                                ? L"Bastos Game — observation"
                                : L"Bastos Game — actif")
                         : L"Bastos Game — erreur";
        wcsncpy_s(tray.szTip, label, _TRUNCATE);
        Shell_NotifyIconW(NIM_MODIFY, &tray);
      }
      return 0;
    case WM_APP + 1:
      if (lp == WM_LBUTTONDBLCLK)
        showSettings();
      if (lp == WM_RBUTTONUP) {
        HMENU m = CreatePopupMenu();
        AppendMenuW(m, MF_STRING, 201, L"Mes réglages et performances");
        AppendMenuW(m, MF_STRING, 202, L"Ouvrir Bastos");
        AppendMenuW(m, MF_SEPARATOR, 0, 0);
        AppendMenuW(m, MF_STRING, 203, L"Arrêter et restaurer");
        POINT pt;
        GetCursorPos(&pt);
        SetForegroundWindow(w);
        TrackPopupMenu(m, TPM_RIGHTBUTTON, pt.x, pt.y, 0, w, 0);
        DestroyMenu(m);
      }
      return 0;
    case WM_QUERYENDSESSION:
      return TRUE;
    case WM_ENDSESSION:
      if (wp && !settingsMode && engine)
        engine->stop();
      return 0;
    case WM_DESTROY:
      KillTimer(w, 1);
      if (!settingsMode && engine) {
        Shell_NotifyIconW(NIM_DELETE, &tray);
        engine->stop();
      }
      PostQuitMessage(0);
      return 0;
    }
  } catch (const std::exception &e) {
    if (settingsMode)
      MessageBoxW(w, wide(e.what()).c_str(), L"Bastos Game",
                  MB_OK | MB_ICONERROR);
    else if (engine)
      engine->log(e.what());
  }
  return DefWindowProcW(w, msg, wp, lp);
}
int selftest(const Paths &p, const fs::path &exe) {
  fs::create_directories(p.config.parent_path());
  J tests = J::array();
  auto check = [&](bool ok, const char *name) {
    tests.push_back({{"Test", name}, {"Passed", ok}});
    if (!ok)
      throw std::runtime_error(name);
  };
  PROCESS_INFORMATION pi{};
  STARTUPINFOW si{sizeof(si)};
  std::wstring cmd = L"\"" + exe.wstring() + L"\" --test-child --config \"" +
                     p.config.wstring() + L"\"";
  if (!CreateProcessW(exe.c_str(), cmd.data(), 0, 0, FALSE, CREATE_NO_WINDOW, 0,
                      0, &si, &pi))
    return 2;
  CloseHandle(pi.hThread);
  Handle child(pi.hProcess);
  try {
    auto childReady = p.config.parent_path() / L"child-gpu.json";
    for (int attempt = 0; attempt < 100 && !fs::exists(childReady); attempt++)
      Sleep(50);
    check(fs::exists(childReady), "GPU test child initialized");
    tests.push_back(
        {{"Test", "GPU device diagnostic"}, {"Result", readJson(childReady)}});
    auto original = snapshot(child);
    auto gpuApi = gpuPriorityApi();
    int gpuBefore = -1;
    LONG gpuReadStatus = gpuApi.get ? gpuApi.get(child, &gpuBefore) : -1;
    tests.push_back({{"Test", "GPU API diagnostic"},
                     {"GetAvailable", gpuApi.get != nullptr},
                     {"SetAvailable", gpuApi.set != nullptr},
                     {"ReadStatus", gpuReadStatus},
                     {"ReadValue", gpuBefore}});
    atomicJson(p.config,
               {{"Enabled", true},
                {"AutoDetect", false},
                {"OptimizeBackground", false},
                {"Games", J::array({{{"Path", utf8(exe.wstring())}}})},
                {"BlockedApps", J::array()}});
    atomicJson(p.profiles, defaultProfiles());
    Engine a(p);
    a.cycle();
    check(a.status["ActiveGames"].size() == 1, "Forced detection");
    check(GetPriorityClass(child) == ABOVE_NORMAL_PRIORITY_CLASS,
          "CPU priority above normal actually applied");
    if (!original.contains("GpuPriority"))
      tests.push_back(
          {{"Test", "GPU priority"},
           {"Skipped",
            "GPU API unavailable or access denied in this environment"}});
    check(!original.contains("GpuPriority") ||
              snapshot(child).value("GpuPriority", -1) == 4,
          "GPU priority high actually applied");
    check(a.status["ActiveGames"][0]["Actions"].size() >= 5,
          "Verified results per setting");
    auto pr = defaultProfiles();
    pr["ObserveOnly"] = true;
    atomicJson(p.profiles, pr);
    a.cycle();
    check(snapshot(child) == original,
          "Observation restores exact original state");
    pr["ObserveOnly"] = false;
    pr["DefaultPriority"] = "High";
    atomicJson(p.profiles, pr);
    a.cycle();
    check(GetPriorityClass(child) == HIGH_PRIORITY_CLASS,
          "High CPU profile applies without restart");
    pr["DefaultPriority"] = "Normal"; // Old profiles must honor the new floor.
    atomicJson(p.profiles, pr);
    a.cycle();
    check(
        GetPriorityClass(child) == ABOVE_NORMAL_PRIORITY_CLASS,
        "Legacy normal CPU profile is raised above normal"); // Simulate a
                                                             // crash: abandon
                                                             // the in-memory
                                                             // map, recover
                                                             // only the durable
                                                             // journal.
    a.entries.clear();
    Engine b(p);
    b.recover();
    check(snapshot(child) == original, "Crash recovery from journal");
    b.cycle();
    auto c = readJson(p.config);
    c["Games"] = J::array();
    atomicJson(p.config, c);
    b.cycle();
    check(snapshot(child) == original,
          "Removing a live game restores its settings");
    c["Games"] = J::array({{{"Path", utf8(exe.wstring())}}});
    atomicJson(p.config, c);
    b.cycle();
    SetPriorityClass(child, NORMAL_PRIORITY_CLASS);
    check(!original.contains("GpuPriority") ||
              setSetting(child, "GpuPriority", 3),
          "External GPU change can be simulated");
    b.cycle();
    check(GetPriorityClass(child) == ABOVE_NORMAL_PRIORITY_CLASS,
          "CPU priority remains above normal during the game");
    check(!original.contains("GpuPriority") ||
              snapshot(child).value("GpuPriority", -1) == 4,
          "GPU priority remains high during the game");
    b.clear();
    check(snapshot(child) == original,
          "Original CPU and GPU priorities restored after game tracking");
    b.cycle();
    {
      std::ofstream f(p.config);
      f << "{";
    }
    b.cycle();
    check(b.status["State"] == "Error" && snapshot(child) == original,
          "Malformed config fails safely and remains visible");
    Proc fake{42, 1, L"C:\\Steam\\steamapps\\common\\Game\\KRNLGame.exe",
              L"krnlgame", true};
    c["AutoDetect"] = true;
    check(automatic(fake, c) && !blocked(fake, c),
          "No legacy conflict or exclusion");
    Proc helper{43, 1, L"C:\\Steam\\steamapps\\common\\PUBG\\ExecPubg.exe",
                L"execpubg", true};
    check(!automatic(helper, c), "Helper not misidentified as game");
    {
      std::ofstream f(p.config.parent_path() / L"capture.csv");
      f << "Application,ProcessID,SwapChainAddress,MsBetweenPresents\n";
      for (int i = 0; i < 1000; i++)
        f << "game.exe,42,0x1,10\n";
      f << "other.exe,5,0x2,80\n";
    }
    auto m = metrics(p.config.parent_path() / L"capture.csv");
    check(m["AverageFps"] == 100.0 && m["OnePercentLowFps"] == 100.0 &&
              m["Frames"] == 1000,
          "CSV metrics isolate a presentation stream");
    atomicJson(p.config.parent_path() / L"tests.json",
               {{"Success", true}, {"Tests", tests}});
    TerminateProcess(child, 0);
    return 0;
  } catch (const std::exception &e) {
    SetPriorityClass(child, NORMAL_PRIORITY_CLASS);
    TerminateProcess(child, 0);
    atomicJson(p.config.parent_path() / L"tests.json",
               {{"Success", false}, {"Error", e.what()}, {"Tests", tests}});
    return 1;
  }
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int) {
  int argc;
  wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  paths = pathsFrom(argc, argv);
  bool test = false;
  for (int i = 1; i < argc; i++) {
    if (std::wstring(argv[i]) == L"--test-child") {
      ID3D11Device *device = nullptr;
      ID3D11DeviceContext *context = nullptr;
      D3D_FEATURE_LEVEL level;
      HRESULT deviceStatus = D3D11CreateDevice(
          nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
          D3D11_SDK_VERSION, &device, &level, &context);
      int gpuLevel = -1;
      auto gpu = gpuPriorityApi();
      LONG gpuStatus = gpu.get ? gpu.get(GetCurrentProcess(), &gpuLevel) : -1;
      atomicJson(paths.config.parent_path() / L"child-gpu.json",
                 {{"DeviceStatus", deviceStatus},
                  {"GpuStatus", gpuStatus},
                  {"GpuLevel", gpuLevel}});
      Sleep(120000);
      if (context)
        context->Release();
      if (device)
        device->Release();
      return 0;
    }
    if (std::wstring(argv[i]) == L"--self-test")
      test = true;
    if (std::wstring(argv[i]) == L"--settings")
      settingsMode = true;
  }
  LocalFree(argv);
  wchar_t exe[32768];
  GetModuleFileNameW(0, exe, 32768);
  if (test) {
    if (paths.config == pathsFrom(0, nullptr).config)
      return 3;
    return selftest(paths, exe);
  }
  try {
    SetProcessDPIAware();
    INITCOMMONCONTROLSEX cc{sizeof(cc), ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&cc);
    Handle mutex(settingsMode
                     ? nullptr
                     : CreateMutexW(0, TRUE, L"Local\\BASTOS-Game-Monitor"));
    if (!settingsMode && GetLastError() == ERROR_ALREADY_EXISTS)
      return 0;
    Engine e(paths);
    if (!settingsMode) {
      engine = &e;
      e.recover();
      e.log("Moteur natif 3.6.0 démarré.");
    }
    WNDCLASSW wc{};
    wc.lpfnWndProc = wndProc;
    wc.hInstance = instance;
    wc.lpszClassName = L"BastosGameV3";
    wc.hCursor = LoadCursorW(0, IDC_ARROW);
    wc.hbrBackground = bgBrush;
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
    RegisterClassW(&wc);
    window = CreateWindowExW(
        0, wc.lpszClassName, L"Bastos Game",
        settingsMode
            ? (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX)
            : 0,
        CW_USEDEFAULT, CW_USEDEFAULT, 988, 812, 0, 0, instance, 0);
    font = CreateFontW(-16, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                       0, 0, L"Segoe UI");
    if (settingsMode) {
      createInterface();
      ShowWindow(window, SW_SHOW);
      SetTimer(window, 1, 1000, 0);
    } else {
      tray.cbSize = sizeof(tray);
      tray.hWnd = window;
      tray.uID = 1;
      tray.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
      tray.uCallbackMessage = trayMessage;
      tray.hIcon = wc.hIcon;
      if (fs::exists(paths.icon))
        tray.hIcon = (HICON)LoadImageW(0, paths.icon.c_str(), IMAGE_ICON, 32,
                                       32, LR_LOADFROMFILE);
      if (!tray.hIcon)
        tray.hIcon = LoadIconW(0, IDI_APPLICATION);
      wcscpy_s(tray.szTip, L"Bastos Game 3 — réglages et profils");
      Shell_NotifyIconW(NIM_ADD, &tray);
      e.cycle();
      SetTimer(window, 1, 1000, 0);
    }
    MSG msg;
    while (GetMessageW(&msg, 0, 0, 0) > 0) {
      if (!settingsMode || !IsDialogMessageW(window, &msg)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
      }
    }
    if (font)
      DeleteObject(font);
    if (!settingsMode)
      ReleaseMutex(mutex);
    return 0;
  } catch (const std::exception &e) {
    try {
      if (!settingsMode)
        atomicJson(paths.status, {{"Version", 3},
                                  {"UpdatedUtc", now()},
                                  {"ProcessId", GetCurrentProcessId()},
                                  {"State", "Error"},
                                  {"Error", e.what()}});
    } catch (...) {
    }
    if (settingsMode)
      MessageBoxW(0, wide(e.what()).c_str(), L"Bastos Game",
                  MB_OK | MB_ICONERROR);
    return 1;
  }
}
