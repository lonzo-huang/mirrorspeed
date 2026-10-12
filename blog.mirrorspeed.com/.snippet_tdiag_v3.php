// ms-tdiag v3: 翻译管线诊断/手动推进/Groq 探测（管理员专用）
// /wp-admin/?ms_t_diag=<post_id>   → 该文章的翻译状态 JSON
// /wp-admin/?ms_t_kick=<post_id>   → 直接同步跑一次 ms_translate_post_handler（绕 cron）
// /wp-admin/?ms_t_probe=<post_id>  → 把该文章 chunk[done] 原样发 Groq，返回真实 HTTP 码+错误体
add_action('admin_init', function () {
    if (!current_user_can('manage_options')) return;
    if (!empty($_GET['ms_t_diag'])) {
        $id = (int) $_GET['ms_t_diag'];
        $st = get_post_meta($id, '_ms_t_state', true);
        $next = wp_next_scheduled('ms_translate_post', array($id));
        $en = function_exists('pll_get_post') ? pll_get_post($id, 'en') : 0;
        $out = array(
            'id'          => $id,
            'post_status' => get_post_status($id),
            'has_weixin'  => strpos((string)get_post_field('post_content', $id), 'mp.weixin.qq.com') !== false,
            't_state'     => is_array($st) ? array(
                'title'  => $st['title'] ?? '',
                'chunks' => count($st['chunks'] ?? array()),
                'done'   => count($st['done'] ?? array()),
            ) : $st,
            'next_tick'   => $next ? gmdate('c', $next) . ' (in ' . ($next - time()) . 's)' : false,
            'en_link'     => $en,
            'en_exists'   => $en ? (bool) get_post($en) : false,
        );
        wp_die('<pre>' . esc_html(wp_json_encode($out, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) . '</pre>');
    }
    if (!empty($_GET['ms_t_kick'])) {
        $id = (int) $_GET['ms_t_kick'];
        if (!function_exists('ms_translate_post_handler')) wp_die('handler missing');
        ms_translate_post_handler($id);
        wp_die('kicked ' . $id . ' done=' . count((array)(get_post_meta($id,'_ms_t_state',true)['done'] ?? array())));
    }
    if (!empty($_GET['ms_t_probe'])) {
        $id = (int) $_GET['ms_t_probe'];
        $st = get_post_meta($id, '_ms_t_state', true);
        $chunk = (is_array($st) && !empty($st['chunks']))
            ? $st['chunks'][count($st['done'] ?? array())]
            : 'Say OK';
        $resp = wp_remote_post('https://api.groq.com/openai/v1/chat/completions', array(
            'timeout' => 90,
            'headers' => array('Authorization' => 'Bearer ' . MS_GROQ_API_KEY, 'Content-Type' => 'application/json'),
            'body'    => wp_json_encode(array(
                'model'    => MS_GROQ_MODEL,
                'messages' => array(
                    array('role' => 'system', 'content' => 'You are a professional Chinese-to-English translator for a tech blog. Translate the HTML below to natural English. Keep ALL HTML tags, attributes, URLs, class names and placeholders EXACTLY as-is; translate only inner text. Output ONLY the translated HTML, no commentary, no markdown fences.'),
                    array('role' => 'user',   'content' => $chunk),
                ),
                'temperature' => 0.3,
                'max_tokens'  => 4096,
                'reasoning_effort' => 'low',
            )),
        ));
        if (is_wp_error($resp)) wp_die('WP_ERROR: ' . esc_html($resp->get_error_message()));
        wp_die('chunk_bytes=' . strlen($chunk) . "\nHTTP " . wp_remote_retrieve_response_code($resp) . "\n" . esc_html(substr(wp_remote_retrieve_body($resp), 0, 800)));
    }
});
