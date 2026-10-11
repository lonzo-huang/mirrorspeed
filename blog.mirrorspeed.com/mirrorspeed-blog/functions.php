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
