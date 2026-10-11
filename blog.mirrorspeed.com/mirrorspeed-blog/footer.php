<?php if (!defined('ABSPATH')) exit; ?>
</main>

<footer class="site-footer">
  <div class="wrap">
    <div class="links">
      <a href="https://www.mirrorspeed.com/"><?php echo get_locale() === 'zh_CN' ? '官网' : 'Home'; ?></a>
      <a href="https://www.mirrorspeed.com/download"><?php echo get_locale() === 'zh_CN' ? '下载' : 'Download'; ?></a>
      <a href="https://www.mirrorspeed.com/support"><?php echo get_locale() === 'zh_CN' ? '客服' : 'Support'; ?></a>
      <a href="<?php echo esc_url(home_url('/')); ?>"><?php echo get_locale() === 'zh_CN' ? '博客' : 'Blog'; ?></a>
    </div>
    <div class="copy">© <?php echo date('Y'); ?> MirrorSpeed</div>
  </div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
