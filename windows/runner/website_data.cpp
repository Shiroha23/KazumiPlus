#include "website_data.h"

#include <WebView2EnvironmentOptions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <winhttp.h>
#include <wrl.h>
#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <memory>
#include <set>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
namespace {
std::wstring Wide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                     value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::wstring Host(std::wstring value) {
  while (!value.empty() && value.front() == L'.') value.erase(0, 1);
  while (!value.empty() && value.back() == L'.') value.pop_back();
  std::transform(value.begin(), value.end(), value.begin(), towlower);
  if (value.compare(0, 4, L"www.") == 0) value.erase(0, 4);
  return value;
}

bool Matches(const std::wstring& domain, const std::wstring& scope) {
  const auto host = Host(domain);
  return host == scope || (host.size() > scope.size() &&
      host.compare(host.size() - scope.size() - 1, scope.size() + 1, L"." + scope) == 0);
}

bool ValidHost(const std::wstring& host) {
  return !host.empty() && std::all_of(host.begin(), host.end(), [](wchar_t c) {
    return iswalnum(c) || c == L'.' || c == L'-' || c == L'_' ||
           c == L':' || c == L'[' || c == L']';
  });
}

bool MatchingOrigin(const std::wstring& origin, const std::wstring& scope) {
  URL_COMPONENTS parts{};
  parts.dwStructSize = sizeof(parts);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  parts.dwUrlPathLength = static_cast<DWORD>(-1);
  parts.dwExtraInfoLength = static_cast<DWORD>(-1);
  if (!WinHttpCrackUrl(origin.c_str(), static_cast<DWORD>(origin.size()), 0, &parts)) return false;
  return (parts.nScheme == INTERNET_SCHEME_HTTP || parts.nScheme == INTERNET_SCHEME_HTTPS) &&
      parts.dwExtraInfoLength == 0 && parts.dwUrlPathLength == 0 &&
      Matches(std::wstring(parts.lpszHostName, parts.dwHostNameLength), scope);
}

std::wstring JsonString(const std::wstring& value) {
  std::wstring result = L"\"";
  for (auto c : value) {
    if (c == L'"' || c == L'\\') result += L'\\';
    result += c;
  }
  return result + L"\"";
}

struct Deletion : std::enable_shared_from_this<Deletion> {
  ComPtr<ICoreWebView2> view;
  ComPtr<ICoreWebView2CookieManager> cookies;
  std::wstring host;
  std::set<std::wstring> origins;
  std::function<void(HRESULT)> completed;

  void Finish(HRESULT hr) {
    if (!completed) return;
    auto callback = std::move(completed);
    callback(hr);
  }

  void ClearNextOrigin() {
    if (origins.empty()) { Finish(S_OK); return; }
    const auto origin = *origins.begin();
    origins.erase(origins.begin());
    const auto args = L"{\"origin\":" + JsonString(origin) + L",\"storageTypes\":\"all\"}";
    auto self = shared_from_this();
    const auto hr = view->CallDevToolsProtocolMethod(L"Storage.clearDataForOrigin", args.c_str(),
        Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
            [self](HRESULT status, LPCWSTR response) -> HRESULT {
              if (FAILED(status) || (response && std::wstring(response).find(L"\"error\"") != std::wstring::npos)) {
                self->Finish(FAILED(status) ? status : E_FAIL);
              } else {
                self->ClearNextOrigin();
              }
              return S_OK;
            }).Get());
    if (FAILED(hr)) Finish(hr);
  }

