-- Add language field to blog_posts for multi-language support
ALTER TABLE blog_posts
  ADD COLUMN IF NOT EXISTS language text;

-- Backfill existing posts based on slug pattern BEFORE setting NOT NULL
-- Posts with -cn suffix are Chinese, others are English
UPDATE blog_posts
SET language = CASE
  WHEN slug LIKE '%-cn' THEN 'zh'
  ELSE 'en'
END
WHERE language IS NULL;

-- Now set the constraint
ALTER TABLE blog_posts
  ALTER COLUMN language SET NOT NULL,
  ALTER COLUMN language SET DEFAULT 'en';

-- Create index for faster filtering by language
CREATE INDEX IF NOT EXISTS blog_posts_language_idx ON blog_posts(language);
CREATE INDEX IF NOT EXISTS blog_posts_language_published_idx ON blog_posts(language, published);
