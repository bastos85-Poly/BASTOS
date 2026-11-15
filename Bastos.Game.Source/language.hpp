#pragma once
#include "language-catalog.hpp"
// Presentation only. Engine configuration, outcomes and process policies stay unchanged.
fs::path gameLanguageFile;
bool gameEnglish = false;
std::map<HWND, std::wstring> gameOriginalText;
std::map<HWND, std::vector<std::wstring>> gameOriginalChoices;
std::wstring gameText(const std::wstring &source) {
  if (!gameEnglish || source.empty()) return source;
  static const J catalog = J::parse(gameLanguageCatalog);
  auto key = utf8(source);
  if (catalog.contains(key)) return wide(catalog.at(key).get<std::string>());
  auto first=source.find_first_not_of(L" \r\t");
  auto last=source.find_last_not_of(L" \r\t");
  if(first!=std::wstring::npos && (first!=0 || last+1!=source.size())) {
    auto middle=source.substr(first,last-first+1);
    return source.substr(0,first)+gameText(middle)+source.substr(last+1);
  }
  auto newline = source.find(L'\n');
  if (newline != std::wstring::npos)
    return gameText(source.substr(0,newline)) + L"\n" + gameText(source.substr(newline+1));
  const std::wstring detected = L" est détecté", many = L" jeux détectés";
  if (source.ends_with(detected)) return source.substr(0,source.size()-detected.size()) + L" detected";
  if (source.ends_with(many)) return source.substr(0,source.size()-many.size()) + L" games detected";
  for(auto it=catalog.begin();it!=catalog.end();++it) if(it.key().starts_with(" ")) {
    auto suffix=wide(it.key());
    if(source.ends_with(suffix)) return source.substr(0,source.size()-suffix.size())+wide(it.value().get<std::string>());
  }
  return source;
}
std::string gameNarrow(const std::string &source) { return utf8(gameText(wide(source))); }
bool refreshGameLanguage() {
  std::ifstream file(gameLanguageFile); std::string value; file >> value;
  bool next = value == "en";
  if(next == gameEnglish) return false;
  gameEnglish = next;
  for(const auto &[handle,text] : gameOriginalText)
    if(IsWindow(handle)) SetWindowTextW(handle,gameText(text).c_str());
  for(const auto &[handle,choices] : gameOriginalChoices) if(IsWindow(handle)) {
    auto selected=SendMessageW(handle,CB_GETCURSEL,0,0);
    SendMessageW(handle,CB_RESETCONTENT,0,0);
    for(const auto &text:choices) SendMessageW(handle,CB_ADDSTRING,0,(LPARAM)gameText(text).c_str());
    SendMessageW(handle,CB_SETCURSEL,selected,0);
  }
  return true;
}
BOOL gameSetWindowText(HWND handle,LPCWSTR text) {
  gameOriginalText[handle]=text ? text : L"";
  return SetWindowTextW(handle,gameText(gameOriginalText[handle]).c_str());
}
HWND gameCreateWindow(DWORD ex,LPCWSTR cls,LPCWSTR text,DWORD style,int x,int y,int w,int h,HWND parent,HMENU menu,HINSTANCE instance,LPVOID param) {
  auto translated=gameText(text ? text : L"");
  auto handle=CreateWindowExW(ex,cls,translated.c_str(),style,x,y,w,h,parent,menu,instance,param);
  if(handle) gameOriginalText[handle]=text ? text : L"";
  return handle;
}
BOOL gameAppendMenu(HMENU menu,UINT flags,UINT_PTR id,LPCWSTR text) {
  auto translated=gameText(text ? text : L"");
  return AppendMenuW(menu,flags,id,text ? translated.c_str() : nullptr);
}
LRESULT gameSendMessage(HWND handle,UINT message,WPARAM wp,LPARAM lp) {
  if(message==CB_ADDSTRING && lp) {
    auto text=(LPCWSTR)lp; gameOriginalChoices[handle].push_back(text);
    return SendMessageW(handle,message,wp,(LPARAM)gameText(text).c_str());
  }
  if(message==CB_RESETCONTENT) gameOriginalChoices.erase(handle);
  return SendMessageW(handle,message,wp,lp);
}
int gameMessageBox(HWND owner,LPCWSTR text,LPCWSTR title,UINT flags) {
  return MessageBoxW(owner,gameText(text ? text : L"").c_str(),gameText(title ? title : L"").c_str(),flags);
}
#define SetWindowTextW gameSetWindowText
#define CreateWindowExW gameCreateWindow
#define AppendMenuW gameAppendMenu
#define SendMessageW gameSendMessage
#define MessageBoxW gameMessageBox
