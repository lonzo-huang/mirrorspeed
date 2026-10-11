<?php if (!defined('ABSPATH')) exit; ?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
  <meta charset="<?php bloginfo('charset'); ?>">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="<?php echo esc_url(home_url('/')); ?>">
      <span class="logo gradient-text">MirrorSpeed</span>
      <span class="tag"><?php echo get_locale() === 'zh_CN' ? '博客' : 'Blog'; ?></span>
    </a>
    <nav class="nav">
      <?php
        if (has_nav_menu('primary')) {
          wp_nav_menu(array(
            'theme_location' => 'primary',
            'container'      => false,
            'items_wrap'     => '%3$s',
            'depth'          => 1,
            'fallback_cb'    => false,
          ));
        }
      ?>
      <?php
        // 语言切换（需安装 Polylang 免费插件；未装则不显示，不报错）。
        if (function_exists('pll_the_languages')) {
          echo '<ul class="lang">';
          pll_the_languages(array('show_names' => 1, 'show_flags' => 0, 'hide_if_empty' => 0));
          echo '</ul>';
        }
      ?>
      <a class="back" href="https://www.mirrorspeed.com/"><?php echo get_locale() === 'zh_CN' ? '返回官网' : 'Main site'; ?></a>
    </nav>
  </div>
</header>

<main>
