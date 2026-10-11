<?php
/**
 * MirrorSpeed Blog theme functions.
 */

if (!defined('ABSPATH')) exit;

function mirrorspeed_setup() {
    add_theme_support('title-tag');
    add_theme_support('post-thumbnails');
    add_theme_support('automatic-feed-links');
    add_theme_support('html5', array('search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script'));
    add_theme_support('responsive-embeds');
    register_nav_menus(array(
        'primary' => __('Primary Menu', 'mirrorspeed-blog'),
    ));
}
add_action('after_setup_theme', 'mirrorspeed_setup');

function mirrorspeed_assets() {
    // 与 mirrorspeed.com 相同的字体：Manrope / Unbounded / JetBrains Mono
    wp_enqueue_style(
        'mirrorspeed-fonts',
        'https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Unbounded:wght@600;700;800;900&family=JetBrains+Mono:wght@400;500&display=swap',
        array(),
        null
    );
    wp_enqueue_style('mirrorspeed-style', get_stylesheet_uri(), array('mirrorspeed-fonts'), '1.0.0');
}
add_action('wp_enqueue_scripts', 'mirrorspeed_assets');

// 摘要长度与结尾
function mirrorspeed_excerpt_length($len) { return 24; }
add_filter('excerpt_length', 'mirrorspeed_excerpt_length');
function mirrorspeed_excerpt_more($more) { return '…'; }
add_filter('excerpt_more', 'mirrorspeed_excerpt_more');

if (!isset($content_width)) $content_width = 760;

// 估算阅读时长（分钟）
function mirrorspeed_read_time($post_id = null) {
    $content = get_post_field('post_content', $post_id ?: get_the_ID());
    $words = max(1, str_word_count(strip_tags($content)));
    // 中文按字数估算：strip 后取字符数的一半作为“词数”近似
    $chars = mb_strlen(strip_tags($content));
    $count = max($words, intval($chars / 2));
    return max(1, (int) ceil($count / 250));
}

// ── 微信图片防盗链 ────────────────────────────────────────────
// 生产环境通过 Code Snippets snippet id=6 运行（与下面全文补全 id=5 分开）。
// mmbiz.qpic.cn 对非微信域名的 Referer 返回「未经允许不可引用」占位图；
// 输出 no-referrer 后浏览器不带 Referer，图片正常加载。
add_action('wp_head', function () {
    echo '<meta name="referrer" content="no-referrer">' . "\n";
}, 1);

// ── 公众号全文补全 ─────────────────────────────────────────────
// 生产环境实际通过 Code Snippets 插件的 snippet (id=5) 运行同名函数；
// 这里保留一份源码副本，用 function_exists 守卫避免重复定义 fatal。
// 背景：WPeMatico 采集的 decemberpei.cyou/rssbox feed 的 <description>
// 只有标题，{content} 为空导致文章"截断"。保存文章时抓 mp.weixin.qq.com
// 原文页，抽取 #js_content 写回 .feed-content，并用正文前 80 字填充摘要。
if (!function_exists('mirrorspeed_wechat_fulltext')) {
    add_filter('wp_insert_post_data', 'mirrorspeed_wechat_fulltext', 20);
    function mirrorspeed_wechat_fulltext($data) {
        if ($data['post_type'] !== 'post' || empty($data['post_content'])) return $data;
        $content = wp_unslash($data['post_content']);
        if (strpos($content, 'mp.weixin.qq.com') === false) return $data;
        if (!preg_match('#https?://mp\.weixin\.qq\.com/[^\s"\'<>]+#', $content, $m)) return $data;

        $resp = wp_remote_get(html_entity_decode($m[0]), array(
            'timeout'     => 20,
            'redirection' => 5,
            'user-agent'  => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        ));
        if (is_wp_error($resp)) return $data;
        $html = wp_remote_retrieve_body($resp);
        if (strlen($html) < 500) return $data;

        libxml_use_internal_errors(true);
        $doc = new DOMDocument('1.0', 'UTF-8');
        $doc->loadHTML('<?xml encoding="utf-8"?>' . $html);
        libxml_clear_errors();
        $node = (new DOMXPath($doc))->query('//div[@id="js_content"]')->item(0);
        if (!$node) return $data;

        $body = '';
        foreach (iterator_to_array($node->childNodes) as $c) $body .= $doc->saveHTML($c);
        // 微信图片懒加载：去掉占位 src="data:..."，把 data-src 提升为 src
        $body = preg_replace('#(<img\b[^>]*?)\ssrc="data:[^"]*"#i', '$1', $body);
        $body = preg_replace('#(<img\b[^>]*?)\sdata-src=#i', '$1 src=', $body);
        $body = wp_kses_post($body);
        if (strlen(trim(wp_strip_all_tags($body))) < 20) return $data;

        $excerpt = wp_trim_words(wp_strip_all_tags($body), 80, '…');
        $content = preg_replace_callback(
            '#(<div class="feed-desc"[^>]*>\s*<h3>[^<]*</h3>\s*<p>).*?(</p>)#s',
            function ($x) use ($excerpt) { return $x[1] . esc_html($excerpt) . $x[2]; },
            $content, 1
        );
        $content = preg_replace_callback(
            '#<div class="feed-content">.*?</div>#s',
            function () use ($body) { return '<div class="feed-content">' . $body . '</div>'; },
            $content, 1
        );
        $content = str_replace('{authorlink}', '', $content);

        $data['post_content'] = wp_slash($content);
        return $data;
    }
}

