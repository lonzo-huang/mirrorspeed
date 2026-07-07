import { NextRequest, NextResponse } from 'next/server'
import * as cheerio from 'cheerio'

export async function POST(req: NextRequest) {
  try {
    const { url } = await req.json()

    if (!url || typeof url !== 'string') {
      return NextResponse.json({ error: 'URL required' }, { status: 400 })
    }

    // 爬取网页
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    })

    if (!response.ok) {
      return NextResponse.json({ error: `Failed to fetch URL: ${response.status}` }, { status: 400 })
    }

    const html = await response.text()
    const $ = cheerio.load(html)

    // 提取标题
    const title =
      $('meta[property="og:title"]').attr('content') ||
      $('meta[name="title"]').attr('content') ||
      $('h1').first().text() ||
      $('title').text() ||
      ''

    // 提取摘要
    const excerpt =
      $('meta[property="og:description"]').attr('content') ||
      $('meta[name="description"]').attr('content') ||
      $('p').first().text() ||
      ''

    // 提取正文（移除脚本、样式、导航等）
    const $body = $('article, main, [role="main"], .content, .post, .entry')
    let content = $body.length > 0 ? $body.html() : $('body').html()

    if (!content) {
      return NextResponse.json({ error: 'Could not extract content' }, { status: 400 })
    }

    // 清理 HTML（移除脚本、样式、评论等）
    const $clean = cheerio.load(content)
    $clean('script, style, nav, footer, .comments, .sidebar, .ads, [class*="cookie"]').remove()
    const cleanContent = $clean.text().trim()

    return NextResponse.json({
      success: true,
      data: {
        title: title.trim(),
        excerpt: excerpt.trim().slice(0, 200),
        content: cleanContent.slice(0, 5000), // 限制字数
        sourceUrl: url,
      },
    })
  } catch (error: any) {
    return NextResponse.json(
      { error: error.message || 'Failed to import URL' },
      { status: 500 }
    )
  }
}
