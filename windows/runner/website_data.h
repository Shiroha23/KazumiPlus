#ifndef RUNNER_WEBSITE_DATA_H_
#define RUNNER_WEBSITE_DATA_H_

#include <windows.h>
#include <WebView2.h>
#include <flutter/binary_messenger.h>
#include <functional>
#include <string>
#include <vector>

// Operates on the supplied profile; never deletes another site's data.
void DeleteWebsiteData(ICoreWebView2* webview, const std::wstring& host,
                       const std::vector<std::wstring>& origins,
                       std::function<void(HRESULT)> completed);
void RegisterWebsiteDataChannel(flutter::BinaryMessenger* messenger, HWND parent,
                               const std::wstring& profile_folder = L"");
// Dispatch cleanup after WebView2 has returned from its completion callback.
constexpr UINT kWebsiteDataCompletionMessage = WM_APP + 43;
void CompleteWebsiteDataDeletion(LPARAM task);

#endif
