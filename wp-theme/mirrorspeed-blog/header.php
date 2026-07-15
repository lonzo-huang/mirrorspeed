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
      <span class="tag"><?php echo function_exists('mb_strlen') && get_locale() === 'zh_CN' ? '博客' : 'Blog'; ?></span>
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
      <a class="back" href="https://www.mirrorspeed.com/"><?php echo get_locale() === 'zh_CN' ? '返回官网' : 'Main site'; ?></a>
    </nav>
  </div>
</header>

<main>