// ═══════════════════════════════════════════════════════════════
// 以下为线上 Code Snippets 的源码副本（Hostinger WAF 拦截 theme-editor
// 的 PHP POST，只能经 REST 管理 snippet；此处存档保持与线上一致）。
//   snippet id=8「采集后处理」：语言归类 + 特色图 + Groq 翻译 + 存量修复 + llms.txt
//   snippet id=9「SEO/OG/分享 meta」
// ═══════════════════════════════════════════════════════════════

// ── snippet id=8：采集文章后处理 ─────────────────────────────────
// WPeMatico 拉公众号中文内容，但 Polylang 默认语言是 English（全站 1600+
// 采集文章曾全挂英文「未分类」）。逻辑：
//  1) 确保「公众号精选」(zh) ↔「Curated Feeds」(en) 分类对存在（存 option）
//  2) save_post：含 mp.weixin.qq.com 的文章 → 语言 zh + 中文分类 +
//     首图下载为本地特色图 + 回填 post_excerpt + 调度异步 Groq 翻译
//  3) ms_translate_post cron：Groq 翻译标题+正文 → 发布英文版并互链
//  4) ms_fix_zh_batch cron：后台分批把存量微信文章改归中文（只归类不翻译）
//  5) /llms.txt（实际被 Rank Math 接管，保留无害）
//
// Groq key 填在线上 snippet 顶部：define('MS_GROQ_API_KEY', '...');

if (!defined('MS_GROQ_API_KEY')) define('MS_GROQ_API_KEY', '');
if (!defined('MS_GROQ_MODEL'))   define('MS_GROQ_MODEL', 'openai/gpt-oss-120b');
// Groq 免费档限额实测：qwen OTPM=1000（一次大块就 429）、llama-3.3-70b 已下线；
// gpt-oss-120b 单次可 4096+ tokens、连发 ~2 次/分钟，配增量分块最稳。

