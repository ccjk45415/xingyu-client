# 原生媒体依赖

正文视频使用 media_kit 1.2.6、media_kit_video 2.0.1（MIT），不使用 WebView。Flutter/Dart 包许可证随安装包的 NOTICES.Z 提供。

原生库采用上游未修改的发行文件，动态链接；不属于星屿客户端的 MIT 授权代码。

- Windows: media_kit_libs_windows_video 1.0.11；libmpv 2023-09-24；构建源码与对应发行文件：https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24 ，https://github.com/media-kit/libmpv-win32-video-build 。ANGLE：https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1 。
- Android: media_kit_libs_android_video 1.3.8；原生构建 v1.1.7；构建源码与发行文件：https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7 ，https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.7 。
- mpv 源码及许可证：https://github.com/mpv-player/mpv ，https://github.com/mpv-player/mpv/blob/master/Copyright 。
- FFmpeg 源码及许可证：https://ffmpeg.org/download.html ，https://ffmpeg.org/legal.html 。

原生组件的许可、版权和对应源码以这些上游发行版本为准；客户端的 MIT 许可证不替代其许可证。后续对外发布需保留本文件、上游版权信息与对应源码获取位置。

AVIF 图片解码：flutter_avif / flutter_avif_platform_interface 3.1.0（MIT），包含 libavif 原生解码及其依赖。源码、构建及许可证：https://github.com/yekeskin/flutter_avif ，https://github.com/AOMediaCodec/libavif 。原生库未修改，随包保留其上游许可证与 Flutter NOTICES。

macOS Apple Silicon：media_kit_libs_macos_video 使用上游未修改的 libmpv Darwin xcframework v0.6.0；构建源码与对应发行文件：https://github.com/media-kit/libmpv-darwin-build ，https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0 。macOS 包通过 CocoaPods 解析并校验上游下载校验和，动态链接媒体框架。
