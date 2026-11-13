#pragma once
#include <dwmapi.h>
#include <uxtheme.h>
const COLORREF bgColor = RGB(14, 20, 32), cardColor = RGB(24, 33, 49),
               textColor = RGB(237, 243, 252), mutedColor = RGB(164, 181, 204),
               accentColor = RGB(78, 156, 255);
HBRUSH bgBrush = CreateSolidBrush(bgColor),
       cardBrush = CreateSolidBrush(cardColor);
HFONT titleFont = 0, sectionFont = 0, smallFont = 0;
HWND heroTitle = 0, heroSub = 0, saveNote = 0, priorityHelp = 0;
std::vector<std::pair<HWND, int>> uiGroups;
std::set<int> titleIds;
int currentPage = 0, currentSelection = 0;
bool dirty = false;
void setNote(const std::wstring &s) { SetWindowTextW(saveNote, s.c_str()); }
void markDirty() {
  dirty = true;
  setNote(L"Modifications en attente — cliquez sur Enregistrer.");
}
void priorityExplanation() {
  int n = (int)SendMessageW(priorityBox, CB_GETCURSEL, 0, 0);
  SetWindowTextW(
      priorityHelp,
      n == 1 ? L"Priorité CPU élevée ; un gain de FPS n'est pas garanti.\nLa "
               L"priorité GPU haute est appliquée séparément."
             : L"Priorité CPU supérieure à la normale.\nLa priorité GPU haute "
               L"est appliquée séparément.");
}
void page(int n) {
  currentPage = n;
  for (auto &[h, g] : uiGroups)
    ShowWindow(h,
               (g == -1 || (g == -2 && n != 2) || g == n) ? SW_SHOW : SW_HIDE);
  ShowWindow(detailBox, n == 2 ? SW_SHOW : SW_HIDE);
  InvalidateRect(window, nullptr, TRUE);
}
void paintCard(HDC dc, int x, int y, int w, int h) {
  HGDIOBJ old = SelectObject(dc, cardBrush);
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(39, 53, 73));
  HGDIOBJ op = SelectObject(dc, pen);
  RoundRect(dc, x, y, x + w, y + h, 20, 20);
  SelectObject(dc, op);
  SelectObject(dc, old);
  DeleteObject(pen);
}
void paintSurface() {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(window, &ps);
  RECT r;
  GetClientRect(window, &r);
  FillRect(dc, &r, bgBrush);
  paintCard(dc, 24, 84, 924, 106);
  if (currentPage == 0) {
    paintCard(dc, 24, 258, 448, 274);
    paintCard(dc, 488, 258, 460, 274);
    paintCard(dc, 24, 548, 924, 102);
  } else if (currentPage == 2)
    paintCard(dc, 24, 258, 924, 392);
  else {
    paintCard(dc, 24, 258, 924, 392);
  }
  EndPaint(window, &ps);
}
LRESULT drawButton(DRAWITEMSTRUCT *d) {
  int id = (int)d->CtlID;
  bool nav = id >= 120 && id <= 122;
  bool primary = id == 110 || id == 111;
  bool selected = nav && currentPage == id - 120;
  COLORREF fill = (primary || selected) ? RGB(43, 110, 209) : RGB(32, 45, 64);
  if (d->itemState & ODS_SELECTED)
    fill = RGB(31, 83, 157);
  HBRUSH b = CreateSolidBrush(fill);
  FillRect(d->hDC, &d->rcItem, b);
  DeleteObject(b);
  SetBkMode(d->hDC, TRANSPARENT);
  SetTextColor(d->hDC, textColor);
  SelectObject(d->hDC, font);
  wchar_t text[256];
  GetWindowTextW(d->hwndItem, text, 256);
  RECT r = d->rcItem;
  DrawTextW(d->hDC, text, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  if (d->itemState & ODS_FOCUS) {
    InflateRect(&r, -4, -4);
    DrawFocusRect(d->hDC, &r);
  }
  return TRUE;
}
std::wstring gameLabel(const std::string &path) {
  auto name = fs::path(wide(path)).stem().wstring();
  if (lower(name) == L"cs2")
    return L"Counter-Strike 2";
  if (lower(name) == L"aimlab_tb")
    return L"Aimlabs";
  if (lower(name) == L"tslgame")
    return L"PUBG: BATTLEGROUNDS";
  return name;
}
bool freshStatus(const J &s) {
  std::string t = s.value("UpdatedUtc", "");
  SYSTEMTIME st{};
  int y, M, d, h, m;
  double sec;
  if (sscanf(t.c_str(), "%d-%d-%dT%d:%d:%lf", &y, &M, &d, &h, &m, &sec) != 6)
    return false;
  st.wYear = y;
  st.wMonth = M;
  st.wDay = d;
  st.wHour = h;
  st.wMinute = m;
  st.wSecond = (WORD)sec;
  FILETIME ft{}, current;
  GetSystemTimeAsFileTime(&current);
  if (!SystemTimeToFileTime(&st, &ft))
    return false;
  uint64_t a = (uint64_t(current.dwHighDateTime) << 32) | current.dwLowDateTime,
           b = (uint64_t(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
  return a >= b && a - b < 100000000ULL;
}
void updateSummary(const J &s) {
  auto games = s.value("ActiveGames", J::array());
  auto state = s.value("State", "");
  std::wstring title, sub;
  if (state == "Error") {
    title = L"Un réglage demande votre attention";
    sub = L"Consultez « Ce qui est appliqué » pour connaître le problème.";
  } else if (!freshStatus(s) || state != "Ready") {
    title = L"Bastos Game n'est pas actif";
    sub = L"Ouvrez Bastos pour démarrer le moteur. Aucun état récent n'est "
          L"confirmé.";
  } else if (s.value("ObserveOnly", false)) {
    title = L"Optimisations en pause";
    sub = L"Bastos Game observe les jeux sans modifier leurs réglages.";
  } else if (games.empty()) {
    title = L"Prêt pour votre prochaine partie";
    sub = L"Vos jeux autorisés seront pris en charge dès leur lancement.";
  } else {
    std::set<std::wstring> names;
    bool issue = false, onlyObserve = true;
    for (auto &g : games) {
      names.insert(gameLabel(g.value("Path", "")));
      if (!g.value("ObserveOnly", false))
        onlyObserve = false;
      for (auto &a : g.value("Actions", J::array())) {
        auto outcome = a.value("Outcome", "");
        if (outcome != "Appliqué et vérifié" &&
            outcome != "Conforme et vérifié" && outcome != "Déjà conforme" &&
            outcome != "Observation — non modifié")
          issue = true;
      }
    }
    title = names.size() == 1
                ? (*names.begin() + L" est détecté")
                : std::to_wstring(names.size()) + L" jeux détectés";
    sub = onlyObserve ? L"Ce jeu est observé sans modification de ses réglages."
          : issue ? L"Certains réglages n'ont pas pu être confirmés. Consultez "
                    L"les détails."
                  : L"Les réglages demandés sont confirmés. Bonne partie !";
  }
  SetWindowTextW(heroTitle, title.c_str());
  SetWindowTextW(heroSub, sub.c_str());
}
HWND ui(const wchar_t *cls, const wchar_t *text, int id, DWORD style, int x,
        int y, int w, int h, int group, HFONT f = 0) {
  if (std::wstring(cls) == L"BUTTON" && !(style & BS_AUTOCHECKBOX))
    style |= BS_OWNERDRAW;
  HWND c = control(cls, text, id, style, x, y, w, h);
  SendMessageW(c, WM_SETFONT, (WPARAM)(f ? f : font), TRUE);
  SetWindowTheme(c, L"DarkMode_Explorer", nullptr);
  uiGroups.push_back({c, group});
  return c;
}

void createInterface() {
  titleFont = CreateFontW(-28, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET,
                          0, 0, 0, 0, L"Segoe UI");
  sectionFont = CreateFontW(-19, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET,
                            0, 0, 0, 0, L"Segoe UI");
  smallFont = CreateFontW(-14, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0,
                          0, 0, 0, L"Segoe UI");
  BOOL dark = TRUE;
  DwmSetWindowAttribute(window, 20, &dark, sizeof(dark));
  ui(L"STATIC", L"BASTOS  /  GAME", 301, 0, 24, 22, 580, 38, -1, titleFont);
  ui(L"BUTTON", L"Ouvrir Bastos", 123, WS_TABSTOP, 788, 25, 160, 36, -1);
  heroTitle = ui(L"STATIC", L"Lecture de l'état…", 302, 0, 46, 102, 870, 31, -1,
                 sectionFont);
  heroSub = ui(L"STATIC", L"", 303, 0, 46, 144, 870, 30, -1);
  ui(L"BUTTON", L"Réglages standards", 120, WS_TABSTOP, 24, 208, 294, 36, -1);
  ui(L"BUTTON", L"Profils par jeu", 121, WS_TABSTOP, 332, 208, 310, 36, -1);
  ui(L"BUTTON", L"Ce qui est appliqué", 122, WS_TABSTOP, 656, 208, 292, 36, -1);
  ui(L"STATIC", L"Pour tous vos jeux", 310, 0, 44, 279, 404, 28, 0,
     sectionFont);
  ui(L"STATIC", L"Priorité CPU par défaut", 311, 0, 44, 327, 404, 24, 0);
  priorityBox = ui(L"COMBOBOX", L"", 104, CBS_DROPDOWNLIST | WS_TABSTOP, 44,
                   359, 404, 150, 0);
  for (auto t : {L"Supérieure à la normale", L"Élevée"})
    SendMessageW(priorityBox, CB_ADDSTRING, 0, (LPARAM)t);
  priorityHelp = ui(L"STATIC", L"", 312, 0, 44, 405, 404, 49, 0, smallFont);
  threadCheck = ui(L"BUTTON", L"Favoriser les threads clés du jeu", 108,
                   BS_AUTOCHECKBOX | WS_TABSTOP, 44, 470, 404, 28, 0);
  ui(L"STATIC", L"Les profils personnels peuvent remplacer ces choix.", 313, 0,
     44, 502, 404, 25, 0, smallFont);
  ui(L"STATIC", L"Applications en arrière-plan", 320, 0, 510, 279, 414, 28, 0,
     sectionFont);
  backgroundCheck = ui(L"BUTTON", L"Limiter les autres applications", 107,
                       BS_AUTOCHECKBOX | WS_TABSTOP, 510, 330, 410, 28, 0);
  ecoCheck = ui(L"BUTTON", L"Économie d'énergie en arrière-plan (EcoQoS)", 109,
                BS_AUTOCHECKBOX | WS_TABSTOP, 510, 379, 410, 28, 0, smallFont);
  ioCheck =
      ui(L"BUTTON", L"Priorité réduite des accès disque en arrière-plan", 114,
         BS_AUTOCHECKBOX | WS_TABSTOP, 510, 421, 410, 28, 0, smallFont);
  ui(L"STATIC",
     L"S'applique pendant une partie aux applications autorisées.\nVos "
     L"exclusions restent prioritaires.",
     322, 0, 510, 474, 410, 47, 0, smallFont);
  observeCheck = ui(L"BUTTON", L"Mettre toutes les optimisations en pause", 102,
                    BS_AUTOCHECKBOX | WS_TABSTOP, 44, 568, 864, 29, 0);
  ui(L"STATIC",
     L"Restaure les réglages modifiés, puis observe vos jeux sans intervenir.",
     330, 0, 44, 611, 864, 28, 0, smallFont);
  ui(L"STATIC", L"Préparer un profil par jeu", 314, 0, 44, 279, 880, 28, 1,
     sectionFont);
  gameList = ui(L"COMBOBOX", L"", 101, CBS_DROPDOWNLIST | WS_TABSTOP, 44, 321,
                864, 180, 1);
  gamePath = ui(L"EDIT", L"", 125,
                ES_READONLY | ES_AUTOHSCROLL | WS_TABSTOP | WS_BORDER, 44, 361,
                864, 25, 1, smallFont);
  ui(L"BUTTON", L"Ajouter un fichier .exe…", 118, WS_TABSTOP, 44, 397, 270, 30,
     1);
  ui(L"BUTTON", L"Détecter les jeux Steam", 119, WS_TABSTOP, 330, 397, 270, 30,
     1);
  gameHint = ui(L"STATIC", L"", 315, 0, 44, 435, 864, 25, 1, smallFont);
  gameCustomCheck =
      ui(L"BUTTON", L"Utiliser un profil personnalisé pour ce jeu", 116,
         BS_AUTOCHECKBOX | WS_TABSTOP, 44, 469, 864, 28, 1);
  ui(L"STATIC", L"Priorité CPU de ce jeu", 316, 0, 44, 506, 390, 25, 1);
  gamePriorityBox = ui(L"COMBOBOX", L"", 115, CBS_DROPDOWNLIST | WS_TABSTOP, 44,
                       537, 390, 130, 1);
  for (auto t : {L"Supérieure à la normale", L"Élevée"})
    SendMessageW(gamePriorityBox, CB_ADDSTRING, 0, (LPARAM)t);
  gameThreadCheck = ui(L"BUTTON", L"Favoriser les threads clés de ce jeu", 117,
                       BS_AUTOCHECKBOX | WS_TABSTOP, 488, 506, 420, 28, 1);
  gameObserve = ui(L"BUTTON", L"Observer ce jeu sans optimisation", 105,
                   BS_AUTOCHECKBOX | WS_TABSTOP, 488, 543, 420, 28, 1);
  auxCheck = ui(L"BUTTON", L"Alléger le lanceur de PUBG", 103,
                BS_AUTOCHECKBOX | WS_TABSTOP, 44, 587, 864, 28, 3);
  auxHelp =
      ui(L"STATIC",
         L"Appliqué automatiquement dès la détection du lancement de PUBG.",
         321, 0, 44, 620, 864, 26, 3, smallFont);
  ui(L"STATIC", L"Vérification des réglages", 340, 0, 44, 278, 880, 28, 2,
     sectionFont);
  ui(L"STATIC",
     L"Les valeurs appliquées sont relues pour confirmer chaque action.", 341,
     0, 44, 313, 880, 26, 2, smallFont);
  detailBox = control(L"EDIT", L"", 106,
                      ES_MULTILINE | ES_READONLY | WS_VSCROLL | ES_AUTOVSCROLL |
                          WS_TABSTOP,
                      44, 354, 884, 275);
  SendMessageW(detailBox, WM_SETFONT, (WPARAM)smallFont, TRUE);
  SetWindowTheme(detailBox, L"DarkMode_Explorer", nullptr);
  ui(L"BUTTON", L"Enregistrer mes réglages", 110, WS_TABSTOP, 24, 672, 270, 42,
     -2);
  ui(L"BUTTON", L"Annuler les modifications", 113, WS_TABSTOP, 310, 672, 248,
     42, -2);
  ui(L"BUTTON", L"Ouvrir l'historique", 112, WS_TABSTOP, 24, 672, 260, 42, 2);
  saveNote =
      ui(L"STATIC",
         L"Les réglages standards s'appliquent aux jeux sans profil personnel.",
         360, 0, 24, 730, 924, 30, -1, smallFont);
  detectInstalledGames(false);
  refreshDetails();
  page(0);
  personalOptions();
}
