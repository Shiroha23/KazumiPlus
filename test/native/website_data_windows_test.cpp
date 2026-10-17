// Offline native regression: all account data is synthetic, in a temporary profile.
#include "website_data.h"
#include <WebView2EnvironmentOptions.h>
#include <flutter/standard_method_codec.h>
#include <shlwapi.h>
#include <wrl.h>
#include <filesystem>
#include <iostream>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {
struct TestMessenger : flutter::BinaryMessenger {
  flutter::BinaryMessageHandler handler;
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply = nullptr) const override {}
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler value) override {
    handler = std::move(value);
  }
};

bool Wait(const std::function<bool()>& done) {
  const auto deadline = GetTickCount64() + 30000;
  while (!done() && GetTickCount64() < deadline) {
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
    MSG message{};
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
  }
  return done();
}

struct Browser {
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> view;
  ComPtr<ICoreWebView2CookieManager> cookies;
  HWND window = nullptr;

  ~Browser() {
    if (controller) controller->Close();
    if (window) DestroyWindow(window);
  }

  bool Open(const std::wstring& profile) {
    WNDCLASSW window_class{};
    window_class.lpszClassName = L"WebsiteDataTest";
    window_class.lpfnWndProc = [](HWND hwnd, UINT message, WPARAM wp, LPARAM lp) -> LRESULT {
      if (message == kWebsiteDataCompletionMessage) {
        CompleteWebsiteDataDeletion(lp); return 0;
      }
      return DefWindowProc(hwnd, message, wp, lp);
    };
    RegisterClassW(&window_class);
    window = CreateWindowExW(0, window_class.lpszClassName, L"Website data test", WS_POPUP,
                              0, 0, 100, 100, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
    bool complete = false;
    HRESULT status = E_FAIL;
    auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
    options->put_AdditionalBrowserArguments(L"--disable-site-isolation-trials --disable-web-security --msEdgeWebViewApplyWebResourceRequestedFilterForOOPIFs");
    const auto created = CreateCoreWebView2EnvironmentWithOptions(nullptr, profile.c_str(), options.Get(),
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [&](HRESULT hr, ICoreWebView2Environment* value) -> HRESULT {
            status = hr; environment = value; complete = true; return S_OK;
          }).Get());
    if (FAILED(created) || !Wait([&] { return complete; }) || FAILED(status)) return false;
    complete = false;
    const auto controlled = environment->CreateCoreWebView2Controller(window,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
          [&](HRESULT hr, ICoreWebView2Controller* value) -> HRESULT {
            status = hr; controller = value; complete = true; return S_OK;
          }).Get());
    if (FAILED(controlled) || !Wait([&] { return complete; }) || FAILED(status)) return false;
    controller->put_IsVisible(FALSE);
    if (FAILED(controller->get_CoreWebView2(&view))) return false;
    ComPtr<ICoreWebView2_2> view2;
    if (FAILED(view.As(&view2)) || FAILED(view2->get_CookieManager(&cookies))) return false;
    view->AddWebResourceRequestedFilter(L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    EventRegistrationToken token{};
    view->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>(
        [this](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
          const char html[] = "<!doctype html><title>Offline website account fixture</title>";
          ComPtr<IStream> stream;
          stream.Attach(SHCreateMemStream(reinterpret_cast<const BYTE*>(html), sizeof(html) - 1));
          ComPtr<ICoreWebView2WebResourceResponse> response;
          const auto hr = environment->CreateWebResourceResponse(stream.Get(), 200, L"OK",
              L"Content-Type: text/html; charset=utf-8", &response);
          return FAILED(hr) ? hr : args->put_Response(response.Get());
        }).Get(), &token);
    return true;
  }

  bool Navigate(const wchar_t* url) {
    bool complete = false;
    bool success = false;
    EventRegistrationToken token{};
    view->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
        [&](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
          BOOL ok = FALSE; args->get_IsSuccess(&ok); success = ok != FALSE;
          complete = true; return S_OK;
        }).Get(), &token);
    const auto hr = view->Navigate(url);
    const bool finished = SUCCEEDED(hr) && Wait([&] { return complete; });
    view->remove_NavigationCompleted(token);
    return finished && success;
  }

  std::wstring Script(const wchar_t* script) {
    bool complete = false;
    std::wstring response;
    const auto hr = view->ExecuteScript(script, Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
        [&](HRESULT status, LPCWSTR json) -> HRESULT {
          if (SUCCEEDED(status) && json) response = json;
          complete = true; return S_OK;
        }).Get());
    if (FAILED(hr) || !Wait([&] { return complete; })) return L"ERROR";
    return response;
  }

  bool SetCookie(const wchar_t* name, const wchar_t* domain, const wchar_t* path) {
    ComPtr<ICoreWebView2Cookie> cookie;
    if (FAILED(cookies->CreateCookie(name, L"synthetic-account", domain, path, &cookie))) return false;
    cookie->put_IsHttpOnly(TRUE);
    cookie->put_IsSecure(TRUE);
    cookie->put_Expires(4102444800.0);
    return SUCCEEDED(cookies->AddOrUpdateCookie(cookie.Get()));
  }

  int CookieCount(const wchar_t* url) {
    bool complete = false;
    int count = -1;
    const auto hr = cookies->GetCookies(url, Callback<ICoreWebView2GetCookiesCompletedHandler>(
        [&](HRESULT status, ICoreWebView2CookieList* list) -> HRESULT {
          UINT size = 0;
          if (SUCCEEDED(status) && list && SUCCEEDED(list->get_Count(&size))) count = static_cast<int>(size);
          complete = true; return S_OK;
        }).Get());
    return SUCCEEDED(hr) && Wait([&] { return complete; }) ? count : -1;
  }
};

