# 运营公告（App 全局通告）操作手册

给 App 首页下发一条全局公告（维护通知、故障恢复、活动等）。运营手动改，无需发版。

## 原理

- 存储：Supabase 表 `app_config`，`key = 'announcement'`，`value` 是一段 **JSON 字符串**（`value` 列是 TEXT）。
- App 通过 `GET https://www.mirrorspeed.com/api/announcement` 拉取（客户端 `ApiService.fetchAnnouncement()`）。
- 该接口有 **60 秒 CDN 缓存**（`s-maxage=60`），改完最多 1 分钟内端上生效。
- ⚠️ 该接口跑在 **Vercel** 上：Vercel 若暂停/宕机，App 拉不到公告。Supabase 改动本身不受影响，等 Vercel 恢复即可显示。

## JSON 字段

```json
{
  "id":     "2026-07-12-recovery",   // 唯一 id，换新公告务必换 id（避免被端上「已读/已忽略」吞掉）
  "title":  "服务已恢复",             // 标题
  "body":   "公告正文……",            // 正文
  "level":  "info",                  // info | warning | critical（端上样式/颜色）
  "active": true,                    // false 或整条不存在 → 不显示
  "url":    null                     // 可选：点击跳转链接，无则 null
}
```

- `active=false` 或 `title`/`body` 全空 → 接口返回 `{announcement:null}`，端上不显示。

## 发布 / 更新一条公告

在 **Supabase → SQL Editor** 执行（改 id/title/body/level 即可复用）：

```sql
INSERT INTO public.app_config (key, value)
VALUES (
  'announcement',
  '{"id":"2026-07-12-recovery","title":"服务已恢复","body":"尊敬的用户，由于用户量暴涨超过了我们的服务器限额导致业务中断，现已扩展云服务器资源，业务已恢复，感谢您的理解。","level":"info","active":true,"url":null}'
)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value, updated_at = NOW();
```

注意：整段 JSON 用**单引号**包住；正文里**不要出现单引号**（如需要请写成 `''` 两个单引号转义）。中文无需转义。

## 撤下公告

```sql
-- 方式1：设为不活跃（保留记录，便于以后翻查/复用）
UPDATE public.app_config
  SET value = REPLACE(value, '"active":true', '"active":false'), updated_at = NOW()
WHERE key = 'announcement';

-- 方式2：直接删除
-- DELETE FROM public.app_config WHERE key = 'announcement';
```

## 查看当前公告

```sql
SELECT value FROM public.app_config WHERE key = 'announcement';
```

或直接访问 `https://www.mirrorspeed.com/api/announcement`（Vercel 在线时）。

## 相关代码

- 接口：`portal/src/app/api/announcement/route.ts`
- 客户端拉取：`client/lib/services/api_service.dart` → `fetchAnnouncement()`
