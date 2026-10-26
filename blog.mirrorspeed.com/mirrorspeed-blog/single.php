<?php if (!defined('ABSPATH')) exit; get_header(); ?>

<?php while (have_posts()) : the_post(); ?>
<article class="article">
  <div class="wrap-narrow">
    <?php
      $cat = mirrorspeed_pick_cat(get_the_category());
      if ($cat) echo '<span class="kicker">// ' . esc_html($cat->name) . '</span>';
    ?>
    <h1><span class="gradient-text"><?php the_title(); ?></span></h1>
    <div class="post-meta">
      <time datetime="<?php echo esc_attr(get_the_date('c')); ?>"><?php echo esc_html(get_the_date()); ?></time>
      <span>·</span>
      <span><?php the_author(); ?></span>
      <span>·</span>
      <span><?php echo mirrorspeed_read_time(); ?> <?php echo get_locale() === 'zh_CN' ? '分钟阅读' : 'min read'; ?></span>
      <span>·</span>
      <span class="views" data-ms-view="<?php echo get_the_ID(); ?>"><?php
        $v = (int) get_post_meta(get_the_ID(), '_ms_views', true);
        echo $v . ' ' . (get_locale() === 'zh_CN' ? '阅读' : 'views');
      ?></span>
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

<script>
(function () {
  var el = document.querySelector('[data-ms-view]');
  if (!el) return;
  var id = el.getAttribute('data-ms-view');
  fetch('<?php echo esc_js(rest_url('ms/v1/view/')); ?>' + id, { method: 'POST', credentials: 'omit' })
    .then(function (r) { return r.json(); })
    .then(function (d) { if (d && typeof d.views === 'number') el.firstChild.nodeValue = d.views + ' '; })
    .catch(function () {});
})();
</script>
<?php endwhile; ?>

<?php get_footer(); ?>
