# 上传到 GitHub 并发布 V1 版本 —— 操作步骤

沙箱环境访问不了 GitHub（网络策略封锁），所以这一步需要你在自己电脑上操作。
大概 5 分钟，三条命令 + 一次网页操作。

---

## 准备

从交付目录下载这两个文件到同一个文件夹：

| 文件 | 用途 |
|---|---|
| `记账App-v1.2.0-含git历史.bundle` | 完整仓库（带提交历史），635KB |
| `记账-v1.2.0.apk` | 要发布的 APK，22MB |
| `发布Release.sh` | 自动发 Release 的脚本 |

**生成 GitHub Token**（如果没有）：

1. 打开 https://github.com/settings/tokens
2. 点 `Generate new token` → `Generate new token (classic)`
3. Note 随便填（比如 `ledger-release`），Expiration 选 90 天或不过期
4. 勾选权限：**`repo`**（必须，全选子项）、`workflow`（可选）
5. 生成后**立刻复制保存** —— 页面关掉就再也看不到了

---

## 第一步：建空仓库

打开 https://github.com/new

| 字段 | 填什么 |
|---|---|
| Repository name | `record-ledger` |
| Description | 纯本地离线安卓记账 App（可选） |
| 可见性 | **Private**（你之前选的） |
| Initialize this repository with | **三个都不要勾！** |

> **为什么要空仓库？** 如果勾了 Add a README，GitHub 会先建一个提交，
> 你推送时会因为历史不相关被拒绝（`rejected - fetch first`）。
> 真遇到了也不难解：`git pull --allow-unrelated-histories` 然后处理冲突。

---

## 第二步：推送代码

在下载的文件夹里打开终端（Windows 用 Git Bash）：

```bash
# 1. 从 bundle 还原仓库
git clone 记账App-v1.2.0-含git历史.bundle record-ledger
cd record-ledger

# 2. 指向你的仓库
git remote set-url origin https://github.com/你的用户名/record-ledger.git

# 3. 推送
git push -u origin master
```

**推送时会弹窗要账号密码**：
- 用户名 → 你的 GitHub 用户名
- 密码 → **粘贴刚才生成的 Token**（不是登录密码！）

> 不想每次都输？用这条命令把 token 存起来：
> ```bash
> git remote set-url origin https://你的用户名:你的Token@github.com/你的用户名/record-ledger.git
> ```
> 但注意：这样 token 会明文存在 `.git/config` 里，个人电脑上可以，公共机器别这么干。

推送成功后，刷新 GitHub 页面就能看到 48 个文件了。

---

## 第三步：发布 V1 Release

把 `记账-v1.2.0.apk` 和 `发布Release.sh` 复制到 `record-ledger` 目录里，然后：

```bash
# 1. 改脚本里的用户名（用编辑器打开，改第一行）
#    USERNAME="你的GitHub用户名"

# 2. 设置 token
export GITHUB_TOKEN=你的Token

# 3. 运行
bash 发布Release.sh
```

脚本会自动：打 `v1.0.0` tag → 创建 Release（带完整的发布说明）→ 上传 APK。

跑完会打印 Release 链接，直接点开就能看到。

---

## 不想用脚本？纯网页操作也行

1. 代码推送完成后，打开仓库页面
2. 右侧栏点 **Releases** → **Create a new release**
3. **Choose a tag** 输入 `v1.0.0` → 点 `Create new tag on publish`
4. Release title 填 `记账 v1.0.0`
5. 描述框里粘贴发布说明（可以复制脚本里 `RELEASE_BODY` 那段）
6. 页面下方 **Attach binaries** 拖入 `记账-v1.2.0.apk`
7. 点 **Publish release**

---

## 校验一下成果

推送完成后，本机跑一遍确认没问题：

```bash
git log --oneline                    # 应看到 "记账 App v1.2.0"
git ls-files | wc -l                 # 应为 48
git ls-files | grep -E "\.apk|\.jks" # 应为空 —— 确认构建产物和密钥没入库
```

---

## 常见问题

**推送被拒绝 `rejected - fetch first`**
建仓库时勾了 README。解决：
```bash
git pull origin master --allow-unrelated-histories
git push -u origin master
```

**`remote: Support for password authentication was removed`**
你把登录密码当成了 token。去 https://github.com/settings/tokens 生成一个。

**中文文件名乱码**
```bash
git config --global core.quotepath false
```

**APK 太大推不上去（>100MB）**
本包的 APK 是 22MB，没问题。GitHub 单文件硬上限 100MB。

**想改成分架构的小包**
```bash
flutter build apk --release --split-per-abi --no-tree-shake-icons
# 产出三个包，arm64 的那个约 7MB，绝大多数手机装这个就行
```

---

## 关于签名文件的提醒

仓库里的 `.gitignore` 已经挡掉了 `*.jks` 和 `*.keystore`。

当前 APK 是**调试签名**，自用完全没问题。但如果以后要做正式签名，
**签名文件绝对不能提交到任何仓库** —— 泄露意味着别人可以用你的身份发布应用更新。
到时候记得把 keystore 放在仓库外的安全位置。

---

## 后续发版流程

改完代码后：

```bash
flutter test                                    # 先跑测试
# 改 pubspec.yaml 里的 version: 1.2.0+6 → 1.3.0+7
flutter build apk --release --no-tree-shake-icons
cp build/app/outputs/flutter-apk/app-release.apk ../记账-v1.3.0.apk

git add -A
git commit -m "v1.3.0: 改了什么"
git push
```

然后改 `发布Release.sh` 里的 `TAG` 和 `APK_FILE`，重新跑一遍即可。
