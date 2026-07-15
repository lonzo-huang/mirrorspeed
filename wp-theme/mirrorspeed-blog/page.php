<?php if (!defined('ABSPATH')) exit; get_header(); ?>

<?php while (have_posts()) : the_post(); ?>
<article class="article">
  <div class="wrap-narrow">
    <h1><span class="gradient-text"><?php the_title(); ?></span></h1>
    <?php if (has_post_thumbnail()) : ?>
      <?php the_post_thumbnail('large', array('class' => 'feat')); ?>
    <?php endif; ?>
    <div class="content">
      <?php the_content(); ?>
    </div>
  </div>
</article>
<?php endwhile; ?>

<?php get_footer(); ?>
