# 论文库 Paper Library

一个管理已读论文的跨平台应用，同一套代码运行在 **Windows / macOS / Linux 桌面** 和 **安卓手机、平板** 上。

## 功能

| 功能 | 说明 |
| --- | --- |
| 导入 PDF | 支持一次选多篇。按文件内容哈希去重，重复导入会被跳过 |
| 元数据识别 | 从 PDF 前两页提取标题、摘要、关键词、DOI、年份；检测到 arXiv 编号或 DOI 时联网（arXiv / Crossref）补全作者、期刊、年份 |
| 自动学科分类 | 根据标题、摘要、关键词与内置 13 个学科门类、约 40 个子学科的中英文关键词打分，自动归类；arXiv 论文直接用 arXiv 学科。详情页显示前 3 个候选，可一键改 |
| 分类会学习 | 手动改过分类的论文会被记住，论文关键词会加入该分类的"学习词表"，之后同类论文分得更准。分类和关键词都可以自己增删改 |
| 选中文字批注 | 在阅读器里选中一段文字，右键菜单或右下角按钮"添加批注"，可写批注、选高亮颜色。点击高亮可再次编辑；批注列表可跳转到对应页 |
| 手写墨迹笔记 | 阅读器右上角笔形按钮进入手写模式：钢笔（支持压感）、荧光笔、橡皮擦、5 种颜色、3 种粗细、撤销/重做。默认"仅触控笔"：手指照常翻页缩放，只有触控笔写字（防手掌误触）。桌面端可用鼠标书写 |
| WebDAV 同步 | 论文信息、分类、批注、手写笔记、PDF 原文件都会同步。支持坚果云、Nextcloud、群晖/威联通 NAS 等任何 WebDAV 服务 |
| 隐私 | WebDAV 密码存放在系统安全存储（安卓 Keystore / Windows 凭据管理器 / macOS 钥匙串 / Linux 钥匙环）。可选**端到端加密**：设置同步密码后，所有数据在本机用 AES-256-GCM 加密再上传，云端只有密文，文件名也经过 HMAC 处理 |
| 其他 | 搜索（标题/作者/摘要/关键词/笔记）、阅读状态（未读/在读/已读）、五星评分、个人笔记、排序 |

## 同步设置

在每台设备的 **设置** 里填同一个 WebDAV 账号：

- **坚果云**：地址 `https://dav.jianguoyun.com/dav/`，账号是坚果云登录邮箱，密码要用 *账户信息 → 安全选项 → 第三方应用管理 → 添加应用* 生成的**应用密码**（不是登录密码）。
- **Nextcloud**：`https://你的域名/remote.php/dav/files/用户名/`
- **群晖 NAS**：在套件中心安装 WebDAV Server，地址 `https://NAS地址:5006/`

开启"自动同步"后，启动时、修改后约 20 秒、以及每 10 分钟各同步一次，也可以点首页右上角的云朵图标手动同步。

数据在 WebDAV 上的结构（可以直接用坚果云网页查看/备份）：

```
PaperLibrary/
  records/paper/<id>.json        每篇论文一个文件
  records/category/<id>.json     修改过的分类
  records/annotation/<id>.json   每条批注
  records/ink/<论文id>_p<页码>.json  每页的手写笔迹
  files/<sha256>.pdf             PDF 原文件
```

启用端到端加密后，数据改存到 `PaperLibrary/e2e/`，所有文件都是密文；`crypto.json` 只包含盐值和用于校验密码的密文，不含密码或密钥。
密钥由同步密码经 PBKDF2-SHA256（20 万次迭代）派生，同步密码本身从不上传，派生出的密钥只保存在每台设备的系统安全存储里。**忘记同步密码就无法解密云端数据**（本机数据不受影响）。

冲突处理：同一条记录在两台设备上都改过时，以最后修改的为准（按记录粒度，例如两台设备分别给同一篇论文的不同页写笔记，互不影响）。

## 安装

### 下载构建好的安装包

代码推到 GitHub 后，`.github/workflows/build.yml` 会自动构建安卓 APK、Windows、macOS、Linux 版本，在仓库的 **Actions → 最新一次运行 → Artifacts** 下载。打 `v1.0.0` 这样的标签会自动发布到 Releases。

安卓平板一般下载 `app-arm64-v8a-release.apk`。

### 自己编译

需要 [Flutter](https://docs.flutter.dev/get-started/install) 3.47 以上。

```bash
flutter pub get
flutter test                 # 运行单元测试
flutter run -d windows       # 或 macos / linux / 连接的安卓设备
flutter build apk --release  # 安卓安装包
flutter build windows --release
```

## 代码结构

```
lib/
  main.dart                     启动、初始化 PDF 引擎和数据库
  models.dart                   数据模型：论文、分类、批注、墨迹
  classifier/taxonomy.dart      内置学科体系和关键词
  classifier/classifier.dart    关键词加权打分分类器 + 学习
  import/text_metadata.dart     从 PDF 文本提取标题/摘要/关键词
  import/online_lookup.dart     arXiv / Crossref 联网补全
  data/database.dart            SQLite 本地存储
  data/library.dart             数据层：导入、分类、保存
  sync/webdav.dart              WebDAV 客户端
  sync/sync_engine.dart         双向增量同步
  sync/sync_service.dart        自动同步调度、设置
  ui/                           界面：首页、详情、阅读器、墨迹层、设置
test/core_test.dart             分类、元数据提取、同步的单元测试
```

## 已知限制 / 后续可做

- 扫描版 PDF（图片，没有文字层）无法自动提取摘要，需要手动填写；可以后续接 OCR。
- 分类是离线关键词匹配，对跨学科论文可能需要手动调整；可选接入大模型 API 做更准确的分类。
- 手写笔记保存在应用内，暂不支持导出为带笔迹的 PDF。
- 本机数据库和 PDF 本身没有额外加密，依赖系统磁盘加密（安卓默认开启；Windows BitLocker、macOS FileVault）。