if (!function_exists('ms_feed_cat_ids')) {
    function ms_feed_cat_ids() {
        $ids = get_option('ms_feed_cats');
        if (is_array($ids) && term_exists((int)$ids[0]) && term_exists((int)$ids[1])) return $ids;

        $zh = get_term_by('slug', 'wechat-feeds', 'category');
        if (!$zh) { $r = wp_insert_term('公众号精选', 'category', array('slug' => 'wechat-feeds')); $zh = is_wp_error($r) ? get_term_by('slug', 'wechat-feeds', 'category') : (object)$r; }
        $en = get_term_by('slug', 'curated-feeds', 'category');
        if (!$en) { $r = wp_insert_term('Curated Feeds', 'category', array('slug' => 'curated-feeds')); $en = is_wp_error($r) ? get_term_by('slug', 'curated-feeds', 'category') : (object)$r; }
        if (!$zh || !$en) return array(0, 0);

        if (function_exists('pll_set_term_language')) {
            pll_set_term_language((int)$zh->term_id, 'zh');
            pll_set_term_language((int)$en->term_id, 'en');
            if (function_exists('pll_save_term_translations'))
                pll_save_term_translations(array('zh' => (int)$zh->term_id, 'en' => (int)$en->term_id));
        }
        $ids = array((int)$zh->term_id, (int)$en->term_id);
        update_option('ms_feed_cats', $ids);
        return $ids;
    }
    add_action('init', 'ms_feed_cat_ids');
}

// mmbiz URL 无扩展名，须手动指定文件名再 sideload（media_sideload_image 会失败）
if (!function_exists('ms_sideload_thumb')) {
    function ms_sideload_thumb($post_id, $url) {
        require_once ABSPATH . 'wp-admin/includes/media.php';
        require_once ABSPATH . 'wp-admin/includes/file.php';
        require_once ABSPATH . 'wp-admin/includes/image.php';
        $tmp = download_url($url, 30);
        if (is_wp_error($tmp)) return;
        $ext = 'jpg';
        if (preg_match('#wx_fmt=(\w+)#i', $url, $m)) $ext = strtolower($m[1]);
        $file = array('name' => 'wechat-' . substr(md5($url), 0, 12) . '.' . $ext, 'tmp_name' => $tmp);
        $att = media_handle_sideload($file, $post_id);
        if (is_wp_error($att)) { @unlink($tmp); return; }
        set_post_thumbnail($post_id, $att);
    }
}

if (!function_exists('ms_feed_post_process')) {
    add_action('save_post_post', 'ms_feed_post_process', 30);
    function ms_feed_post_process($post_id) {
        static $busy = false;
        if ($busy) return;
        if (wp_is_post_revision($post_id) || wp_is_post_autosave($post_id)) return;
        if (!empty($GLOBALS['ms_creating_translation'])) return;
        $c = get_post_field('post_content', $post_id);
        if (strpos($c, 'mp.weixin.qq.com') === false) return;

        $busy = true;
        list($zh_cat) = ms_feed_cat_ids();
        if ($zh_cat) {
            if (function_exists('pll_set_post_language')) pll_set_post_language($post_id, 'zh');
            wp_set_post_categories($post_id, array($zh_cat));
        }
        if (!has_post_thumbnail($post_id) &&
            preg_match('#https?://mmbiz\.qpic\.cn/[^"\'\s<>]+#i', $c, $im)) {
            ms_sideload_thumb($post_id, html_entity_decode($im[0]));
        }
        if (get_post_field('post_excerpt', $post_id) === '' &&
            preg_match('#<div class="feed-desc"[^>]*>.*?<p>.*?</p>#s', $c, $em)) {
            $exc = trim(wp_strip_all_tags($em[0]));
            if ($exc !== '') wp_update_post(array('ID' => $post_id, 'post_excerpt' => $exc));
        }
        // 翻译链接可能指向已删除的文章（如手动删 EN 版），需 get_post 存在检查
        $en_t = function_exists('pll_get_post') ? pll_get_post($post_id, 'en') : 0;
        if (!$en_t || !get_post($en_t)) {
            if (!wp_next_scheduled('ms_translate_post', array($post_id)))
                wp_schedule_single_event(time() + 10, 'ms_translate_post', array($post_id));
        }
        $busy = false;
    }
}

