# 国科大在线 · 鸿蒙原生客户端

用 ArkTS / ArkUI 写的「国科大在线」非官方客户端。登录一次，课程、作业、资料、通知都在一个应用里。

> **非官方项目。** 本项目由个人开发，与中国科学院大学、超星（学习通）均无隶属或合作关系，也未获得校名、校徽的使用授权。应用展示的所有内容都来自学校自己的服务，本项目不提供、也不经过任何自建服务器。

学校目前没有鸿蒙原生客户端，鸿蒙设备上访问这些服务通常得借助卓易通一类的安卓兼容层，用起来繁琐。**这个项目就是填补这个空档的过渡方案——学校一旦推出官方鸿蒙版本，它就没有继续存在的必要，本项目希望并支持学校做这件事。** 完整立场见 [DISCLAIMER.md](DISCLAIMER.md)。

## 功能

| 模块 | 内容 |
|---|---|
| 登录 | 内嵌网页登录（SEP / 慕课），登录后的 Cookie 经系统 Asset Store 加密后落盘 |
| 课程 | 课程列表、学期筛选、搜索、课程详情与章节 |
| 作业 | 作业列表与详情、答案草稿、附件（拍照 / 录音 / 选文件）上传与回执 |
| 资料 | 课程资料浏览、下载与系统分享 |
| 通知 | 通知列表与详情、通知内网页深链 |
| 我的 | 个人页、设置、课程备注、置顶与已读状态、作业提醒 |

## 环境要求

| 项 | 版本 |
|---|---|
| DevEco Studio | 26.0.0 或更新 |
| HarmonyOS SDK | API 26（`targetSdkVersion` 26.0.0，`compatibleSdkVersion` 6.1.1(24)） |
| 运行时 | HarmonyOS |
| 设备类型 | phone |

工程里**没有** `hvigorw` wrapper，构建要用 DevEco Studio 安装目录里自带的那份。

## 构建

```bash
export DEVECO_SDK_HOME="<DevEco Studio 安装目录>/sdk"
HV="<DevEco Studio 安装目录>/tools/hvigor/bin/hvigorw.bat"

# debug HAP
"$HV" --mode module -p product=default -p buildMode=debug assembleHap --no-daemon

# release HAP
"$HV" --mode module -p product=default -p buildMode=release assembleHap --no-daemon
```

产物在 `entry/build/default/outputs/default/`。

### 签名

`build-profile.json5` 里的 `signingConfigs` 是空的，构建出来的是**未签名** HAP。
要装到设备上得自己配签名：在 DevEco Studio 里打开 `File → Project Structure → Signing Configs`，
勾选自动签名（需要华为开发者账号），它会往 `build-profile.json5` 写入本机的证书路径和口令。
**不要把这段提交回仓库**——里面是本机绝对路径，换台机器也用不了。

模拟器和已注册的调试设备接受未签名 HAP：

```bash
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 测试

单元测试用 Hypium：

```bash
"$HV" test -p module=entry --no-daemon
```

`entry/src/test/` 下另有几个 `.node.cjs`，是不依赖设备的解析器测试，直接用 Node 跑
（第一个参数传一个 TypeScript 包，它需要 `typescript` 来转译 `.ets`）：

```bash
node entry/src/test/work-parser.node.cjs <typescript>/lib/typescript.js
```

> 这几个 `.cjs` 测试的输入是真实页面样本，样本目录（`verification/`、`entry/build/verification/`）
> **不在仓库里**——里面有真实课程名、姓名和学号。克隆下来直接跑会因为找不到样本而失败，
> 它们只在持有样本的机器上有意义。

## 项目结构

```
AppScope/                应用级配置：bundleName、版本号、图标、应用名
entry/
  src/main/ets/
    api/                 接口调用与 HTML / JSON 解析（课程、作业、资料、通知）
    auth/                会话与凭证：SessionStore / SessionManager / CookieUtil
    data/                数据模型与本地 UI 状态
    ui/                  各页面视图
    pages/Index.ets      入口页
    entryability/        UIAbility 与备份扩展
  src/test/              单元测试（Hypium + Node 解析器测试）
  src/ohosTest/          设备侧集成测试
tools/                   开发辅助脚本：模拟器布局探针、图标生成
```

## 权限

| 权限 | 用途 | 不授权会怎样 |
|---|---|---|
| `ohos.permission.INTERNET` | 登录、读取课程 / 作业 / 资料 / 通知 | 应用无法使用 |
| `ohos.permission.CAMERA` | 只在主动拍照作为作业附件时调用 | 拍照附件的相关功能不可用 |
| `ohos.permission.MICROPHONE` | 只在主动录音作为作业附件时调用 | 录音附件的相关功能不可用 |

应用未接入广告，也没有接入任何独立的用户行为分析服务。

## 数据与隐私

登录凭证（Cookie）保存在系统 Asset Store；课程备注、置顶与已读状态、提醒开关保存在本机；
应用不向开发者自建服务器发送任何数据。完整的说明见 [PRIVACY.md](PRIVACY.md)。

## 已知限制

- 只支持手机（`deviceTypes` 为 `phone`）。
- 只在 DevEco Studio 自带模拟器（Pura 70 Ultra，API 26）上验证过。真机上的相机、录音、系统分享面板没有验证。
- release 构建有约 100 条 ArkTS 告警，没有 error。其中 `wantAgent` 系列 API 已废弃，有待迁移到 `@ohos.app.ability.wantAgent`。
- 上一条提到的 `.node.cjs` 测试依赖本机样本。

## 免责声明

**本项目是非官方客户端，与中国科学院大学、超星（学习通）无任何隶属或合作关系，也未取得校名、校徽的使用授权，仅供学习与交流。**

使用前请读 [DISCLAIMER.md](DISCLAIMER.md)：里面写清了账号被封禁或锁定的风险、学术规范的要求、第三方数据来源、责任限制的范围，以及**权利人有异议时的配合处理方式**。

## 许可

未附开源许可证，保留所有权利。