  void Start() {
    ComPtr<ICoreWebView2_2> view2;
    auto hr = view.As(&view2);
    if (SUCCEEDED(hr)) hr = view2->get_CookieManager(&cookies);
    if (FAILED(hr)) { Finish(hr); return; }
    auto self = shared_from_this();
    hr = cookies->GetCookies(nullptr, Callback<ICoreWebView2GetCookiesCompletedHandler>(
        [self](HRESULT status, ICoreWebView2CookieList* list) -> HRESULT {
          if (FAILED(status) || !list) { self->Finish(FAILED(status) ? status : E_FAIL); return S_OK; }
          UINT count = 0;
          auto result = list->get_Count(&count);
          for (UINT i = 0; SUCCEEDED(result) && i < count; ++i) {
            ComPtr<ICoreWebView2Cookie> cookie;
            result = list->GetValueAtIndex(i, &cookie);
            LPWSTR domain = nullptr;
            if (SUCCEEDED(result)) result = cookie->get_Domain(&domain);
            const std::wstring domain_value = domain ? domain : L"";
            CoTaskMemFree(domain);
            // A parent-domain cookie also authenticates the selected subdomain.
            // Host-only cookies on a parent/sibling site are never included.
            const bool parent_domain_cookie = !domain_value.empty() &&
                domain_value.front() == L'.' && Matches(self->host, Host(domain_value));
            const bool in_scope = Matches(domain_value, self->host);
            if (SUCCEEDED(result) && (in_scope || parent_domain_cookie)) {
              // A shared parent cookie is applicable here, but the parent's
              // host-only cookies and web storage belong to a different scope.
              if (in_scope) {
                std::wstring origin_host = domain_value;
                while (!origin_host.empty() && origin_host.front() == L'.') origin_host.erase(0, 1);
                self->origins.insert(L"https://" + origin_host);
                self->origins.insert(L"http://" + origin_host);
              }
              result = self->cookies->DeleteCookie(cookie.Get());
            }
          }
          if (FAILED(result)) self->Finish(result); else self->ClearNextOrigin();
          return S_OK;
        }).Get());
    if (FAILED(hr)) Finish(hr);
  }
};

struct BrowserSession {
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Controller> controller;
};

void CompleteLater(HWND parent, std::shared_ptr<BrowserSession> session,
                   std::function<void()> reply) {
  // Closing the controller from a CDP callback destroys CdpHelper while it is
  // still dispatching the response. Keep it alive until the next window message.
  auto task = std::make_unique<std::function<void()>>(
      [session, reply = std::move(reply)] {
        if (session->controller) session->controller->Close();
        reply();
      });
  if (PostMessage(parent, kWebsiteDataCompletionMessage, 0,
                  reinterpret_cast<LPARAM>(task.get()))) {
    task.release();
  } else {
    // If the parent has already gone away, retain the controller until process
    // teardown. Releasing its final reference here can cause the same crash as
    // Close() while CDP is still dispatching the response.
    session->controller.Detach();
  }
}

std::wstring DefaultProfileFolder() {
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) return {};
  std::filesystem::path folder(local);
  CoTaskMemFree(local);
  wchar_t filename[MAX_PATH]{};
  if (!GetModuleFileNameW(nullptr, filename, MAX_PATH)) return {};
  // Same persistent profile as the pinned webview_windows dependency.
  return (folder / L"flutter_webview_windows" / std::filesystem::path(filename).stem()).wstring();
}
}  // namespace

void CompleteWebsiteDataDeletion(LPARAM task) {
  std::unique_ptr<std::function<void()>> completion(
      reinterpret_cast<std::function<void()>*>(task));
  (*completion)();
}

void DeleteWebsiteData(ICoreWebView2* webview, const std::wstring& host,
                       const std::vector<std::wstring>& origins,
                       std::function<void(HRESULT)> completed) {
  auto deletion = std::make_shared<Deletion>();
  deletion->view = webview;
  deletion->host = Host(host);
  deletion->completed = std::move(completed);
  if (!webview || !ValidHost(deletion->host)) { deletion->Finish(E_INVALIDARG); return; }
  for (const auto& origin : origins) {
    if (!MatchingOrigin(origin, deletion->host)) { deletion->Finish(E_INVALIDARG); return; }
    deletion->origins.insert(origin);
  }
  for (const auto& scheme : {L"https://", L"http://"}) {
    deletion->origins.insert(std::wstring(scheme) + deletion->host);
    if (deletion->host.find(L':') == std::wstring::npos) {
      deletion->origins.insert(std::wstring(scheme) + L"www." + deletion->host);
    }
  }
  deletion->Start();
}