if (!function_exists('ms_groq_translate')) {
    function ms_groq_translate($text, $is_html) {
        $sys = $is_html
            ? 'You are a professional Chinese-to-English translator for a tech blog. Translate the HTML below to natural English. Keep ALL HTML tags, attributes, URLs, class names and placeholders EXACTLY as-is; translate only inner text. Output ONLY the translated HTML, no commentary, no markdown fences.'
            : 'Translate this Chinese blog title into concise natural English. Output ONLY the translation.';
        $resp = wp_remote_post('https://api.groq.com/openai/v1/chat/completions', array(
            'timeout' => 90,
            'headers' => array('Authorization' => 'Bearer ' . MS_GROQ_API_KEY, 'Content-Type' => 'application/json'),
            'body'    => wp_json_encode(array(
                'model'       => MS_GROQ_MODEL,
                'messages'    => array(
                    array('role' => 'system', 'content' => $sys),
                    array('role' => 'user',   'content' => $text),
                ),
                'temperature' => 0.3,
                'max_tokens'  => 4096,
                'reasoning_effort' => 'low',
            )),
        ));
        if (is_wp_error($resp)) return false;
        $j = json_decode(wp_remote_retrieve_body($resp), true);
        $out = isset($j['choices'][0]['message']['content']) ? trim($j['choices'][0]['message']['content']) : '';
        $out = preg_replace('#^```[a-zA-Z]*\s*|\s*```$#', '', $out);
        // gpt-oss 偶尔包 "translates to:" / markdown 强调
        $out = preg_replace('#^(?:translates?\s+to:?|here (?:is|\'s) (?:the )?transl\w+:?)[^\n]*\n?#i', '', $out);
        if (!$is_html) $out = trim($out, "\"'** \t\n");
        return $out === '' ? false : $out;
    }
}

if (!function_exists('ms_split_html')) {
    function ms_split_html($html, $max) {
        $parts = preg_split('#(?=<(?:div|p|section|h[1-6]|table|blockquote|ul|ol|figure)\b)#i', $html);
        $chunks = array(); $cur = '';
        foreach ($parts as $p) {
            if ($p === '') continue;
            if (strlen($cur) + strlen($p) > $max && $cur !== '') { $chunks[] = $cur; $cur = ''; }
            $cur .= $p;
            if (strlen($cur) > $max) { $chunks[] = $cur; $cur = ''; }
        }
        if ($cur !== '') $chunks[] = $cur;
        return $chunks;
    }
}

if (!function_exists('ms_translate_post_handler')) {
    add_action('ms_translate_post', 'ms_translate_post_handler');
    function ms_translate_post_handler($post_id) {
        if (!MS_GROQ_API_KEY || get_post_status($post_id) !== 'publish') return;
        $en_t = function_exists('pll_get_post') ? pll_get_post($post_id, 'en') : 0;
        if ($en_t && get_post($en_t)) return;

        // 增量翻译：每次 cron tick 只翻一块（~20s 一块，绕开免费档每分钟限流），
        // 状态存 _ms_t_state meta：{title, chunks[], done[]}；块失败 60s 后自动重试。
        $st = get_post_meta($post_id, '_ms_t_state', true);
        if (!is_array($st) || !isset($st['chunks'])) {
            $title = get_the_title($post_id);
            $en_title = ms_groq_translate($title, false);
            $st = array(
                'title'  => $en_title ?: $title,
                'chunks' => ms_split_html(get_post_field('post_content', $post_id), 1800),
                'done'   => array(),
            );
            update_post_meta($post_id, '_ms_t_state', $st);
            wp_schedule_single_event(time() + 20, 'ms_translate_post', array($post_id));
            return;
        }

        // 时间预算循环：本 tick 内连续翻多块（约 5-7s/块），耗尽再排下一 tick。
        // Groq 免费档 TPM=8000，单块 ~3400 token，40s 预算配块间 2s 间隔可稳住；
        // 遇 429/错误即停，65s 后从断点继续（done[] 已落 meta，不丢进度）。
        @set_time_limit(120);
        $deadline = time() + 40;
        $i = count($st['done']);
        while ($i < count($st['chunks'])) {
            $t = ms_groq_translate($st['chunks'][$i], true);
            if ($t === false) {
                wp_schedule_single_event(time() + 65, 'ms_translate_post', array($post_id));
                return;
            }
            $st['done'][] = $t; $i++;
            update_post_meta($post_id, '_ms_t_state', $st);
            if (time() >= $deadline) {
                wp_schedule_single_event(time() + 5, 'ms_translate_post', array($post_id));
                return;
            }
            sleep(2);
        }

        // 全部块完成：组装发布英文版
        $en_body = implode('', $st['done']);
        remove_filter('wp_insert_post_data', 'mirrorspeed_wechat_fulltext', 20);
        $GLOBALS['ms_creating_translation'] = true;
        $new_id = wp_insert_post(array(
            'post_type'    => 'post',
            'post_status'  => 'publish',
            'post_title'   => $st['title'],
            'post_content' => $en_body,
        ), true);
        $GLOBALS['ms_creating_translation'] = false;

        if (!is_wp_error($new_id)) {
            list($zh_cat, $en_cat) = ms_feed_cat_ids();
            if ($en_cat) {
                if (function_exists('pll_set_post_language')) pll_set_post_language($new_id, 'en');
                if (function_exists('pll_save_post_translations'))
                    pll_save_post_translations(array('zh' => (int)$post_id, 'en' => (int)$new_id));
                wp_set_post_categories($new_id, array($en_cat));
            }
            $thumb = get_post_thumbnail_id($post_id);
            if ($thumb) set_post_thumbnail($new_id, $thumb);
        }
        delete_post_meta($post_id, '_ms_t_state');
    }
}

