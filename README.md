# Unraid Mobile

一个从零开始、完全通过 **GitHub 云端 Actions** 打包的 Unraid NAS 手机管理 App。
本地不需要安装 Android Studio / Flutter SDK / Java，只需要一个 GitHub 账号。

功能：
- 📊 仪表盘：主机名、系统版本、CPU / 内存占用环形图、CPU 温度与频率、
  阵列状态与启停、存储总览、**实时网络上传/下载速率**、磁盘温度 / 运行状态 / SMART
  （前台 **每 2 秒自动刷新**，含 Docker / 虚拟机 / 文件页）
- ⚡ **整机重启/关机**：配置 root 密码后，仪表盘出现系统控制卡片（倒计时确认防误触）
- 💾 **SMART 完整属性表**：磁盘详情页展示 smartctl 明细（重映射扇区、通电时长等）
- 🌐 **多地址自动选择**：可填写多个地址（局域网 HTTP、外网 HTTPS 都行），
  打开 App 时自动探测并选择当前可达的地址，无需手动切换
- 🐳 Docker 容器管理：启动 / 停止 / 暂停 / 恢复（每 2 秒刷新状态）
- 🖥️ 虚拟机管理：启动 / 停止 / 暂停 / 恢复 / 重启（每 2 秒刷新状态）
- 📁 文件管理（WebDAV / OpenList）：浏览、新建文件夹、上传、下载并打开、
  重命名、删除；地址自动补全 `/dav`；**传输任务中心**查看上传/下载实时进度
- 🎨 主题：深色 / 浅色 / 跟随系统 × 橙 / 青绿 / 蓝 强调色，设置页即时切换
- 🔄 应用内更新提醒：自动检测 GitHub 上的新版本，一键跳转下载
- 📱 手机上可以**原地升级安装**，不需要先卸载旧版（见下方原理说明）

---

## 一、准备工作：开启 Unraid 的 GraphQL API

1. 打开 Unraid WebGUI，进入 **Settings → Management Access → Developer Options**，
   打开 **GraphQL Sandbox** 开关。
2. 进入 **Settings → Management Access → API Keys**，创建一个新的 API Key，
   角色选择 `Admin`（或者只勾选 Docker / Info / Array 相关权限），保存后复制这个 Key，
   稍后要填到手机 App 里。
3. 记下 NAS 的地址：局域网 IP（如 `192.168.1.10`）；如果通过 Cloudflare / 反代
   做了外网 HTTPS 访问，再记下外网域名（如 `https://nas.example.com`）。

> 如果你在 Settings 里没找到上面这两个入口，把 Settings 页面截图发我，我帮你定位（不同 Unraid 小版本菜单位置可能略有出入）。

---

## 二、把这个项目推送到你的 GitHub 仓库

在电脑上（不需要装 Flutter，只需要 git）：

```bash
cd unraid-mobile
git init
git add .
git commit -m "init: unraid mobile app"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<你的仓库名>.git
git push -u origin main
```

> 如果你连本地 git 都不想用，也可以直接在 GitHub 网页里新建仓库，然后把这个文件夹里的所有文件手动上传（Add file → Upload files）。

---

## 三、生成签名证书（只需要做一次，非常重要）

这一步是实现"手机上直接升级安装、不用先卸载"的关键。原理很简单：
**Android 只有在新旧安装包使用同一份签名证书、且新包的版本号更高时，才允许"原地覆盖安装"。**

操作步骤：

1. 打开你仓库的 **Actions** 标签页
2. 左侧选择 **Generate Signing Keystore (只需运行一次)**
3. 点击右侧 **Run workflow** 按钮 → 再点一次绿色的 **Run workflow** 确认
4. 等待运行完成（大约 30 秒），点进这次运行记录，在最下方 **Artifacts** 里下载
   `unraid-mobile-keystore` 压缩包
5. 解压后你会看到三个文件：
   - `keystore-info.txt` —— 打开它，里面写清楚了接下来要填的 4 个密钥
   - `release_base64.txt` —— 待会要复制这里面的内容
   - `release.jks` —— 证书本体，**请额外备份一份到网盘或电脑里**，遗失后无法恢复
