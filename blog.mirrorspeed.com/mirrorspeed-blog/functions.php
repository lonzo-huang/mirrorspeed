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

// 主题分类优先显示：卡片/文章页 chip 从多个分类里挑主题分类，
// 跳过 feed 自动带入的垃圾词（公司名/邮箱/CVE 编号等）与来源标记分类。
function mirrorspeed_pick_cat($cats) {
    if (empty($cats)) return null;
    $topic = array(
        'security', 'security-zh', 'ai', 'ai-zh', 'privacy', 'privacy-zh',
        'deepdive', 'deepdive-zh', 'tutorial', 'tutorial-zh',
        'industry', 'industry-zh', 'tech', 'tech-zh',
        'wechat-feeds', 'curated-feeds', 'vpn', 'jia-su-qi', 'ji-chang',
    );
    foreach ($cats as $c) if (in_array($c->slug, $topic, true)) return $c;
    // 次选：名字不含 @ / .com / 纯编号的（过滤 feed 垃圾词）
    foreach ($cats as $c) if (!preg_match('/[@.]|cve-\d/i', $c->slug . $c->name)) return $c;
    return $cats[0];
}

// ── 浏览量统计 ────────────────────────────────────────────────
// single.php 前端 JS POST /wp-json/ms/v1/view/<id> 计数（LiteSpeed 缓存页
// 不打 PHP，必须走 REST 异步 +1）；meta key `_ms_views`，仅读这一个字段。
// ── 每页 9 篇（首页/分类/标签/归档/搜索）────────────────────
add_action('pre_get_posts', 'mirrorspeed_posts_per_page');
function mirrorspeed_posts_per_page($q) {
    if (is_admin() || !$q->is_main_query()) return;
    if ($q->is_home() || $q->is_category() || $q->is_tag() || $q->is_date() || $q->is_search()) {
        $q->set('posts_per_page', 9);
    }
}

add_action('rest_api_init', function () {
    register_rest_route('ms/v1', '/view/(?P<id>\d+)', array(
        'methods'             => 'POST',
        'callback'            => 'mirrorspeed_view_hit',
        'permission_callback' => '__return_true',
    ));
});
function mirrorspeed_view_hit($req) {
    $id = (int) $req['id'];
    $p  = get_post($id);
    if (!$p || $p->post_status !== 'publish' || $p->post_type !== 'post') {
        return new WP_REST_Response(array('ok' => false), 404);
    }
    $v = (int) get_post_meta($id, '_ms_views', true) + 1;
    update_post_meta($id, '_ms_views', $v);
    return new WP_REST_Response(array('ok' => true, 'views' => $v), 200);
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
//   snippet id=34「采集后处理」：语言归类 + 特色图 + Groq 翻译 + 存量修复 + llms.txt
//   snippet id=9「SEO/OG/分享 meta」
// ═══════════════════════════════════════════════════════════════

// -- snippet id=43 (v9.0): post-import pipeline
//   v8.9 -> v9.0: 8 topic category pairs (zh/en) + keyword routing,
//   EN feed categorization, ?ms_recat=now backfill. Source: .snip35_code.php
// ── snippet id=35（v8.2）：采集文章后处理 ────────────────────────────────
// WPeMatico 拉公众号中文内容，但 Polylang 默认语言是 English（全站 1600+
// 采集文章曾全挂英文「未分类」）。逻辑：
//  1) 确保「公众号精选」(zh) ↔「Curated Feeds」(en) 分类对存在（存 option）
//  2) save_post：含 mp.weixin.qq.com 的文章 → 语言 zh + 中文分类 +
//     首图下载为本地特色图 + 回填 post_excerpt + 调度异步 Groq 翻译
//  3) ms_translate_post cron：Groq 翻译标题+正文 → 发布英文版并互链
//  4) ms_fix_zh_batch cron：后台分批把存量微信文章改归中文（只归类不翻译）
//  5) /llms.txt（实际被 Rank Math 接管，保留无害）
//
// v8 = Groq key 池轮换：MS_GROQ_API_KEYS 数组，请求轮转（option ms_groq_key_idx）。
//   任何 429 都按 Groq 返回的 "try again in Xs" 把该 key 拉黑到恢复时刻
//   （transient ms_groq_dead_<idx>，值=恢复的 unix 时间戳），立刻换下一个 key；
//   全部拉黑时把最近的恢复时间写进 $GLOBALS['ms_groq_wait']，handler 睡到那时
//   再试（而不是每 65s 空转）。TPD=200k/key/天，N 个 key ≈ N×200k 日额度。
//
// Groq 免费档限额实测：qwen OTPM=1000（一次大块就 429）、llama-3.3-70b 已下线；
// gpt-oss-120b 单次可 4096+ tokens、连发 ~2 次/分钟，配增量分块最稳。

if (!defined('MS_GROQ_API_KEYS')) define('MS_GROQ_API_KEYS', array(
    '__GROQ_KEY__',
    '__GROQ_KEY__',
));
if (!defined('MS_GROQ_MODEL'))   define('MS_GROQ_MODEL', 'openai/gpt-oss-120b');
// 兼容 ms-tdiag-v3（id=30）probe 仍引用旧单 key 常量
if (!defined('MS_GROQ_API_KEY') && !empty(MS_GROQ_API_KEYS)) define('MS_GROQ_API_KEY', MS_GROQ_API_KEYS[0]);

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
                wp_schedule_single_event(time() + 10 + ($post_id % 60), 'ms_translate_post', array($post_id));
        }
        $busy = false;
    }
}

