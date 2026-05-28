-- ============================================================
-- Migration 008: Blog posts table for SEO content
-- ============================================================

CREATE TABLE IF NOT EXISTS public.blog_posts (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  slug         TEXT        NOT NULL UNIQUE,
  title        TEXT        NOT NULL,
  excerpt      TEXT,
  content      TEXT        NOT NULL,
  tags         TEXT[]      DEFAULT '{}',
  author       TEXT        DEFAULT 'MirrorSpeed',
  cover_url    TEXT,
  published    BOOLEAN     DEFAULT true,
  published_at TIMESTAMPTZ DEFAULT NOW(),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blog_posts_slug         ON public.blog_posts(slug);
CREATE INDEX IF NOT EXISTS idx_blog_posts_published_at ON public.blog_posts(published_at DESC) WHERE published = true;

ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;

-- Anyone can read published posts
CREATE POLICY "blog_posts_public_read"
  ON public.blog_posts FOR SELECT
  USING (published = true);

-- Only service role can write (bot uses service role key via API)
-- No INSERT/UPDATE/DELETE policy needed for anon — handled in API route