6. 回到仓库 **Settings → Secrets and variables → Actions → New repository secret**，
   依次添加 4 个 Secret（名字必须完全一致）：

   | Secret 名称 | 值 |
   |---|---|
   | `KEYSTORE_BASE64` | 打开 `release_base64.txt`，把整行内容粘贴进去 |
   | `KEYSTORE_PASSWORD` | 抄 `keystore-info.txt` 里的密码 |
   | `KEY_ALIAS` | `unraidmobile` |
   | `KEY_PASSWORD` | 抄 `keystore-info.txt` 里的密码（和 storePassword 相同）|

完成后这一步就再也不用做了，以后每次打包都会自动复用这份证书。

---

## 四、触发云端打包

添加完 4 个 Secret 后，到仓库 **Actions → Build & Release APK → Run workflow**
手动触发一次（打包大约 3-6 分钟，会先跑一遍 `flutter analyze` 静态检查）。
完成后，仓库主页右侧 **Releases** 里会自动出现一个新版本，里面有一个 `.apk` 文件。

> 设计为手动触发：想打包时才打，避免"每改一个文件就自动构建一次"。
> 每次触发都会生成一个带新版本号的 Release（`v1.0.<运行号>`），历史版本会保留。

## 五、手机上安装

1. 手机浏览器打开你仓库的 Releases 页面（地址形如
   `https://github.com/<用户名>/<仓库名>/releases/latest`）
2. 点击 `.apk` 文件下载
3. 第一次安装：系统会提示"未知来源"，去 设置 → 允许该浏览器安装应用，然后正常安装即可
4. **以后每次更新**：重复上面第 1-2 步，下载新的 apk 点击安装，
   手机会直接提示"更新"而不是"卸载重装"——因为签名证书和版本号机制已经处理好了

### 版本号与覆盖升级原理

- `versionName`（显示用）= `1.0.<Actions 运行号>`，和 Release 的 tag 一致；
- `versionCode`（安装器判断用）= `自 Unix 纪元的天数 × 10000 + 运行号`。
  运行号保证每次构建严格递增；天数偏移防止 workflow 文件被改名/重建后
  运行号从 1 重来、导致新版本号反而小于旧版本号。
- 条件：**签名证书永不更换**（就是第三步生成的 keystore）+ versionCode 严格递增。
  两个条件都满足，覆盖安装时应用数据（登录信息等）会保留。

---

## 六、使用说明

### 连接配置（全部在设置页，改动实时生效）

- **服务器连接**：设置页可编辑地址列表（添加/移除备用地址）和 API Key，
  点"保存并应用"会当场探测并提示当前使用的地址；App 每次启动也会自动探测。
  地址可以不写 `http://` / `https://` 前缀（自动补全），但需要区分协议时请写全
  （局域网一般 `http://192.168.1.10`，外网一般 `https://...`）。
- **WebDAV 文件管理**：地址只填 OpenList 主页地址即可（如 `192.168.1.10:5244`），
  `/dav` 自动补全；没写协议时自动补 `http://`。
- 系统地址和 WebDAV 地址相互独立，可以指向不同的主机/端口。

### 主题

设置页 → 主题：深色 / 浅色 / 跟随系统，配合橙 / 青绿 / 蓝 三种强调色，
切换立即生效，无需重启。

### 文件管理

- 右上角 **+**：新建文件夹 / 上传文件（走系统文件选择器，无需存储权限）
- 右上角 **⇅**：传输任务中心，查看所有上传/下载的实时进度与历史记录
- 点击文件：下载并调用系统应用打开（图片/视频/文本/压缩包等）
- 长按条目菜单（⋮）：重命名 / 删除；文件夹点按进入，**系统返回键回到上级目录**
- 下载保存位置（设置页）：缓存目录（默认，超限自动清理）/ 文档目录（持久保存）

### 权限说明（符合高版本 Android 的分区存储）

- App 只申请 **INTERNET** 权限；
- 上传文件使用系统自带的文件选择器（SAF），App 只能看到你选中的那一个文件，
  不会申请存储读写权限，也不触碰其他目录；
- 下载的文件保存在应用私有目录（缓存/文档），完全隔离，卸载即清空。

### 系统控制（整机重启/关机、SMART 明细）

