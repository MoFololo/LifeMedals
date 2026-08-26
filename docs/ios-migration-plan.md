# LifeMedals iOS 迁移计划

## 技术路线

使用现有 SwiftUI target 构建 macOS 与 iOS 多平台应用，而不是复制第二套客户端。两个平台共享 SwiftData schema、CloudKit 私有容器、Apple 登录、AI 服务、通知和业务 UI；仅为图片、相机、WebKit、窗口命令及紧凑布局保留平台适配代码。

## 阶段与状态

### 1. 多平台基础（已完成）

- [x] target 支持 `macosx`、`iphoneos` 和 `iphonesimulator`
- [x] 配置 iPhone/iPad device family、iOS 部署版本、相机和照片权限说明
- [x] Debug 继续使用无云端 entitlement 的本地开发模式
- [x] Release 复用 `iCloud.noorg.LifeMedals`、Sign in with Apple 和通知 entitlement
- [x] macOS 与 iOS Debug 编译验证通过

### 2. 平台 API 与首轮 UI 适配（已完成）

- [x] AppKit/UIKit 图片显示统一到共享适配层
- [x] 图片压缩改为跨平台 ImageIO 实现
- [x] WKWebView 勋章动画同时支持 `NSViewRepresentable` 与 `UIViewRepresentable`
- [x] 相机预览同时支持 AppKit 与 UIKit，并接入证据提交页
- [x] iPhone 使用紧凑顶部栏和底部主导航
- [x] 登录页、任务契约表单、证据槽位和账户面板适配小屏宽度
- [x] iOS 支持相机、PhotosPicker 与文件选择；macOS 继续支持拖放和 `⌘V`

### 3. 真机与跨设备验收（下一阶段）

- [ ] 使用付费 Apple Developer Team 激活 CloudKit 容器和签名配置
- [ ] 在 iPhone 真机验证相机权限、照片权限、拍照方向和压缩结果
- [ ] 验证本地通知授权、前台展示、截止提醒与重启恢复
- [ ] 验证 Apple 登录首次授权、取消、撤销和离线会话
- [ ] 验证 Mac/iPhone 新增、编辑、核验、EXP 与证据图片双向同步
- [ ] 验证断网编辑、恢复联网、并发修改和同步冲突
- [ ] 在 CloudKit Console 检查开发 schema，再发布到 Production

### 4. iOS 产品级打磨

- [x] 在标准 iPhone 模拟器逐页检查首页、任务、契约、详情、勋章、账户与奖励动画
- [x] 修复导航栏账户入口、启动抢焦点、Tab Bar 键盘遮挡和任务行双重横滑手势
- [x] 修复竖向 ScrollView 采用桌面理想宽度造成的整页横向溢出
- [x] 为双图证据槽、证据历史卡、账户弹窗和奖励动画增加紧凑布局
- [x] 奖励动画支持 Reduce Motion，并在 iOS 使用全屏模态避免导航容器裁切
- [ ] 用 iPhone SE 尺寸、标准 iPhone、Pro Max 和 iPad 做逐页视觉 QA
- [ ] 优化键盘避让、动态字体、VoiceOver、横竖屏策略和触控目标
- [ ] 为证据历史卡片、勋章动画和较长任务标题补充窄屏边界测试
- [ ] 添加 SwiftData 服务测试和关键 UI smoke test
- [ ] 评估是否继续支持 iPad；若支持，增加双栏/宽屏布局

### 5. TestFlight 与上架

- [ ] 制作 iOS App Icon、Launch Screen 和各设备截图
- [ ] 补齐隐私清单、隐私政策、相机/照片/iCloud/AI 数据说明
- [ ] 在 App Store Connect 创建 iOS 平台版本并配置 Sign in with Apple
- [ ] Archive/Validate，解决签名、entitlement 与隐私检查问题
- [ ] TestFlight 内测，完成崩溃、性能、网络失败和迁移回归
- [ ] 提交 App Review

## 验收标准

iOS 版本达到可内测状态时，必须能在 iPhone 上独立跑通“生成契约 → 保存 → 本地提醒 → 拍照/选图 → AI 核验 → EXP/勋章 → Library”，断网不丢本地数据；恢复联网后，同一 iCloud 账户下的 Mac 与 iPhone 数据最终一致。

## Debug 截图回归入口

Debug 构建可通过 `LIFEMEDALS_DEBUG_PAGE` 打开 `tasks`、`medals`、`atlas`、`account`、`review`、`task-detail` 或 `award` 场景。该入口仅用于模拟器截图回归，不会进入 Release 构建的正常用户流程。
