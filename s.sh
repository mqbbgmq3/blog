#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hexo 博客迁移至 Cloudflare Pages 一键脚本
# 包含 Gitalk Token Proxy 的 CF Functions 适配
# 用法: bash migrate-to-cf-pages.sh [hexo站点根目录]
# ============================================================

HEXO_ROOT="${1:-.}"
FUNCTIONS_DIR="$HEXO_ROOT/functions"
WRANGLER_CONFIG="$HEXO_ROOT/wrangler.toml"
FLATPAPER_CONFIG="$HEXO_ROOT/_config.flatpaper.yml"

echo "☁️  Hexo → Cloudflare Pages 迁移工具"
echo "   目标目录: $(cd "$HEXO_ROOT" && pwd)"
echo ""

# ------------------------------------------------------------
# 1. 检查 Hexo 站点结构
# ------------------------------------------------------------
if [[ ! -f "$HEXO_ROOT/_config.yml" ]]; then
  echo "❌ 未找到 _config.yml，请确认在 Hexo 站点根目录执行"
  exit 1
fi

# ------------------------------------------------------------
# 2. 清理 Netlify 残留
# ------------------------------------------------------------
echo "🧹 清理 Netlify 专属文件..."
rm -rf "$HEXO_ROOT/netlify"
rm -f "$HEXO_ROOT/netlify.toml"
echo "   ✅ 已移除 netlify/ 目录和 netlify.toml"

# ------------------------------------------------------------
# 3. 创建 Cloudflare Pages Function (Gitalk Token Proxy)
# ------------------------------------------------------------
echo ""
echo "🔧 创建 Cloudflare Pages Function..."
mkdir -p "$FUNCTIONS_DIR/api"

cat > "$FUNCTIONS_DIR/api/gitalk-token.js" << 'CF_FUNCTION'
/**
 * Gitalk OAuth Token Proxy for Cloudflare Pages Functions
 * 路径: /api/gitalk-token
 * 方法: POST
 * 
 * Cloudflare Pages Functions 使用 Web API (Request/Response)
 * 与 Netlify Functions 的 AWS Lambda 格式完全不同
 */
export async function onRequestPost(context) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json'
  };

  try {
    const body = await context.request.text();
    
    const githubResp = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: body
    });

    const data = await githubResp.text();

    return new Response(data, {
      status: githubResp.status,
      headers: corsHeaders
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: corsHeaders }
    );
  }
}

// 处理 CORS 预检请求
export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    }
  });
}
CF_FUNCTION

echo "   ✅ 已创建 functions/api/gitalk-token.js"

# ------------------------------------------------------------
# 4. 生成 wrangler.toml
# ------------------------------------------------------------
echo ""
echo "📝 生成 wrangler.toml..."

# 尝试从 package.json 读取项目名作为 fallback
PROJECT_NAME="hexo-blog"
if [[ -f "$HEXO_ROOT/package.json" ]]; then
  PROJECT_NAME=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$HEXO_ROOT/package.json" | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//;s/"//' || echo "hexo-blog")
fi

cat > "$WRANGLER_CONFIG" << WRANGLER_EOF
# Cloudflare Pages 配置
# 文档: https://developers.cloudflare.com/pages/configuration/
name = "${PROJECT_NAME}"
compatibility_date = "2024-09-23"

# Pages 构建配置（也可在 Dashboard 中设置）
[build]
command = "npm run build"
output_dir = "public"

# Functions 路由自动映射，无需额外配置
# /api/gitalk-token → functions/api/gitalk-token.js
WRANGLER_EOF

echo "   ✅ 已生成 wrangler.toml (项目名: ${PROJECT_NAME})"

# ------------------------------------------------------------
# 5. 更新 _config.flatpaper.yml 中的 Gitalk proxy
# ------------------------------------------------------------
echo ""
echo "🔄 更新 Gitalk proxy 配置..."

if [[ -f "$FLATPAPER_CONFIG" ]]; then
  # 备份原配置
  cp "$FLATPAPER_CONFIG" "${FLATPAPER_CONFIG}.bak.$(date +%s)"
  
  # 如果已有 proxy 行则替换，否则在 gitalk 块末尾追加
  if grep -q "^  proxy:" "$FLATPAPER_CONFIG"; then
    sed -i.bak "s|^  proxy:.*|  proxy: '/api/gitalk-token'|" "$FLATPAPER_CONFIG"
    rm -f "${FLATPAPER_CONFIG}.bak"
    echo "   ✅ 已更新现有 proxy 为 /api/gitalk-token"
  elif grep -q "^gitalk:" "$FLATPAPER_CONFIG"; then
    # 在 gitalk: 块的最后一个缩进行后插入 proxy
    sed -i.bak "/^gitalk:/,/^[^ ]/{ /^[^ ]/i\\
  proxy: '/api/gitalk-token'
}" "$FLATPAPER_CONFIG"
    # 如果 sed 没匹配到（gitalk 是文件末尾），直接追加
    if ! grep -q "proxy:" "$FLATPAPER_CONFIG"; then
      echo "  proxy: '/api/gitalk-token'" >> "$FLATPAPER_CONFIG"
    fi
    rm -f "${FLATPAPER_CONFIG}.bak"
    echo "   ✅ 已追加 proxy: '/api/gitalk-token'"
  else
    echo "   ⚠️  未找到 gitalk 配置块，请手动添加:"
    echo "      proxy: '/api/gitalk-token'"
  fi
else
  echo "   ⚠️  未找到 $FLATPAPER_CONFIG，跳过"
fi

# ------------------------------------------------------------
# 6. 确保 .gitignore 包含必要条目
# ------------------------------------------------------------
GITIGNORE="$HEXO_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  for pattern in ".wrangler/" "node_modules/" "public/"; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
      echo "$pattern" >> "$GITIGNORE"
    fi
  done
  echo ""
  echo "📋 已更新 .gitignore"
fi

# ------------------------------------------------------------
# 7. 完成
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "✅ 迁移完成！"
echo "============================================================"
echo ""
echo "📁 变更摘要:"
echo "   ➕ functions/api/gitalk-token.js  (CF Pages Function)"
echo "   ➕ wrangler.toml                  (CF 配置)"
echo "   ➖ netlify/                       (已移除)"
echo "   ➖ netlify.toml                   (已移除)"
echo "   🔄 _config.flatpaper.yml          (proxy 已更新)"
echo ""
echo "🚀 部署步骤:"
echo "   1. npm install                    # 安装依赖"
echo "   2. npm run build                  # 本地验证构建"
echo "   3. npx wrangler pages deploy public  # 部署到 CF Pages"
echo ""
echo "   或在 CF Dashboard 中连接 Git 仓库:"
echo "   Build command:  npm run build"
echo "   Output dir:     public"
echo ""
echo "⚠️  注意事项:"
echo "   • 确保 package.json 中有 \"build\": \"hexo generate\" 脚本"
echo "   • 首次部署后在 CF Dashboard → Settings → Functions 确认路由生效"
echo "   • Client Secret 如已泄露请务必重置"
echo "============================================================"