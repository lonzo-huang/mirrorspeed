<?php if (!defined('ABSPATH')) exit; get_header(); ?>

<section class="wrap">
  <div class="intro">
    <span class="kicker">// <?php echo get_locale() === 'zh_CN' ? '博客' : 'Blog'; ?></span>
    <h1><span class="gradient-text"><?php
      if (is_home() || is_front_page()) { echo get_locale() === 'zh_CN' ? '最新文章' : 'Latest Articles'; }
      elseif (is_category() || is_tag() || is_archive()) { single_term_title(); the_archive_title(); }
      elseif (is_search()) { printf(get_locale() === 'zh_CN' ? '搜索：%s' : 'Search: %s', get_search_query()); }
      else { echo esc_html(get_the_title()); }
    ?></span></h1>
    <p><?php echo get_locale() === 'zh_CN'
      ? '关于加速、连接、隐私与网络的实用文章与教程。'
      : 'Practical guides on speed, connectivity, privacy and networking.'; ?></p>
  </div>

  <?php if (have_posts()) : ?>
    <div class="grid">
      <?php while (have_posts()) : the_post(); ?>
        <article class="card">
          <a class="thumb" href="<?php the_permalink(); ?>">
            <?php if (has_post_thumbnail()) the_post_thumbnail('large'); ?>
          </a>
          <div class="body">
            <?php
              $cats = get_the_category();
              if (!empty($cats)) echo '<span class="chip">' . esc_html($cats[0]->name) . '</span>';
            ?>
            <h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
            <p class="excerpt"><?php echo esc_html(wp_trim_words(get_the_excerpt(), 22, '…')); ?></p>
            <div class="meta">
              <span><?php echo esc_html(get_the_date()); ?></span>
              <a class="more" href="<?php the_permalink(); ?>"><?php echo get_locale() === 'zh_CN' ? '阅读全文 →' : 'Read →'; ?></a>
            </div>
          </div>
        </article>
      <?php endwhile; ?>
    </div>

    <div class="pagination">
      <?php echo paginate_links(array('mid_size' => 1, 'prev_text' => '‹', 'next_text' => '›')); ?>
    </div>
  <?php else : ?>
    <p class="empty"><?php echo get_locale() === 'zh_CN' ? '暂无文章。' : 'No posts yet.'; ?></p>
  <?php endif; ?>
</section>

<?php get_footer(); ?>
