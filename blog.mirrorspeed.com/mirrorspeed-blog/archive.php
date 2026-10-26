<?php if (!defined('ABSPATH')) exit; get_header();

$zh = (get_locale() === 'zh_CN');

// 归档分组标题：年/月/日
$title = '';
if (is_year())  $title = sprintf($zh ? '%s年归档' : 'Year: %s', get_the_date('Y'));
elseif (is_month()) $title = sprintf($zh ? '%s归档' : 'Month: %s', get_the_date($zh ? 'Y年n月' : 'F Y'));
elseif (is_day())   $title = sprintf($zh ? '%s归档' : 'Day: %s', get_the_date());
else                $title = $zh ? '归档' : 'Archives';
?>

<section class="wrap">
  <div class="intro">
    <span class="kicker">// <?php echo $zh ? '归档' : 'Archives'; ?></span>
    <h1><span class="gradient-text"><?php echo esc_html($title); ?></span></h1>
    <p><?php echo $zh ? '按时间浏览全部文章。' : 'Browse all posts by date.'; ?></p>
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
              $cat = mirrorspeed_pick_cat(get_the_category());
              if ($cat) echo '<span class="chip">' . esc_html($cat->name) . '</span>';
            ?>
            <h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
            <p class="excerpt"><?php echo esc_html(wp_trim_words(get_the_excerpt(), 22, '…')); ?></p>
            <div class="meta">
              <time datetime="<?php echo esc_attr(get_the_date('c')); ?>"><?php echo esc_html(get_the_date()); ?></time>
              <a class="more" href="<?php the_permalink(); ?>"><?php echo $zh ? '阅读全文 →' : 'Read →'; ?></a>
            </div>
          </div>
        </article>
      <?php endwhile; ?>
    </div>

    <div class="pagination">
      <?php echo paginate_links(array('mid_size' => 1, 'prev_text' => '‹', 'next_text' => '›')); ?>
    </div>
  <?php else : ?>
    <p class="empty"><?php echo $zh ? '该时间段暂无文章。' : 'No posts in this period.'; ?></p>
  <?php endif; ?>

  <!-- 按月目录：仅列有文章的月份 -->
  <div class="archive-index">
    <h2 class="archive-index__title"><?php echo $zh ? '按月归档' : 'By month'; ?></h2>
    <ul class="archive-index__list">
      <?php wp_get_archives(array('type' => 'monthly', 'show_post_count' => true, 'limit' => 36)); ?>
    </ul>
  </div>
</section>

<?php get_footer(); ?>
