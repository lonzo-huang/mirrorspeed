import { NextRequest, NextResponse } from 'next/server'
import { Groq } from 'groq-sdk'

export async function POST(req: NextRequest) {
  try {
    const apiKey = process.env.GROQ_API_KEY
    if (!apiKey) {
      console.error('[ai-rewrite] GROQ_API_KEY is missing')
      return NextResponse.json(
        { error: 'GROQ_API_KEY not configured in environment' },
        { status: 500 }
      )
    }

    const groq = new Groq({ apiKey })

    const { content, title, excerpt, sourceUrl } = await req.json()

    if (!content || typeof content !== 'string') {
      return NextResponse.json({ error: 'Content required' }, { status: 400 })
    }

    const prompt = `你是一个专业的技术内容编辑。我将给你一篇关于 VPN、网络加速、隐私保护的文章。

原始文章：
${content.slice(0, 3000)}

你的任务：
1. 用更清晰易懂的语言改写这篇文章（保留核心信息和观点）
2. 优化标题使其更吸引点击，包含相关关键词（如 VPN、速度、隐私、安全等）
3. 生成 100-150 字的摘要，适合博客列表页显示
4. 增加 SEO 友好的关键词和短语
5. 改进段落结构、分段清晰、便于阅读
6. 如果原文有来源 URL（${sourceUrl}），标注原文链接

请按以下 JSON 格式返回改写结果：
{
  "title": "改写后的标题",
  "excerpt": "100-150字的摘要",
  "content": "改写后的正文（保持 markdown 格式，注意段落分割清晰）",
  "keywords": ["关键词1", "关键词2", "关键词3"]
}`

    const message = await groq.chat.completions.create({
      model: 'llama-3.1-8b-instant',
      max_tokens: 2048,
      temperature: 0.7,
      messages: [
        {
          role: 'user',
          content: prompt,
        },
      ],
    })

    const responseText = message.choices[0]?.message?.content || ''

    if (!responseText) {
      return NextResponse.json({ error: 'Empty response from Groq' }, { status: 500 })
    }

    // 尝试解析 JSON
    let result: any = { content: responseText }
    try {
      const jsonMatch = responseText.match(/\{[\s\S]*\}/)
      if (jsonMatch) {
        result = JSON.parse(jsonMatch[0])
      }
    } catch (parseErr) {
      console.warn('[ai-rewrite] JSON parse failed, using raw text')
    }

    return NextResponse.json({
      success: true,
      data: {
        title: result.title || title || '优化后的标题',
        excerpt: result.excerpt || excerpt || '',
        content: result.content || responseText,
        keywords: result.keywords || [],
        sourceUrl: sourceUrl || null,
      },
    })
  } catch (error: any) {
    console.error('[ai-rewrite] Error:', error)
    return NextResponse.json(
      {
        error: error.message || 'Failed to rewrite content with Groq API',
        details: error.error?.message,
      },
      { status: 500 }
    )
  }
}