int Run() {
  GUID id{};
  CoCreateGuid(&id);
  wchar_t guid[40]{};
  StringFromGUID2(id, guid, 40);
  const auto profile = std::filesystem::temp_directory_path() /
      (std::wstring(L"kazumi-website-data-test-") + guid);
  Browser browser;
  if (!browser.Open(profile.wstring())) { std::cerr << "Cannot create isolated test profile\n"; return 1; }
  if (!browser.SetCookie(L"root-auth", L".account.test", L"/private") ||
      !browser.SetCookie(L"api-auth", L"api.account.test", L"/hidden") ||
      !browser.SetCookie(L"other-auth", L"unrelated.test", L"/") ||
      !browser.SetCookie(L"lookalike-auth", L"account.test.evil.test", L"/")) return 2;
  for (auto origin : {L"https://account.test/", L"https://www.account.test/",
                      L"https://api.account.test/", L"https://unrelated.test/"}) {
    if (!browser.Navigate(origin) || browser.Script(L"localStorage.setItem('account', 'synthetic'); true") != L"true") return 3;
  }
  if (browser.CookieCount(L"https://account.test/private") != 1 ||
      browser.CookieCount(L"https://api.account.test/hidden") != 1) return 4;
  bool complete = false;
  HRESULT result = E_FAIL;
  DeleteWebsiteData(browser.view.Get(), L"account.test", {L"https://account.test",
      L"https://www.account.test", L"https://api.account.test"}, [&](HRESULT status) {
    result = status; complete = true;
  });
  if (!Wait([&] { return complete; }) || FAILED(result)) return 5;
  if (browser.CookieCount(L"https://account.test/private") != 0 ||
      browser.CookieCount(L"https://api.account.test/hidden") != 0 ||
      browser.CookieCount(L"https://unrelated.test/") != 1 ||
      browser.CookieCount(L"https://account.test.evil.test/") != 1) return 6;
  for (auto origin : {L"https://account.test/", L"https://www.account.test/", L"https://api.account.test/"}) {
    if (!browser.Navigate(origin) || browser.Script(L"localStorage.getItem('account')") != L"null") return 7;
  }
  if (!browser.Navigate(L"https://unrelated.test/") ||
      browser.Script(L"localStorage.getItem('account')") != L"\"synthetic\"") return 8;
  complete = false;
  DeleteWebsiteData(browser.view.Get(), L"account.test", {L"https://unrelated.test"},
      [&](HRESULT status) { result = status; complete = true; });
  if (!complete || result != E_INVALIDARG || browser.CookieCount(L"https://unrelated.test/") != 1) return 9;
  if (!browser.SetCookie(L"parent-auth", L".account.test", L"/private") ||
      !browser.SetCookie(L"parent-only", L"account.test", L"/private") ||
      !browser.Navigate(L"https://account.test/") ||
      browser.Script(L"localStorage.setItem('account', 'parent-only'); true") != L"true") return 11;
  complete = false;
  DeleteWebsiteData(browser.view.Get(), L"api.account.test", {L"https://api.account.test"},
      [&](HRESULT status) { result = status; complete = true; });
  if (!Wait([&] { return complete; }) || FAILED(result) ||
      browser.CookieCount(L"https://api.account.test/private") != 0 ||
      browser.CookieCount(L"https://unrelated.test/") != 1 ||
      browser.CookieCount(L"https://account.test/private") != 1 ||
      browser.Script(L"localStorage.getItem('account')") != L"\"parent-only\"") return 12;
  // Exercise the real channel's temporary environment/controller lifecycle.
  TestMessenger messenger;
  RegisterWebsiteDataChannel(&messenger, browser.window, profile.wstring());
  const auto message = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
      flutter::MethodCall<flutter::EncodableValue>("deleteAccountData",
          std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
            {flutter::EncodableValue("host"), flutter::EncodableValue("account.test")},
            {flutter::EncodableValue("origins"), flutter::EncodableValue(flutter::EncodableList{
              flutter::EncodableValue("https://account.test")})}})));
  for (int i = 0; i < 3; ++i) {
    if (!browser.SetCookie(L"channel-auth", L".account.test", L"/private")) return 13;
    complete = false;
    bool success = false;
    messenger.handler(message->data(), message->size(), [&](const uint8_t* reply, size_t size) {
      success = size == 2 && reply[0] == 0; complete = true;
    });
    if (!Wait([&] { return complete; }) || !success ||
        browser.CookieCount(L"https://account.test/private") != 0 ||
        browser.CookieCount(L"https://unrelated.test/") != 1) return 14;
  }
  std::cout << "PASS: HttpOnly/path/subdomain cookies and website storage deleted; other sites preserved.\n";
  return 0;
}
}  // namespace

int main() {
  const auto hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(hr)) return 10;
  const auto result = Run();
  if (result != 0) std::cerr << "Website data regression failed at stage " << result << "\n";
  CoUninitialize();
  return result;
}