// 存量文章后台分批改归中文（一次性，自动推进；只归类不翻译）
add_action('init', function () {
    if (!get_option('ms_fix_batch_started')) {
        update_option('ms_fix_batch_started', 1);
        wp_schedule_single_event(time() + 30, 'ms_fix_zh_batch');
    }
});
add_action('ms_fix_zh_batch', function () {
    $q = new WP_Query(array(
        'post_type' => 'post', 'posts_per_page' => 40, 'fields' => 'ids',
        'post_status' => 'any', 's' => 'mp.weixin.qq.com',
    ));
    $did = 0;
    list($zh_cat) = ms_feed_cat_ids();
    foreach ($q->posts as $pid) {
        if (!function_exists('pll_get_post_language') || !$zh_cat) break;
        if (pll_get_post_language($pid, 'slug') !== 'en') continue;
        pll_set_post_language($pid, 'zh');
        wp_set_post_categories($pid, array($zh_cat));
        $did++;
    }
    if ($did > 0) wp_schedule_single_event(time() + 15, 'ms_fix_zh_batch');
});

// /llms.txt 兜底（线上实际由 Rank Math 接管输出，此处无害保留）
add_action('init', function () {
    $uri = parse_url(isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '', PHP_URL_PATH);
    if ($uri !== '/llms.txt') return;
    header('Content-Type: text/plain; charset=utf-8');
    echo "# MirrorSpeed Blog\n\n> MirrorSpeed 官方博客：VPN 加速、隐私安全、AI 与科技精选资讯。\n\n";
    echo "- English home: " . home_url('/') . "\n- 中文首页: " . home_url('/zh/') . "\n- Sitemap: " . home_url('/sitemap_index.xml') . "\n";
    exit;
});

