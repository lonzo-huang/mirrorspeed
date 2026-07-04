-- Add language field to blog_posts for multi-language support
ALTER TABLE blog_posts
  ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'en';

-- Create index for faster filtering by language
CREATE INDEX IF NOT EXISTS blog_posts_language_idx ON blog_posts(language);
CREATE INDEX IF NOT EXISTS blog_posts_language_published_idx ON blog_posts(language, published);

-- Backfill existing posts based on slug pattern
-- Posts with -cn suffix are Chinese, others are English
UPDATE blog_posts
SET language = 'zh'
WHERE slug LIKE '%-cn' AND language = 'en';
