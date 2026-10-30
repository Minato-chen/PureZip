#!/bin/bash
set -e

echo "🚀 [PureZip] 正在将应用安装并注册到 macOS 系统..."

APP_SRC="dist/PureZip.app"
DEST_APP="/Applications/PureZip.app"
BUNDLE_ID="com.minato.purezip"
FINDER_SYNC_ID="com.minato.purezip.FinderSync"

if [ ! -d "$APP_SRC" ]; then
    echo "❌ 找不到 $APP_SRC，请先执行打包脚本！"
    exit 1
fi

# 1. 退出正在运行的旧版本 PureZip
echo "1️⃣ 正在关闭正在运行的 PureZip 进程..."
killall PureZipApp 2>/dev/null || true

# 2. 拷贝到 /Applications
echo "2️⃣ 正在同步到 /Applications/PureZip.app ..."
rm -rf "$DEST_APP"
cp -R "$APP_SRC" "$DEST_APP"

# 3. 移除 Quarantine 隔离属性
echo "3️⃣ 移除 macOS 隔离属性 (quarantine)..."
xattr -cr "$DEST_APP"

# 4. 注册 LaunchServices (打开方式 / 默认应用关联)
echo "4️⃣ 注册 LaunchServices 文件类型关联 (打开方式)..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -f "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$DEST_APP"
    echo "   ✅ LaunchServices 注册成功 (zip, 7z, rar, tar.gz 等格式已识别为 PureZip)"
fi

# 5. 注册并启用 FinderSync 插件 (右键菜单)
echo "5️⃣ 注册并激活 Finder 扩展 (FinderSync 右键菜单)..."
pluginkit -a "$DEST_APP/Contents/PlugIns/PureZipFinderSync.appex" 2>/dev/null || true
pluginkit -e use -i "$FINDER_SYNC_ID" 2>/dev/null || true

# 6. 重启 Finder 刷新右键菜单
echo "6️⃣ 重启 Finder 刷新插件缓存..."
killall Finder 2>/dev/null || true

echo ""
echo "🎉 安装与系统注册完成！"
echo "👉 现在你可以："
echo "   1. 在 Finder 中任选一个文件或文件夹，右键查看【PureZip】压缩/解压菜单。"
echo "   2. 在任意 .zip / .7z / .rar 文件上右键 ->【打开方式】，查看【PureZip】。"
echo "   3. 点击 /Applications/PureZip.app 即可正常启动。"