// ── snippet id=9：SEO / OG / 分享 meta ────────────────────────────
// og:image = 本地特色图（无则正文第一张图）；og:description = 摘要/正文前40词；
// meta description + canonical + shortlink + Article JSON-LD。
// Rank Math 已装但需跑完 Setup Wizard 才输出；届时可停用本段/snippet。
if (!function_exists('ms_seo_meta')) {
    add_action('wp_head', 'ms_seo_meta', 5);
    function ms_seo_meta() {
        if (!is_singular('post')) return;
        $id    = get_the_ID();
        $title = get_the_title($id);
        $desc  = get_the_excerpt($id);
        if ($desc === '') $desc = wp_trim_words(wp_strip_all_tags(get_post_field('post_content', $id)), 40, '…');
        $url = get_permalink($id);

        $img = '';
        $t = get_post_thumbnail_id($id);
        if ($t) { $s = wp_get_attachment_image_src($t, 'large'); if ($s) $img = $s[0]; }
        if (!$img && preg_match('#<img\b[^>]*\ssrc="(https?://[^"]+)"#i', get_post_field('post_content', $id), $im)) $img = $im[1];

        $lang = function_exists('pll_get_post_language') ? pll_get_post_language($id, 'slug') : 'en';
        $locale = ($lang === 'zh') ? 'zh_CN' : 'en_GB';

        echo '<meta name="description" content="' . esc_attr($desc) . '">' . "\n";
        echo '<link rel="canonical" href="' . esc_url($url) . '">' . "\n";
        echo '<link rel="shortlink" href="' . esc_url(wp_get_shortlink($id)) . '">' . "\n";
        echo '<meta property="og:type" content="article">' . "\n";
        echo '<meta property="og:title" content="' . esc_attr($title) . '">' . "\n";
        echo '<meta property="og:description" content="' . esc_attr($desc) . '">' . "\n";
        echo '<meta property="og:url" content="' . esc_url($url) . '">' . "\n";
        echo '<meta property="og:site_name" content="MirrorSpeed Blog">' . "\n";
        echo '<meta property="og:locale" content="' . esc_attr($locale) . '">' . "\n";
        echo '<meta property="article:published_time" content="' . esc_attr(get_post_time('c', true, $id)) . '">' . "\n";
        echo '<meta property="article:modified_time" content="' . esc_attr(get_post_modified_time('c', true, $id)) . '">' . "\n";
        if ($img) echo '<meta property="og:image" content="' . esc_url($img) . '">' . "\n";
        echo '<meta name="twitter:card" content="' . ($img ? 'summary_large_image' : 'summary') . '">' . "\n";
        echo '<meta name="twitter:title" content="' . esc_attr($title) . '">' . "\n";
        echo '<meta name="twitter:description" content="' . esc_attr($desc) . '">' . "\n";
        if ($img) echo '<meta name="twitter:image" content="' . esc_url($img) . '">' . "\n";

        $ld = array(
            '@context'         => 'https://schema.org',
            '@type'            => 'Article',
            'headline'         => $title,
            'description'      => $desc,
            'datePublished'    => get_post_time('c', true, $id),
            'dateModified'     => get_post_modified_time('c', true, $id),
            'mainEntityOfPage' => $url,
            'inLanguage'       => $lang,
            'author'           => array('@type' => 'Organization', 'name' => 'MirrorSpeed'),
            'publisher'        => array('@type' => 'Organization', 'name' => 'MirrorSpeed'),
        );
        if ($img) $ld['image'] = $img;
        echo '<script type="application/ld+json">' . wp_json_encode($ld, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . '</script>' . "\n";
    }
}

// ── snippet「pll-disable-cookie-redirect」（线上激活中）────────────
// 修复：zh 访客从 /zh/ 点「English」→ / 被 Polylang 302 弹回 /zh/（x-redirect-by: Polylang）。
// 原因：Polylang「记住语言」pll_language cookie，在 plugins_loaded 就被读取决定
// preferred_language，init 阶段再删 cookie 太晚 → 三层拦截：
unset($_COOKIE['pll_language']);                                  // 顶层执行，尽量早
add_action('plugins_loaded', function () { unset($_COOKIE['pll_language']); }, 0);
add_filter('pll_preferred_language', '__return_false');           // 禁「首选语言」探测
add_filter('pll_check_canonical_url', '__return_false');          // 禁 Polylang canonical 重定向
// 兜底：仅当访问 / 而目标是 /zh/ 时取消重定向（wp_redirect 返 false = 不发 location）
add_filter('wp_redirect', function ($loc) {
    if ($loc && strpos($loc, '/zh') !== false &&
        isset($_SERVER['REQUEST_URI']) && preg_match('#^/?(\?.*)?$#', $_SERVER['REQUEST_URI']))
        return false;
    return $loc;
});