// Groq 429 body "Please try again in 8h21m33.123s" → 秒数；解析不到兜底 300
if (!function_exists('ms_groq_wait_secs')) {
    function ms_groq_wait_secs($body) {
        $b = (string) $body;
        if (preg_match('/try again in (\d+)h(\d+)m([\d.]+)s/i', $b, $m)) return $m[1] * 3600 + $m[2] * 60 + (int) ceil($m[3]);
        if (preg_match('/try again in (\d+)m([\d.]+)s/i',        $b, $m)) return $m[1] * 60 + (int) ceil($m[2]);
        if (preg_match('/try again in ([\d.]+)s/i',             $b, $m)) return (int) ceil($m[1]);
        if (preg_match('/try again in (\d+)m/i',               $b, $m)) return $m[1] * 60;
        return 300;
    }
}

if (!function_exists('ms_groq_translate')) {
    function ms_groq_translate($text, $is_html) {
        $sys = $is_html
            ? 'You are a professional Chinese-to-English translator for a tech blog. Translate the HTML below to natural English. Keep ALL HTML tags, attributes, URLs, class names and placeholders EXACTLY as-is; translate only inner text. Output ONLY the translated HTML, no commentary, no markdown fences.'
            : 'Translate this Chinese blog title into concise natural English. Output ONLY the translation.';
        $keys = array_values(array_filter((array) MS_GROQ_API_KEYS));
        $n = count($keys);
        if (!$n) return false;
        $idx = (int) get_option('ms_groq_key_idx', 0) % $n;
        $min_dead = 0;
        for ($tried = 0; $tried < $n; $tried++, $idx = ($idx + 1) % $n) {
            $dead_until = (int) get_transient('ms_groq_dead_' . $idx);
            if ($dead_until > time()) {
                if (!$min_dead || $dead_until < $min_dead) $min_dead = $dead_until;
                continue;
            }
            $resp = wp_remote_post('https://api.groq.com/openai/v1/chat/completions', array(
                'timeout' => 90,
                'headers' => array('Authorization' => 'Bearer ' . $keys[$idx], 'Content-Type' => 'application/json'),
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
            if (is_wp_error($resp)) { set_transient('ms_groq_dead_' . $idx, time() + 60, 60); if (!$min_dead || time() + 60 < $min_dead) $min_dead = time() + 60; continue; }
            if ((int) wp_remote_retrieve_response_code($resp) === 429) {
                $wait  = ms_groq_wait_secs(wp_remote_retrieve_body($resp));
                $until = time() + min($wait, DAY_IN_SECONDS);
                set_transient('ms_groq_dead_' . $idx, $until, min($wait, DAY_IN_SECONDS));
                if (!$min_dead || $until < $min_dead) $min_dead = $until;
                continue;
            }
            $code = (int) wp_remote_retrieve_response_code($resp);
            if ($code >= 400 && $code < 500) return $is_html ? $text : false;
            if ($code !== 200) { set_transient('ms_groq_dead_' . $idx, time() + 30, 30); if (!$min_dead || time() + 30 < $min_dead) $min_dead = time() + 30; continue; }
            update_option('ms_groq_key_idx', ($idx + 1) % $n, false);
            $j   = json_decode(wp_remote_retrieve_body($resp), true);
            $out = isset($j['choices'][0]['message']['content']) ? trim($j['choices'][0]['message']['content']) : '';
            $out = preg_replace('#^```[a-zA-Z]*\s*|\s*```$#', '', $out);
            // gpt-oss 偶尔包 "translates to:" / markdown 强调
            $out = preg_replace('#^(?:translates?\s+to:?|here (?:is|\'s) (?:the )?transl\w+:?)[^\n]*\n?#i', '', $out);
            if (!$is_html) $out = trim($out, "\"'** \t\n");
            return $out === '' ? ($is_html ? $text : false) : $out;
        }
        if ($min_dead > time()) $GLOBALS['ms_groq_wait'] = $min_dead - time();
        return false;
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
        if (empty(MS_GROQ_API_KEYS) || get_post_status($post_id) !== 'publish') return;
        $en_t = function_exists('pll_get_post') ? pll_get_post($post_id, 'en') : 0;
        if ($en_t && get_post($en_t)) return;

        // 增量翻译：每次 cron tick 只翻一块（~20s 一块，绕开免费档每分钟限流），
        // 状态存 _ms_t_state meta：{title, chunks[], done[]}；块失败按 ms_groq_wait 重试。
        $st = get_post_meta($post_id, '_ms_t_state', true);
        if (!is_array($st) || !isset($st['chunks'])) {
            $title = get_the_title($post_id);
            $en_title = ms_groq_translate($title, false);
            $st = array(
                'title'  => $en_title ?: $title,
            'src_title' => $title,
                'chunks' => ms_split_html(get_post_field('post_content', $post_id), 1800),
                'done'   => array(),
            );
            update_post_meta($post_id, '_ms_t_state', $st);
            $wait = isset($GLOBALS['ms_groq_wait']) ? (int) $GLOBALS['ms_groq_wait'] : 0;
            wp_schedule_single_event(time() + max(20, $wait + 5), 'ms_translate_post', array($post_id));
            return;
        }

        // 时间预算循环：本 tick 内连续翻多块（约 5-7s/块），耗尽再排下一 tick。
        // 遇 429/错误即停：单 key TPM 限流已被 key 池轮转吸收；全死则睡到最近恢复时刻。
        @set_time_limit(120);
        $deadline = time() + 40;
        $i = count($st['done']);
        while ($i < count($st['chunks'])) {
            $t = ms_groq_translate($st['chunks'][$i], true);
            if ($t === false) {
                $wait = isset($GLOBALS['ms_groq_wait']) ? (int) $GLOBALS['ms_groq_wait'] : 65;
                wp_schedule_single_event(time() + max(65, $wait + 5) + ($post_id % 37), 'ms_translate_post', array($post_id));
                return;
            }
            $st['done'][] = $t; $i++;
            update_post_meta($post_id, '_ms_t_state', $st);
            if (time() >= $deadline) {
                wp_schedule_single_event(time() + 5 + ($post_id % 25), 'ms_translate_post', array($post_id));
                return;
            }
            sleep(2);
        }

        // 全部块完成：组装发布英文版

        // v8.2: retry title once if still CJK (silent fallback from quota-era init)
        $en_title_pub = $st['title'];
        if (preg_match('/[\x{4e00}-\x{9fff}]/u', $en_title_pub)) {
            $rt = ms_groq_translate(isset($st['src_title']) ? $st['src_title'] : $en_title_pub, false);
            if ($rt && !preg_match('/[\x{4e00}-\x{9fff}]/u', $rt)) $en_title_pub = $rt;
        }
        $en_body = implode('', $st['done']);
        remove_filter('wp_insert_post_data', 'mirrorspeed_wechat_fulltext', 20);
        $GLOBALS['ms_creating_translation'] = true;
        $new_id = wp_insert_post(array(
            'post_type'    => 'post',
            'post_status'  => 'publish',
            'post_title'   => $en_title_pub,
            'post_name'    => sanitize_title($en_title_pub),
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


// v8.2: ?ms_retitle=1 admin trigger: self-scan EN posts w/ CJK titles -> retranslate title+slug
// ms_retitle_tick cron: 4 posts/tick, reschedules until clean; per-post 3-try cap via _ms_rt3_tries
if (!function_exists('ms_retitle_run')) {
    function ms_retitle_run($limit) {
        $q = new WP_Query(array(
            'post_type' => 'post', 'post_status' => 'any', 'posts_per_page' => -1, 'fields' => 'ids',
            'tax_query' => array(array('taxonomy' => 'language', 'field' => 'slug', 'terms' => 'en')),
        ));
        $bad = array();
        foreach ($q->posts as $pid) {
            $t = get_the_title($pid);
            if ($t && preg_match('/[\x{4e00}-\x{9fff}]/u', $t)) $bad[] = $pid;
        }
        $fixed = 0; $failed = 0; $left = 0; $mistag = 0; $log = array();
        foreach ($bad as $eid) {
            $zid = function_exists('pll_get_post') ? (int) pll_get_post($eid, 'zh') : 0;
            if (!$zid) { $mistag++; continue; }
            $tries = (int) get_post_meta($eid, '_ms_rt3_tries', true);
            if ($tries >= 3) continue;
            $left++;
            if ($fixed + $failed >= $limit) continue;
            update_post_meta($eid, '_ms_rt3_tries', $tries + 1);
            $src = get_the_title($zid);
            $new = ms_groq_translate($src, false);
            if (!$new) { $failed++; $log[$eid] = 'false'; continue; }
            if (preg_match('/[\x{4e00}-\x{9fff}]/u', $new)) { $failed++; $log[$eid] = 'cjk:' . mb_substr($new, 0, 40); continue; }
            wp_update_post(array('ID' => $eid, 'post_title' => $new, 'post_name' => sanitize_title($new)));
            $fixed++;
            $log[$eid] = 'ok:' . mb_substr($new, 0, 40);
            sleep(2);
        }
        return array('bad' => count($bad), 'mistag' => $mistag, 'left' => $left, 'fixed' => $fixed, 'failed' => $failed, 'log' => $log);
    }
}
add_action('ms_retitle_tick', function () {
    @set_time_limit(300);
    $r = ms_retitle_run(4);
    if ($r['left'] - $r['fixed'] > 0) wp_schedule_single_event(time() + 20, 'ms_retitle_tick');
});
add_action('admin_init', function () {
    if (empty($_GET['ms_retitle']) || !current_user_can('manage_options')) return;
    if (!wp_next_scheduled('ms_retitle_tick')) wp_schedule_single_event(time() + 5, 'ms_retitle_tick');
    if ($_GET['ms_retitle'] === 'now') {
        @set_time_limit(300);
        wp_die('<pre>' . esc_html(json_encode(ms_retitle_run(4), JSON_UNESCAPED_UNICODE)) . '</pre>');
    }
    wp_die('ms_retitle scheduled: 4 posts per ~20s tick until no zh-titled EN posts remain.');
});
// v9.0: ?ms_rtlist=1 -> dump bad EN posts with zh counterpart (for remote fixing)
add_action('admin_init', function () {
    if (empty($_GET['ms_rtlist']) || !current_user_can('manage_options')) return;
    $q = new WP_Query(array(
        'post_type' => 'post', 'post_status' => 'any', 'posts_per_page' => -1, 'fields' => 'ids',
        'tax_query' => array(array('taxonomy' => 'language', 'field' => 'slug', 'terms' => 'en')),
    ));
    $out = array();
    foreach ($q->posts as $pid) {
        $t = get_the_title($pid);
        if (!$t || !preg_match('/[\x{4e00}-\x{9fff}]/u', $t)) continue;
        $zid = function_exists('pll_get_post') ? (int) pll_get_post($pid, 'zh') : 0;
        $out[] = array('id' => $pid, 'zid' => $zid, 'ztitle' => $zid ? get_the_title($zid) : '', 'title' => $t);
    }
    wp_die('<pre>' . esc_html(json_encode($out, JSON_UNESCAPED_UNICODE)) . '</pre>');
});
// v9.0: ?ms_fixlang=now -> retag mistagged zh-original posts (weixin content, no zh pair) to zh
add_action('admin_init', function () {
    if (empty($_GET['ms_fixlang']) || !current_user_can('manage_options')) return;
    $limit = 80; $done = 0; $scanned = 0; $retagged = 0;
    $q = new WP_Query(array(
        'post_type' => 'post', 'post_status' => 'any', 'posts_per_page' => -1, 'fields' => 'ids',
        'tax_query' => array(array('taxonomy' => 'language', 'field' => 'slug', 'terms' => 'en')),
    ));
    $remain = 0;
    foreach ($q->posts as $pid) {
        $t = get_the_title($pid);
        if (!$t || !preg_match('/[\x{4e00}-\x{9fff}]/u', $t)) continue;
        $zid = function_exists('pll_get_post') ? (int) pll_get_post($pid, 'zh') : 0;
        if ($zid) continue;
        $scanned++;
        $body = get_post_field('post_content', $pid);
        if (strpos($body, 'mp.weixin.qq.com') === false) continue;
        if ($done < $limit) {
            if (function_exists('pll_set_post_language')) pll_set_post_language($pid, 'zh');
            if (function_exists('pll_save_post_translations')) pll_save_post_translations(array('zh' => $pid));
            $done++; $retagged++;
        } else { $remain++; }
    }
    wp_die('<pre>' . esc_html(json_encode(array('scanned' => $scanned, 'retagged' => $retagged, 'remain' => $remain), JSON_UNESCAPED_UNICODE)) . '</pre>');
});
// v9.0: ?ms_setlang=<eid>&z=<zid> -> restore EN tag + rebuild zh/en translation group
add_action('admin_init', function () {
    if (empty($_GET['ms_setlang']) || !current_user_can('manage_options')) return;
    $eid = (int) $_GET['ms_setlang'];
    $zid = isset($_GET['z']) ? (int) $_GET['z'] : 0;
    if (!$eid || !$zid) wp_die('<pre>{"err":"need id&z"}</pre>');
    if (function_exists('pll_get_post_language') && pll_get_post_language($zid) !== 'zh') {
        wp_die('<pre>' . esc_html(json_encode(array('err' => 'zid not zh', 'zlang' => pll_get_post_language($zid)))) . '</pre>');
    }
    if (function_exists('pll_set_post_language')) pll_set_post_language($eid, 'en');
    if (function_exists('pll_save_post_translations')) pll_save_post_translations(array('zh' => $zid, 'en' => $eid));
    wp_die('<pre>' . esc_html(json_encode(array('ok' => true, 'eid' => $eid, 'zid' => $zid, 'elang' => function_exists('pll_get_post_language') ? pll_get_post_language($eid) : '?', 'link' => get_permalink($eid)))) . '</pre>');
});
// 
// v9.0: 主题分类路由（8 对 zh/en）+ EN feed 归类 + ?ms_recat=now 回填
// 
// key => [zh 名, en 名, zh slug, en slug, 关键词(小写, 命中加权)]
if (!function_exists('ms_topic_map')) {
function ms_topic_map() {
    return array(
        'security' => array('网络安全', 'Cybersecurity', 'security-zh', 'security',
            array('cve','漏洞','exploit','ransomware','勒索','0day','zero-day','breach','数据泄露','ddos','黑客','hacker','malware','恶意','phishing','钓鱼','backdoor','后门','inject','注入','vulnerability','payload','attack','攻击','fuzz','sandbox escape')),
        'ai' => array('AI 与智能体', 'AI & Agents', 'ai-zh', 'ai',
            array('ai','gpt','llm','大模型','智能体','agent','机器人','robot','深度学习','neural','神经','openai','claude','transformer','diffusion','模型','生成式','机器学习','neurips')),
        'privacy' => array('隐私与网络', 'Privacy & VPN', 'privacy-zh', 'privacy',
            array('vpn','代理','tor','gfw','隐私','封锁','审查','dns','加密','encryption','surveillance','翻墙','梯子','节点','协议','wireguard','hysteria','vless')),
        'deepdive' => array('深度解析', 'Deep Dives', 'deepdive-zh', 'deepdive',
            array('详解','分析','复盘','原理','深入','剖析','源码','internals','teardown','reverse','逆向','审计','audit','内存','forensics','取证')),
        'tutorial' => array('实用教程', 'How-Tos', 'tutorial-zh', 'tutorial',
            array('教程','指南','如何','上手','入门','配置','安装','搭建','how to','walkthrough','guide','setup','install','configure','step-by-step','对比','评测','测评')),
        'industry' => array('行业动态', 'Industry News', 'industry-zh', 'industry',
            array('发布','推出','上线','融资','收购','上市','launch','raise','funding','acquire','acquisition','ipo','unveil','announce','合作','财报')),
        'tech' => array('科技与互联网', 'Tech & Internet', 'tech-zh', 'tech', array()),
    );
}
}

// 按标题+正文打分取主题 key；全 0  tech 兜底
if (!function_exists('ms_topic_key')) {
function ms_topic_key($title, $body) {
    $hay = mb_strtolower($title . ' ' . mb_substr(wp_strip_all_tags($body), 0, 3000));
    $best = 'tech'; $bs = 0;
    foreach (ms_topic_map() as $k => $m) {
        $s = 0;
        foreach ($m[4] as $kw) if (strpos($hay, $kw) !== false) $s++;
        if ($s > $bs) { $bs = $s; $best = $k; }
    }
    return $best;
}
}

// 确保某 key 的 zh/en 分类存在且已配对；返回 array(zh_id, en_id)
if (!function_exists('ms_topic_cat_ids')) {
function ms_topic_cat_ids($key) {
    $map = ms_topic_map();
    if (!isset($map[$key])) $key = 'tech';
    $m = $map[$key];
    $zh = get_term_by('slug', $m[2], 'category');
    if (!$zh) { $r = wp_insert_term($m[0], 'category', array('slug' => $m[2])); $zh = is_wp_error($r) ? get_term_by('slug', $m[2], 'category') : (object)$r; }
    $en = get_term_by('slug', $m[3], 'category');
    if (!$en) { $r = wp_insert_term($m[1], 'category', array('slug' => $m[3])); $en = is_wp_error($r) ? get_term_by('slug', $m[3], 'category') : (object)$r; }
    if (!$zh || !$en) return array(0, 0);
    if (function_exists('pll_set_term_language')) {
        pll_set_term_language((int)$zh->term_id, 'zh');
        pll_set_term_language((int)$en->term_id, 'en');
        if (function_exists('pll_save_term_translations'))
            pll_save_term_translations(array('zh' => (int)$zh->term_id, 'en' => (int)$en->term_id));
    }
    return array((int)$zh->term_id, (int)$en->term_id);
}
}

// save_post_post：EN feed / 非微信帖  英文主题分类（微信帖已由 ms_feed_post_process 处理 zh+精选）
if (!function_exists('ms_feed_topic_cat')) {
add_action('save_post_post', 'ms_feed_topic_cat', 35);
function ms_feed_topic_cat($post_id) {
    if (wp_is_post_revision($post_id) || wp_is_post_autosave($post_id)) return;
    if (!empty($GLOBALS['ms_creating_translation'])) return;
    $c = get_post_field('post_content', $post_id);
    if (strpos($c, 'mp.weixin.qq.com') !== false) return; // 微信走原钩子
    if (function_exists('pll_get_post_language') && pll_get_post_language($post_id) === 'zh') return;
    list($z, $eid) = ms_topic_cat_ids(ms_topic_key(get_the_title($post_id), $c));
    if ($eid) wp_set_post_categories($post_id, array($eid));
}
}

// 微信 zh 帖追加 zh 主题分类（保留 公众号精选 标记位）
if (!function_exists('ms_wechat_topic_cat')) {
add_action('save_post_post', 'ms_wechat_topic_cat', 36);
function ms_wechat_topic_cat($post_id) {
    if (wp_is_post_revision($post_id) || wp_is_post_autosave($post_id)) return;
    $c = get_post_field('post_content', $post_id);
    if (strpos($c, 'mp.weixin.qq.com') === false) return;
    list($zid, $e) = ms_topic_cat_ids(ms_topic_key(get_the_title($post_id), $c));
    if (!$zid) return;
    $cur = wp_get_post_categories($post_id);
    if (!in_array($zid, $cur, true)) wp_set_post_categories($post_id, array_merge($cur, array($zid)));
}
}

// 翻译发布时同步英文主题分类：挂在翻译完成后的分类赋值处由 ms_setlang 路径维护，
// 这里在 publish_post 兜底新建的 EN 版若只有 Curated Feeds，再补主题分类。
if (!function_exists('ms_en_trans_topic_cat')) {
add_action('publish_post', 'ms_en_trans_topic_cat', 40);
function ms_en_trans_topic_cat($post_id) {
    if (function_exists('pll_get_post_language') && pll_get_post_language($post_id) !== 'en') return;
    $c = get_post_field('post_content', $post_id);
    list($z, $eid) = ms_topic_cat_ids(ms_topic_key(get_the_title($post_id), $c));
    if (!$eid) return;
    $cur = wp_get_post_categories($post_id);
    if (!in_array($eid, $cur, true)) wp_set_post_categories($post_id, array_merge($cur, array($eid)));
}
}

// ?ms_recat=now：存量回填主题分类（zh 帖zh topic，en 帖en topic；每轮 60）
add_action('admin_init', function () {
    if (empty($_GET['ms_recat']) || !current_user_can('manage_options')) return;
    $limit = 60;
    $q = new WP_Query(array(
        'post_type' => 'post', 'post_status' => 'publish', 'posts_per_page' => -1,
        'fields' => 'ids', 'no_found_rows' => true,
    ));
    $done = 0; $scanned = 0; $remain = 0;
    foreach ($q->posts as $pid) {
        $scanned++;
        $lang = function_exists('pll_get_post_language') ? pll_get_post_language($pid) : 'en';
        $key = ms_topic_key(get_the_title($pid), get_post_field('post_content', $pid));
        list($zid, $eid) = ms_topic_cat_ids($key);
        $want = ($lang === 'zh') ? $zid : $eid;
        if (!$want) continue;
        $cur = wp_get_post_categories($pid);
        if (in_array($want, $cur, true)) continue;
        if ($done >= $limit) { $remain++; continue; }
        wp_set_post_categories($pid, array_merge($cur, array($want)));
        $done++;
    }
    wp_die('<pre>' . esc_html(json_encode(array('scanned' => $scanned, 'set' => $done, 'remain' => $remain))) . '</pre>');
});

// ── snippet id=9：SEO / OG / 分享 meta（已停用，留作 RM 备用实现）──
// og:image = 本地特色图（无则正文第一张图）；og:description = 摘要/正文前40词；
// meta description + canonical + shortlink + Article JSON-LD。
// Rank Math 跑完 Setup Wizard 后已接管全部 meta 输出 → 线上停用，防双份。
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

// ── snippet「pll-disable-browser-lang」v6（线上 id=23 激活中）────
// 修复：zh 浏览器/带 zh cookie 访客访问 / 被 Polylang 302 弹回 /zh/，
// 语言切换器永远到不了英文站（x-redirect-by: Polylang）。
// 根因：Polylang「Detect browser language」(polylang.browser=1) 用
// pll_language cookie + Accept-Language 决定首页首选语言并重定向。
// 注意两条弯路勿再走：① filter(option_polylang/pll_preferred_language) 拦不住——
// PLL 在 plugins_loaded 早期就读完 option 缓存，注册太晚；
// ② wp_redirect 返 false 会让 PLL 调完 exit 留下 200 空页面（首页白屏事故）。
// 正解：直接把 browser 选项在 DB 持久关掉（幂等，等价后台手动关闭）。
add_action('init', function () {
    $o = get_option('polylang');
    if (is_array($o) && !empty($o['browser'])) {
        $o['browser'] = 0;
        update_option('polylang', $o);
    }
}, 1);
unset($_COOKIE['pll_language']);
add_filter('pll_preferred_language', '__return_false');

// ── snippet「seo-extras」id=24（线上激活中）────────────────────
// 补 Rank Math 免费版不覆盖的点 + Rank Math 报告里的站点级失败项，全幂等。

// 1) 图片 alt 兜底：特色图/附件无 alt 时用附件 alt → 父文章标题
//    （RM 图片 SEO 属 Pro；报告 Image ALT 失败项的根因是 sideload 没写 alt）。
add_filter('wp_get_attachment_image_attributes', function ($attr, $attachment) {
    if (empty($attr['alt'])) {
        $t = get_post_meta($attachment->ID, '_wp_attachment_image_alt', true);
        if (!$t && $attachment->post_parent) $t = get_the_title($attachment->post_parent);
        if (!$t) $t = get_the_title($attachment->ID);
        $attr['alt'] = trim(wp_strip_all_tags($t));
    }
    return $attr;
}, 10, 2);

// 2) 插件自动更新（WP 无批量开关 → filter 全开）。
add_filter('auto_update_plugin', '__return_true');

// 3) 站点 tagline + RM 首页 title/description + LiteSpeed minify（幂等写）。
//    tagline 顺手修「MirrorSpeed VPN -」悬空标题；homepage_* 是
//    rank-math-options-titles 里首页「最新文章列表」模式的 meta 字段。
add_action('init', function () {
    $tag = 'VPN guides, updates & curated tech news';
    if (get_option('blogdescription') !== $tag) update_option('blogdescription', $tag);

    $t = get_option('rank-math-options-titles');
    if (is_array($t)) {
        $ch = false;
        $title = 'MirrorSpeed VPN Blog | VPN Guides & Curated Tech News';
        $desc  = 'MirrorSpeed VPN official blog - app updates, setup guides, and curated tech & AI news in English and Chinese.';
        if (($t['homepage_title'] ?? '') !== $title) { $t['homepage_title'] = $title; $ch = true; }
        if (($t['homepage_description'] ?? '') !== $desc) { $t['homepage_description'] = $desc; $ch = true; }
        if ($ch) update_option('rank-math-options-titles', $t);
    }

    if (!get_option('litespeed.conf.optm-css_min')) update_option('litespeed.conf.optm-css_min', 1);
    if (!get_option('litespeed.conf.optm-js_min'))  update_option('litespeed.conf.optm-js_min', 1);
}, 1);

// ── snippet「ms-content-cleaner-v2」id=27（线上激活中；v1 id=25、boost id=26 已停用）─
// 采集文清洗 + SEO 补强（ChatGPT 审查发现的问题修复）：
// P0a 剥 WPeMatico 模板带入正文的 feed-hidden-info 隐藏元数据块
//     （Feed地址/图标/采集任务ID——display:none 隐藏文本像 cloaking，必须删）；
//     保留 feed-author-source 归属链接块。
//     ★v1 坑：raw post_content 里该块是纯 \r\n 换行、无 <p> 标签（<p> 是 wpautop
//       渲染时才加的），锚「采集任务ID</p>」的正则全失配 → 存量一批没清。
//       v2 锚「采集任务ID」后 (</p>)? 可选 + div 深度感知兜底。
// P0b 正文内 <h1> 全降级 <h2>（主题已用 post title 当 H1，源文标题造成双 H1）。
// P1  wp_insert_post_data 导入即清洗 + 英文长标题自动生成短 slug（前6词，中文跳过）。
// P2a admin_init ?ms_boost_clean=1 管理员内联批处理（200篇/请求，&reset=1 重置游标；
//     绕开 wp-cron 锁竞争——WPeMatico 重任务让 curl 驱动基本跑不动）；
//     ms_content_clean_batch WP-Cron 30篇/tick 兜底。$wpdb 直写防重触发 id=17。
// P2b the_content 尾部追加双语 VPN CTA 内联块（ms-vpn-cta，引泛科技流量到产品）。

if (!function_exists('ms_clean_post_html')) {
function ms_clean_post_html($c) {
    if (!is_string($c) || $c === '') return $c;
    $c = preg_replace(
        '#<div[^>]*class=["\'][^"\']*feed-hidden-info[^"\']*["\'][^>]*>.*?采集任务ID[^<]*(?:</p>\s*)?</div>#is',
        '', $c);
    $c = preg_replace(
        '#<div[^>]*class=["\'][^"\']*feed-hidden-info[^"\']*["\'][^>]*>(?:(?!</?div\b)[\s\S]|<div[^>]*>(?:(?!</?div\b)[\s\S])*</div>)*</div>#is',
        '', $c);
    $c = preg_replace(
        '#<p[^>]*>(?:(?!</p>).)*(?:Feed地址|Feed简介|Feed图标|Feed收藏图标|采集任务ID|RSS\s*Feed).*?</p>#is',
        '', $c);
    $c = preg_replace('#<(/?)h1(\s[^>]*)?>#i', '<$1h2$2>', $c);
    return $c;
}}

add_filter('wp_insert_post_data', function ($data) {
    if (($data['post_type'] ?? '') !== 'post') return $data;
    $data['post_content'] = ms_clean_post_html($data['post_content']);
    if (empty($data['post_name']) && !empty($data['post_title'])) {
        $slug = sanitize_title($data['post_title']);
        $parts = explode('-', $slug);
        if (count($parts) >= 6) {
            $data['post_name'] = implode('-', array_slice($parts, 0, 6));
        }
    }
    return $data;
}, 20);

add_filter('the_content', function ($c) {
    if (!is_singular('post') || !in_the_loop() || !is_main_query()) return $c;
    $zh = function_exists('pll_current_language') && pll_current_language() === 'zh';
    if ($zh) {
        $h = '用 MirrorSpeed VPN 无障碍阅读更多技术资讯';
        $p = '镜像加速、隐私加密、全球节点。访问技术原文与海外资源更稳定。';
        $b = '了解 MirrorSpeed';
    } else {
        $h = 'Read more tech without borders — MirrorSpeed VPN';
        $p = 'Fast mirror acceleration, encrypted privacy, global nodes for stable access to overseas resources.';
        $b = 'Get MirrorSpeed';
    }
    $box = '<div class="ms-vpn-cta" style="margin:28px 0 8px;padding:18px 20px;border:1px solid #e2e8f0;border-left:4px solid #4f46e5;border-radius:8px;background:#f8faff;font-size:15px;line-height:1.6">'
         . '<strong style="display:block;font-size:16px;margin-bottom:6px">' . esc_html($h) . '</strong>'
         . '<span style="color:#475569">' . esc_html($p) . '</span><br/>'
         . '<a href="https://mirrorspeed.com" target="_blank" rel="noopener" style="display:inline-block;margin-top:10px;padding:8px 16px;background:#4f46e5;color:#fff;border-radius:6px;text-decoration:none;font-weight:600">' . esc_html($b) . '</a>'
         . '</div>';
    return $c . $box;
}, 99);

// 管理员内联批处理：/wp-admin/?ms_boost_clean=1（200篇/请求，&reset=1 重置游标）
add_action('admin_init', function () {
    if (empty($_GET['ms_boost_clean']) || !current_user_can('manage_options')) return;
    @set_time_limit(120);
    global $wpdb;
    if (!empty($_GET['reset'])) delete_option('ms_clean_cursor');
    $cursor = (int) get_option('ms_clean_cursor', 0);
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT ID, post_content FROM {$wpdb->posts}
         WHERE post_type='post' AND post_status IN ('publish','draft','future','private')
           AND ID > %d ORDER BY ID ASC LIMIT 200", $cursor));
    if (!$rows) { update_option('ms_clean_done', '1'); wp_die('CLEAN_DONE cursor=' . $cursor); }
    $max = $cursor; $changed = 0;
    foreach ($rows as $r) {
        $max = max($max, (int) $r->ID);
        $new = ms_clean_post_html($r->post_content);
        if ($new !== $r->post_content) {
            $wpdb->update($wpdb->posts, ['post_content' => $new], ['ID' => $r->ID]);
            clean_post_cache($r->ID);
            do_action('litespeed_purge_post', $r->ID);
            $changed++;
        }
    }
    update_option('ms_clean_cursor', $max);
    wp_die("batch done: cursor $cursor -> $max, changed $changed/" . count($rows));
});

add_action('init', function () {
    if (get_option('ms_clean_done') !== '1' && !wp_next_scheduled('ms_content_clean_batch')) {
        wp_schedule_single_event(time() + 10, 'ms_content_clean_batch');
    }
});
add_action('ms_content_clean_batch', function () {
    global $wpdb;
    $cursor = (int) get_option('ms_clean_cursor', 0);
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT ID, post_content FROM {$wpdb->posts}
         WHERE post_type='post' AND post_status IN ('publish','draft','future','private')
           AND ID > %d ORDER BY ID ASC LIMIT 30", $cursor));
    if (!$rows) { update_option('ms_clean_done', '1'); return; }
    $max = $cursor;
    foreach ($rows as $r) {
        $max = max($max, (int) $r->ID);
        $new = ms_clean_post_html($r->post_content);
        if ($new !== $r->post_content) {
            $wpdb->update($wpdb->posts, ['post_content' => $new], ['ID' => $r->ID]);
            clean_post_cache($r->ID);
            if (function_exists('do_action')) do_action('litespeed_purge_post', $r->ID);
        }
    }
    update_option('ms_clean_cursor', $max);
    wp_schedule_single_event(time() + 20, 'ms_content_clean_batch');
});

// ============================================================
// Code Snippets id=31: ms-edge-purge（发布文章 → LiteSpeed purge_all，连带清 hcdn 边缘缓存）
// 线上激活中。修：purge-post_f/h 只清本地 LSCache，hcdn edge 层只有 purge_all 能穿透
// → 首页曾滞留 33h 旧副本（Age: 120108）。10min 节流防导入批刷屏全清。
// ============================================================
add_action('transition_post_status', function ($new, $old, $post) {
    if ($new !== 'publish' || $old === 'publish') return;
    if (!is_object($post) || ($post->post_type ?? '') !== 'post') return;
    $last = (int) get_option('ms_edgepurge_ts', 0);
    if (time() - $last < 600) return;
    update_option('ms_edgepurge_ts', time(), false);
    if (function_exists('do_action')) do_action('litespeed_purge_all');
}, 10, 3);
