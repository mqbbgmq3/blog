#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FlatPaper v0.4.0 + Gitalk 一键安装脚本
# 用法: bash install-flatpaper-gitalk.sh [hexo站点根目录]
# 默认在当前目录执行
# ============================================================

HEXO_ROOT="${1:-.}"
THEME_VERSION="v0.4.0"
THEME_DIR="$HEXO_ROOT/themes/flatpaper"
RELEASE_URL="https://github.com/homulilly/hexo-theme-flatpaper/archive/refs/tags/${THEME_VERSION}.tar.gz"

echo "📦 FlatPaper ${THEME_VERSION} + Gitalk 一键安装"
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
# 2. 下载并解压 flatpaper v0.4.0
# ------------------------------------------------------------
if [[ -d "$THEME_DIR" ]]; then
  echo "⚠️  themes/flatpaper 已存在，备份为 flatpaper.bak.$(date +%s)"
  mv "$THEME_DIR" "${THEME_DIR}.bak.$(date +%s)"
fi

echo "⬇️  下载 flatpaper ${THEME_VERSION}..."
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

curl -fSL "$RELEASE_URL" -o "$TMPDIR/flatpaper.tar.gz"
tar -xzf "$TMPDIR/flatpaper.tar.gz" -C "$TMPDIR"

EXTRACTED=$(find "$TMPDIR" -maxdepth 1 -type d -name "hexo-theme-flatpaper-*" | head -1)
if [[ -z "$EXTRACTED" ]]; then
  echo "❌ 解压失败，未找到主题目录"
  exit 1
fi

mv "$EXTRACTED" "$THEME_DIR"
echo "✅ 主题已安装到 $THEME_DIR"

# ------------------------------------------------------------
# 3. 生成主题配置文件（如果不存在）
# ------------------------------------------------------------
SITE_CONFIG="$HEXO_ROOT/_config.flatpaper.yml"
if [[ ! -f "$SITE_CONFIG" ]]; then
  cp "$THEME_DIR/_config.yml" "$SITE_CONFIG"
  echo "✅ 已生成 $SITE_CONFIG"
else
  echo "ℹ️  $SITE_CONFIG 已存在，跳过覆盖"
fi

# ------------------------------------------------------------
# 4. 注入 Gitalk 配置到 _config.flatpaper.yml
# ------------------------------------------------------------
echo ""
echo "🔧 配置 Gitalk..."

if grep -q "^gitalk:" "$SITE_CONFIG" 2>/dev/null; then
  echo "ℹ️  检测到已有 gitalk 配置，跳过自动注入"
else
  cat >> "$SITE_CONFIG" << 'GITALK_CONFIG'

# ============================================================
# Gitalk 评论系统配置
# 使用前请先在 GitHub 创建 OAuth App:
#   https://github.com/settings/developers
#   Authorization callback URL 填你的博客域名
# ============================================================
gitalk:
  clientID: ''          # GitHub OAuth Client ID
  clientSecret: ''      # GitHub OAuth Client Secret
  repo: ''              # 存放评论 Issue 的仓库名
  owner: ''             # 仓库所有者 GitHub 用户名
  admin: ['']           # 管理员 GitHub 用户名列表
  distractionFreeMode: false
  language: 'zh-CN'     # 界面语言: zh-CN / en
GITALK_CONFIG
  echo "✅ Gitalk 配置模板已追加到 $SITE_CONFIG"
  echo "   ⚠️  请填写 clientID / clientSecret / repo / owner / admin"
fi

# ------------------------------------------------------------
# 5. 修改主题文件以支持 Gitalk
# ------------------------------------------------------------
echo ""
echo "🔧 修改主题文件以集成 Gitalk..."

COMMENTS_EJS="$THEME_DIR/layout/_partial/comments.ejs"
COMMENTS_SDK_EJS="$THEME_DIR/layout/_partial/comments-sdk.ejs"

cp "$COMMENTS_EJS" "${COMMENTS_EJS}.orig"
cp "$COMMENTS_SDK_EJS" "${COMMENTS_SDK_EJS}.orig"

cat > "$COMMENTS_EJS" << 'COMMENTS_EJS_CONTENT'
<%
var sys = theme.comments ? String(theme.comments).toLowerCase() : '';
var pageTypeKey = String(page.type || '').toLowerCase();
var isNotFoundPage = page.layout === '404' || pageTypeKey === '404';
var isContentPage = (is_post() || page.layout === 'page') && !isNotFoundPage;
var canRender = isContentPage && page.comments !== false;

var tk = theme.twikoo || {};
var ak = theme.artalk || {};
var gt = theme.gitalk || {};
var renderTwikoo = canRender && sys === 'twikoo' && tk.envId;
var renderArtalk = canRender && sys === 'artalk' && ak.server;
var renderGitalk = canRender && sys === 'gitalk' && gt.clientID && gt.repo && gt.owner;