GraphQL API 不提供整机重启/关机，也不暴露完整 SMART 属性表。
App 通过**设置页 → 系统控制**配置的 root 账号密码，走 webGUI 会话调用旧版端点实现：

- **重启 / 关机**：仪表盘出现"系统控制"卡片，点击后有 10 秒倒计时确认（可取消）
- **SMART 明细**：磁盘详情页展示 smartctl 完整属性（值/最差/阈值/原始值）
- 前提：Unraid 里**已设置 root 密码**（webGUI 能登录）；未配置时这些功能不显示
- 密码保存在手机本地，仅用于建立 webGUI 会话

### 检查更新

`lib/services/update_service.dart` 里有一行：

```dart
static const String githubRepo = 'YOUR_GITHUB_USERNAME/unraid-mobile';
```

把它改成你自己的 `用户名/仓库名`，重新打包后，App 首页顶部会自动检测并提示
"发现新版本 vX，点击下载安装"。

## 项目结构

```
unraid-mobile/
├── .github/workflows/
│   ├── generate-keystore.yml   # 一次性：生成签名证书
│   └── build-apk.yml           # 手动触发：静态检查 + 云端编译 + 发布 Release
├── android_overrides/
│   └── app_build.gradle.kts    # CI 会用它覆盖 flutter create 生成的默认签名配置
├── lib/
│   ├── main.dart
│   ├── theme/app_theme.dart    # 主题预设（深浅色 × 强调色）+ 动态配色
│   ├── models/                 # SystemInfo / Metrics / Array / NetworkRate / Docker / VM
│   ├── services/
│   │   ├── unraid_api.dart     # GraphQL 请求封装（已按官方最新 Schema 逐字段核对）
│   │   ├── storage_service.dart
│   │   ├── webdav_service.dart # WebDAV 客户端（/dav 自动补全、缓存清理）
│   │   ├── transfer_manager.dart # 全局传输任务中心
│   │   └── update_service.dart
│   ├── screens/                # 登录 / 主页 / 仪表盘 / Docker / VM / 文件 / 设置
│   └── widgets/                # 容器列表项 / 虚拟机列表项 / 环形图
└── pubspec.yaml
```

`android/`、`ios/` 等平台目录**故意没有提交到仓库**——它们由 `build-apk.yml`
在云端构建时通过 `flutter create` 自动生成，这样你本地完全不需要装任何 Android 环境。

## 已知限制

- **SMART 明细**：官方 API 只提供粗粒度的 SMART 健康状态；完整属性表依赖 webGUI 会话抓取，
  磁盘休眠或未设置 root 密码时获取不到。
- **实时网速**：依赖较新的 Unraid 7.x（API 的 `metrics.network` 字段）；
  旧版本会自动隐藏实时速率区域，不影响其他功能。
- **后台通知**：目前是前台每 2 秒自动刷新；后台定时推送提醒（磁盘高温、容器异常退出）
  尚未实现。

## 常见问题

**Q: push 后 Actions 报错 "缺少 KEYSTORE_BASE64 secret"**
A: 说明第三步的 4 个 Secret 还没配置完整，去 Settings → Secrets 检查名称是否完全一致（区分大小写）。

**Q: App 提示"所有地址都无法连接"**
A: 逐项检查：地址/端口是否正确；手机和 NAS 网络是否互通（外网地址需要在公网可达）；
API Key 是否有效；是否已开启 GraphQL（Settings → Management Access）。
另外注意：局域网地址用 `http://`，外网 Cloudflare 域名用 `https://`。

**Q: 手机升级时提示"应用未安装" / 要卸载重装**
A: 99% 是签名证书对不上：确认 4 个 Secret 没改过、keystore 没换过；
另外确认 `android_overrides/app_build.gradle.kts` 里的包名没被改过。

**Q: 文件管理提示连接失败**
A: 确认 OpenList 已开启 WebDAV 服务、账号密码正确、端口写对（OpenList 默认 5244）；
外网访问 OpenList 的话地址要写成外网域名。

**Q: 文件页按返回键直接退出 App？**
A: 已在根目录时返回键会退出 App（正常）；进入任意子目录后返回键会回到上级目录。
如果还有异常，把复现步骤发我。
