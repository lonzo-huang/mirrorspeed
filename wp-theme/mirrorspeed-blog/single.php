<?php if (!defined('ABSPATH')) exit; get_header(); ?>

<?php while (have_posts()) : the_post(); ?>
<article class="article">
  <div class="wrap-narrow">
    <?php
      $cats = get_the_category();
      if (!empty($cats)) echo '<span class="kicker">// ' . esc_html($cats[0]->name) . '</span>';
    ?>
    <h1><span class="gradient-text"><?php the_title(); ?></span></h1>
    <div class="post-meta">
      <span><?php echo esc_html(get_the_date()); ?></span>
      <span>·</span>
      <span><?php the_author(); ?></span>
      <span>·</span>
      <span><?php echo mirrorspeed_read_time(); ?> <?php echo get_locale() === 'zh_CN' ? '分钟阅读' : 'min read'; ?></span>
    </div>

    <?php if (has_post_thumbnail()) : ?>
      <?php the_post_thumbnail('large', array('class' => 'feat')); ?>
    <?php endif; ?>

    <div class="content">
      <?php the_content(); ?>
    </div>

    <?php
      $tags = get_the_tags();
      if (!empty($tags)) {
        echo '<div class="tags">';
        foreach ($tags as $t) {
          echo '<a href="' . esc_url(get_tag_link($t->term_id)) . '">#' . esc_html($t->name) . '</a>';
        }
        echo '</div>';
      }
    ?>

    <div class="post-nav">
      <span><?php previous_post_link('%link', get_locale() === 'zh_CN' ? '← 上一篇' : '← Previous'); ?></span>
      <span><?php next_post_link('%link', get_locale() === 'zh_CN' ? '下一篇 →' : 'Next →'); ?></span>
    </div>
  </div>
</article>
<?php endwhile; ?>

<?php get_footer(); ?>