function jsonForScript(value) {
  return JSON.stringify(value).replace(/<\//g, '<\\/');
}
%>
<% if (renderTwikoo) { %>
<section class="comments-section" aria-label="<%= flatpaper_i18n('common.comments') %>">
  <header class="comments-section__head">
    <h2><%- partial('_partial/icons', { icon: 'message-circle' }) %><%= flatpaper_i18n('common.comments') %></h2>
  </header>
  <div id="tcomment"></div>
</section>
<script>
window.addEventListener('load', function () {
  if (typeof twikoo === 'undefined') return;
  twikoo.init({ envId: <%- jsonForScript(tk.envId) %>, el: '#tcomment' });
});
</script>
<% } else if (renderArtalk) { %>
<section class="comments-section" aria-label="<%= flatpaper_i18n('common.comments') %>">
  <header class="comments-section__head">
    <h2><%- partial('_partial/icons', { icon: 'message-circle' }) %><%= flatpaper_i18n('common.comments') %></h2>
  </header>
  <div id="artalk-comments"></div>
</section>
<script>
window.addEventListener('load', function () {
  if (typeof Artalk === 'undefined' || typeof Artalk.init !== 'function') return;
  Artalk.init({
    el: '#artalk-comments',
    pageKey: <%- jsonForScript(page.permalink || url_for(page.path || '')) %>,
    pageTitle: <%- jsonForScript(page.title || '') %>,
    server: <%- jsonForScript(ak.server) %>,
    site: <%- jsonForScript(ak.site || '') %>
  });
});
</script>
<% } else if (renderGitalk) { %>
<section class="comments-section" aria-label="<%= flatpaper_i18n('common.comments') %>">
  <header class="comments-section__head">
    <h2><%- partial('_partial/icons', { icon: 'message-circle' }) %><%= flatpaper_i18n('common.comments') %></h2>
  </header>
  <div id="gitalk-container"></div>
</section>
<script>
window.addEventListener('load', function () {
  if (typeof Gitalk === 'undefined') return;
  var gitalk = new Gitalk({
    clientID: <%- jsonForScript(gt.clientID) %>,
    clientSecret: <%- jsonForScript(gt.clientSecret || '') %>,
    repo: <%- jsonForScript(gt.repo) %>,
    owner: <%- jsonForScript(gt.owner) %>,
    admin: <%- jsonForScript(gt.admin || []) %>,
    id: location.pathname.substr(0, 50),
    distractionFreeMode: <%= gt.distractionFreeMode !== false %>,
    language: <%- jsonForScript(gt.language || 'zh-CN') %>
  });
  gitalk.render('gitalk-container');
});
</script>
<% } %>
COMMENTS_EJS_CONTENT

cat > "$COMMENTS_SDK_EJS" << 'COMMENTS_SDK_EJS_CONTENT'
<%
var sys = theme.comments ? String(theme.comments).toLowerCase() : '';
var pageTypeKey = String(page.type || '').toLowerCase();
var isNotFoundPage = page.layout === '404' || pageTypeKey === '404';
var isContentPage = (is_post() || page.layout === 'page') && !isNotFoundPage;
if (!isContentPage || page.comments === false) { sys = ''; }

if (sys === 'twikoo' && theme.twikoo && theme.twikoo.envId) {
  var tkCdn = flatpaper_safe_url(
    theme.twikoo.cdn || 'https://cdn.jsdelivr.net/npm/twikoo@1.7.9/dist/twikoo.all.min.js', 'href');
  if (tkCdn && tkCdn !== '#') { %>
<script defer src="<%= tkCdn %>"></script>
<% }
} else if (sys === 'artalk' && theme.artalk && theme.artalk.server) {
  var akCss = flatpaper_safe_url(
    theme.artalk.cdn_css || 'https://cdn.jsdelivr.net/npm/artalk@2.9.1/dist/Artalk.css', 'href');
  var akJs = flatpaper_safe_url(
    theme.artalk.cdn_js || 'https://cdn.jsdelivr.net/npm/artalk@2.9.1/dist/Artalk.js', 'href');
  if (akCss && akCss !== '#') { %><link rel="stylesheet" href="<%= akCss %>"><% }
  if (akJs && akJs !== '#') { %><script defer src="<%= akJs %>"></script><% }
} else if (sys === 'gitalk' && theme.gitalk && theme.gitalk.clientID) {
  var gtCss = flatpaper_safe_url(
    theme.gitalk.cdn_css || 'https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.css', 'href');
  var gtJs = flatpaper_safe_url(
    theme.gitalk.cdn_js || 'https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.min.js', 'href');
  if (gtCss && gtCss !== '#') { %><link rel="stylesheet" href="<%= gtCss %>"><% }
  if (gtJs && gtJs !== '#') { %><script defer src="<%= gtJs %>"></script><% }
} %>
COMMENTS_SDK_EJS_CONTENT

echo "✅ comments.ejs 和 comments-sdk.ejs 已更新"

# ------------------------------------------------------------
# 6. 检查站点主题配置
# ------------------------------------------------------------
SITE_MAIN_CONFIG="$HEXO_ROOT/_config.yml"
if ! grep -q "^theme:.*flatpaper" "$SITE_MAIN_CONFIG" 2>/dev/null; then
  echo ""
  echo "⚠️  未在 $SITE_MAIN_CONFIG 中检测到 theme: flatpaper，请手动确认"
fi

# ------------------------------------------------------------
# 7. 完成
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "🎉 安装完成！"
echo "============================================================"
echo ""
echo "📋 接下来："
echo "   1. 编辑 $SITE_CONFIG → 设置 comments: gitalk 并填写 OAuth 信息"
echo "   2. 创建 GitHub OAuth App → https://github.com/settings/developers"
echo "   3. hexo clean && hexo g && hexo s"
echo "   4. 首次访问文章页用 GitHub 登录授权即可"
echo ""
echo "📁 原始文件已备份为 *.orig"
echo "============================================================"