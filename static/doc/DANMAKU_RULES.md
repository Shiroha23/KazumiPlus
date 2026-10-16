# 网站弹幕规则

规则 API 10 支持可选的 `danmakuConfig`。在「规则编辑器 → 弹幕」中编辑配置，并输入播放页 URL 测试。配置随规则保存、导入、导出和分享，无需为每个网站增加 Dart 代码。

通用的是请求和解析机制，每个网站仍需提供正确的接口配置。引擎不会自动推断所有网站的私有接口，也不会执行网页 JavaScript。

`danmakuConfig` 为 `null` 或 `enabled: false` 时使用原有弹弹play服务。启用网站弹幕后，空列表表示该集暂无网站弹幕；请求或映射失败会报告规则错误。开启「下载弹幕」后也会缓存网站弹幕供离线播放。

## 单次 JSON 请求

下面内容可以直接放入编辑器的弹幕配置框；实际接口和字段名需按网站调整。

```json
{
  "enabled": true,
  "format": "json",
  "steps": [
    {
      "request": {
        "method": "GET",
        "url": "/api/danmaku",
        "query": {"episode": "@episodeNumber"},
        "headers": {"Accept": "application/json"}
      }
    }
  ],
  "listPath": "$.data[*]",
  "contentPath": "$.content",
  "timePath": "$.time",
  "modePath": "$.mode",
  "colorPath": "$.color",
  "timeScale": 1
}
```

对应响应示例：

```json
{"data":[{"content":"这是一条弹幕","time":1.418,"mode":"top","color":"#ffffff"}]}
```

JSONPath 支持字段、数组索引、`[*]` 和带引号的字段名，与搜索/选集规则使用相同的受限语法。时间为秒，毫秒接口设置 `timeScale: 0.001`。颜色支持 RGB 整数、十六进制数字字符串或 `#RRGGBB`。默认模式为滚动，`top`/`5` 表示顶部，`bottom`/`4` 表示底部；可通过 `modeMap` 自定义。

## 请求模板变量

| 变量 | 含义 |
|---|---|
| `@pageUrl` | 当前剧集播放页 URL |
| `@origin` | 播放页协议和域名，用于 `@origin/api/...` |
| `@videoUrl` | 当前解析到的视频 URL；编辑器测试时为空 |
| `@episodeNumber` | 当前集数，从 1 起，可被播放页命名捕获覆盖 |
| `@episodeIndex` | 当前集数减 1 |
| `@pageNumber` / `@pageIndex` | 当前步骤配置 `pageSize` 后计算出的页码和页内索引 |

`pagePattern` 对播放页 URL 执行正则，命名捕获组成为变量。例如 `/play/(?<episodeNumber>\d+)`。`defaults` 提供默认变量，`queryVariables` 从播放页查询参数读取，例如 `{"line":"from"}` 将 `?from=abc` 存为 `@line`。

请求支持 GET/POST、JSON 或表单请求体，与现有 API 规则的 `request` 结构一致。URL 路径内的变量会转义；查询参数和请求体中独立的变量会保留原始类型。请求地址可为同站绝对路径 `/api/...`、完整 HTTP/HTTPS 地址或保存了完整地址的单独变量。

请求默认带播放页 Referer，并按目标网站复用已保存会话的 Cookie 和浏览器 User-Agent，同站新规则自动复用；请求头可自行配置。Cookie 依照目标域名匹配，不会因为请求链跨域而自动转发给其他域名。

## 先查分集 ID，再查弹幕

`steps` 按顺序执行。预请求可通过 `captures` 将响应中的 JSONPath 保存为后续变量。若配置 `listPath`，先从列表选择当前集，再读取 `captures`。

```json
{
  "pagePattern": "/anime/(?<videoId>\\d+)/play/(?<episodeNumber>\\d+)",
  "steps": [
    {
      "request": {"url":"/api/videos/@videoId/sections"},
      "listPath":"$.data.list[*]",
      "matchPath":"$.order",
      "matchValue":"@episodeNumber",
      "index":"@episodeIndex",
      "captures":{"sectionId":"$.id"},
      "successPath":"$.code",
      "successValue":0
    },
    {"request":{"url":"/api/sections/@sectionId/danmaku"}}
  ],
  "listPath":"$.data.items[*]",
  "contentPath":"$.content",
  "timePath":"$.time_point"
}
```

如果列表有 `matchPath` 对应字段，按 `matchValue` 匹配，找不到就报错；列表没有该字段时才按 `index` 选择。分页接口可在步骤中配置 `pageSize: 100`，请求使用 `page: "@pageNumber"`，列表选择使用 `index: "@pageIndex"`。若接口不分页，应使用 `@episodeIndex`。

`successPath`/`successValue` 可检查 HTTP 200 响应内的业务状态。接口返回失败、变量未找到或请求取消时，后续步骤不会执行。

## 从播放页提取变量

对于将弹幕 ID 或地址写在 HTML 中的网站，可先请求 `@pageUrl`，使用 `regexCaptures` 提取。每个正则的第一个捕获组保存为对应变量。

```json
{
  "steps": [
    {
      "request":{"url":"@pageUrl"},
      "regexCaptures":{"id":"data-danmaku-id=\"([^\"]+)\""}
    },
    {"request":{"url":"/danmaku/@id.json"}}
  ],
  "listPath":"$.data[*]",
  "contentPath":"$.content",
  "timePath":"$.time"
}
```

## DPlayer 和 Bilibili XML

`format: "dplayer"` 的默认列表为 `$.data[*]`，单条为 `[秒数, 模式, RGB颜色, 用户, 文字]`。默认模式 `0`/`1`/`2` 分别对应滚动/顶部/底部。可以覆盖列表路径、字段路径和 `modeMap`。

```json
{"format":"dplayer","steps":[{"request":{"url":"/v3/","query":{"id":"@episodeNumber"}}}]}
```

`format: "bilibiliXml"` 解析 `<i><d p="时间,模式,字号,颜色,...">文字</d></i>`，模式和颜色从 `p` 属性读取。XML 最后一步不支持 JSONPath 选择、业务状态检查或 JSON 变量提取；之前的 JSON/HTML 预请求仍可使用。

```json
{"format":"bilibiliXml","steps":[{"request":{"url":"/danmaku/@episodeNumber.xml"}}]}
```

编辑器提供以上三种格式的示例。未配置的网站需根据实际接口修改示例，并使用「测试弹幕」验证。导出包含网站弹幕配置的规则时，API 版本至少为 10。
