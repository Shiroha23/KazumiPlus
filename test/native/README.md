# Website account-data deletion (Windows)

The native regression uses a unique temporary WebView2 profile and offline
synthetic pages. It checks deletion of HttpOnly cookies, cookies on private
paths and subdomains, and localStorage. An unrelated site's cookies and storage,
and a lookalike hostname's cookies, must survive. Deleting a subdomain removes
applicable shared parent cookies while preserving the parent's host-only cookies
and storage. Cross-site origin input is rejected before any deletion.

The real platform channel is also invoked repeatedly, including its temporary
environment/controller creation and deferred cleanup. Closing the controller
inside the CDP completion callback previously crashed the WebView2 runtime;
this regression exercises that lifecycle as well as the deletion helper.

With the Windows Flutter and CMake toolchains available:

```powershell
flutter build windows --debug
cmake -S windows -B build/windows/x64 -DKAZUMI_WEBSITE_DATA_TESTS=ON
cmake --build build/windows/x64 --config Debug --target website_data_test
./build/windows/x64/website_data_tests/Debug/website_data_test.exe
```

The test leaves its synthetic profile under the system temporary directory for
inspection. Normal builds do not enable this executable.
