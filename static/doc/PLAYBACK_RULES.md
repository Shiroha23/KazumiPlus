# 通用播放解析规则（API 11）

`playbackConfig` 是可选的播放解析配置。客户端不包含站点域名或专用接口；各站通过规则描述如何从播放页或 HTTP 接口获取媒体地址。留空或设置 `enabled: false`，继续使用原有 WebView 嗅探。

在「规则编辑器 → 播放」编辑 JSON，可用播放页地址测试请求和字段映射。测试成功仅表示获得了媒体地址，仍需实际播放验证。配置随导入、导出、分享和规则编辑保存；含该字段的规则导出时 API 至少为 11。

## 示例：分离的视频与音频

以下是虚构站点的配置结构，实际使用时修改接口和字段路径。

```json
{
  "enabled": true,
  "pagePattern": "/watch/(?<mediaId>\\d+)",
  "steps": [
    {
      "request": {
        "url": "@origin/api/media/@mediaId",
        "headers": {"Accept": "application/json"}
      },
      "successPath": "$.code",
      "successValue": 0
    }
  ],
  "video": {
    "listPath": "$.data.video[*]",
    "urlPath": "$.url",
    "qualityPath": "$.height",
    "bandwidthPath": "$.bandwidth",
    "codecPath": "$.codec",
    "preferredCodecs": ["avc1", "hev1"],
    "maxQuality": 1080,
    "headers": {"Referer": "@pageUrl"}
  },
  "audio": {
    "listPath": "$.data.audio[*]",
    "urlPath": "$.url",
    "bandwidthPath": "$.bandwidth",
    "headers": {"Referer": "@pageUrl"}
  }
}
```

对应响应：

```json
{"code":0,"data":{"video":[{"height":1080,"bandwidth":2000000,"codec":"avc1.640028","url":"https://video.example/media.mp4"}],"audio":[{"bandwidth":128000,"url":"https://audio.example/media.m4a"}]}}
```

`video` 必填，`audio` 可选。不配置 `audio` 时，`video` 应指向音画合一的 MP4、HLS 或其他播放器支持的媒体。配置 `audio` 后，如果音频字段缺失、列表为空或音轨加载失败，会报告错误，不会自动转为无声播放。

## 流选择

- `listPath` 留空时从最终 JSON 响应根节点读取 `urlPath`；填写时从候选列表中选择一条。
- `urlPath` 必填，支持相对地址或 HTTP/HTTPS 地址；不接受本地文件、脚本协议或包含用户名密码的地址。
- `preferredCodecs` 按顺序匹配编码前缀，不区分大小写。先比较编码偏好，再按 `qualityPath` 数值降序、`bandwidthPath` 数值降序选择。没有偏好匹配时仍可选择其他编码。
- `maxQuality` 是 `qualityPath` 所映射数值的上限，单位由规则决定，例如分辨率高度或接口的清晰度编号。仅选择接口实际返回的候选流；不会获得账号无权访问的清晰度。
- 不设置排序路径时保留接口顺序；数值路径缺失或无效按 0 处理。媒体格式 `format` 支持 `auto`（默认）或 `hls`。

## 请求、变量与登录

`steps` 与[网站弹幕规则](DANMAKU_RULES.md)使用相同的多步请求机制，支持 GET/POST、JSON/表单、JSONPath captures、HTML regexCaptures、业务状态检查及按集选择列表。最后一个请求应返回 JSON，媒体映射始终从最后响应根节点读取。

初始变量有 `@pageUrl`、`@origin`、`@episodeNumber`、`@episodeIndex`。`pagePattern` 的命名捕获、`queryVariables`（变量名到播放页查询参数名的映射）、`defaults` 和前序步骤的 captures 可为后续请求和媒体请求头提供变量。捕获值是数据，不执行任意 JavaScript，不计算接口私有签名。

请求按目标网站复用已保存的登录状态和 User-Agent，同站新规则无需单独登记。每个 API、视频和音频地址分别按目标域名读取 Cookie；不会把视频 Cookie 自动复制到另一个音频域名。`video.headers` 和 `audio.headers` 分别配置媒体请求头，支持变量。规则的 User-Agent 和 Referer 作为公共默认值，媒体流配置可以覆盖它们。请不要把账号凭据写入公开分享的规则。

原生播放器先暂停加载视频，再用音频自己的请求头附加外部音轨，确认音轨存在后才按自动播放设置启动。两条流使用同一个播放器时钟，暂停、倍速、跳转和断点续播共同生效，不需预先下载或转码。

## 当前边界

适用于无需 DRM 的独立 HTTP 音视频媒体，包含接口已经给出可独立打开地址的 DASH 资源；不自动从任意网络请求推断哪两条流是一对，也不解析 MPD 中分散的初始化片段和分片模板。使用这类资源时，规则仍需返回播放器可打开的媒体地址或完整清单。

本次支持内置播放器在线播放。分离流下载合并、外部播放器传递音轨和 DLNA 投屏尚未实现，客户端会明确提示，不会只交付一条流。音画合一的媒体继续使用已有下载和外部播放流程。Windows 原生集成测试可用 `KAZUMI_NATIVE_PLAYBACK_TEST=1 flutter test test/separate_media_native_test.dart` 运行，需要本地已有构建产物中的 `libmpv-2.dll`。