void RegisterWebsiteDataChannel(flutter::BinaryMessenger* messenger, HWND parent,
                               const std::wstring& profile_folder) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.predidit.kazumi/website_data", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([parent, profile_folder](const auto& call, auto unique_result) {
    if (call.method_name() != "deleteAccountData") { unique_result->NotImplemented(); return; }
    auto result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(unique_result));
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("INVALID_ARGUMENT", "Website arguments required"); return; }
    const auto host_it = args->find(flutter::EncodableValue("host"));
    const auto* raw_host = host_it == args->end() ? nullptr : std::get_if<std::string>(&host_it->second);
    if (!raw_host || !ValidHost(Host(Wide(*raw_host)))) { result->Error("INVALID_ARGUMENT", "Invalid website host"); return; }
    const auto host = Host(Wide(*raw_host));
    std::vector<std::wstring> origins;
    const auto origins_it = args->find(flutter::EncodableValue("origins"));
    const auto* raw_origins = origins_it == args->end() ? nullptr : std::get_if<flutter::EncodableList>(&origins_it->second);
    if (raw_origins) {
      for (const auto& value : *raw_origins) {
        const auto* origin = std::get_if<std::string>(&value);
        if (!origin || !MatchingOrigin(Wide(*origin), host)) { result->Error("INVALID_ARGUMENT", "Origin is outside website"); return; }
        origins.push_back(Wide(*origin));
      }
    }
    auto folder = profile_folder.empty() ? DefaultProfileFolder() : profile_folder;
    if (folder.empty()) { result->Error("PROFILE_UNAVAILABLE", "Cannot locate browser profile"); return; }
    auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
    std::wstring browser_args = L"--disable-site-isolation-trials --disable-web-security --msEdgeWebViewApplyWebResourceRequestedFilterForOOPIFs";
    const auto extra = args->find(flutter::EncodableValue("additionalArguments"));
    if (extra != args->end()) {
      const auto* value = std::get_if<std::string>(&extra->second);
      if (value && !value->empty()) browser_args += L" " + Wide(*value);
    }
    options->put_AdditionalBrowserArguments(browser_args.c_str());
    auto session = std::make_shared<BrowserSession>();
    const auto hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, folder.c_str(), options.Get(),
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [parent, session, result, host, origins](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
            if (FAILED(status) || !environment) { result->Error("PROFILE_UNAVAILABLE", "Cannot open website profile"); return S_OK; }
            session->environment = environment;
            const auto created = environment->CreateCoreWebView2Controller(parent,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                  [parent, session, result, host, origins](HRESULT controller_status, ICoreWebView2Controller* controller) -> HRESULT {
                    if (FAILED(controller_status) || !controller) { result->Error("PROFILE_UNAVAILABLE", "Cannot open website data controller"); return S_OK; }
                    session->controller = controller;
                    controller->put_IsVisible(FALSE);
                    ComPtr<ICoreWebView2> view;
                    const auto opened = controller->get_CoreWebView2(&view);
                    if (FAILED(opened)) {
                      CompleteLater(parent, session, [result] { result->Error("PROFILE_UNAVAILABLE", "Cannot open website data"); });
                      return S_OK;
                    }
                    DeleteWebsiteData(view.Get(), host, origins, [parent, session, result](HRESULT deleted) {
                      CompleteLater(parent, session, [result, deleted] {
                        if (FAILED(deleted)) result->Error("DELETE_FAILED", "Website account data could not be completely deleted");
                        else result->Success();
                      });
                    });
                    return S_OK;
                  }).Get());
            if (FAILED(created)) result->Error("PROFILE_UNAVAILABLE", "Cannot create website data controller");
            return S_OK;
          }).Get());
    if (FAILED(hr)) result->Error("PROFILE_UNAVAILABLE", "Cannot initialize website profile");
  });
}
