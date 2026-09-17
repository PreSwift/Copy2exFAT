# 拷到 exFAT

macOS 小工具，用来把文件或文件夹安全拷贝到 exFAT 磁盘。拷贝完成后会执行 `sync` 并刷新磁盘缓存，降低直接弹出导致文件系统损坏的风险。

[下载 v1.0.0](https://github.com/PreSwift/Copy2exFAT/releases/tag/v1.0.0) · 需要 macOS 14 或更高版本

## 功能

- 选择或拖入文件、文件夹，拷贝到 exFAT 磁盘
- 识别目标卷格式与可用空间
- 显示拷贝进度，可中途取消
- 取消时删除未完成的临时文件（`.partial`）
- 拷贝完成后一键弹出移动磁盘

## 安装

1. 从 [Releases](https://github.com/PreSwift/Copy2exFAT/releases) 下载 `Copy2exFAT-1.0.0-macos.zip`
2. 解压后将 `Copy2exFAT.app` 拖到「应用程序」
3. 若系统提示无法打开，在 Finder 中右键选择「打开」

安装包为通用二进制，同时支持 Apple Silicon 和 Intel。

也可以双击仓库里的 `copy2exfat.command`：若本地还没有应用，会先执行 `build.sh` 再启动。

## 使用

1. 选择或拖入要拷贝的文件 / 文件夹
2. 选择 exFAT 磁盘上的目标位置
3. 点击「拷贝并同步」
4. 完成后点击「弹出磁盘」

拷贝过程中会先写入 `文件名.partial`，成功后再改成正式文件名。

## 从源码构建

需要 Xcode Command Line Tools 或完整 Xcode。

```bash
./build.sh
open Copy2exFAT.app
```

## 许可

[MIT](LICENSE)
