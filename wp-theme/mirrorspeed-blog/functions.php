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
