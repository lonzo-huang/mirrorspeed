import { NextRequest, NextResponse } from 'next/server'
import { Groq } from 'groq-sdk'

const groq = new Groq({
  apiKey: process.env.GROQ_API_KEY || '',
})

export async function POST(req: NextRequest) {
  try {
    if (!process.env.GROQ_API_KEY) {
      return NextResponse.json({ error: 'GROQ_API_KEY not configured' }, { status: 500 })
    }

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
5. 改进段落结构和可读性
6. 如果原文有来源 URL，标注原文链接

请按以下 JSON 格式返回改写结果：
{
  "title": "改写后的标题",
  "excerpt": "100-150字的摘要",
  "content": "改写后的正文（保持 markdown 格式）",
  "keywords": ["关键词1", "关键词2", "关键词3"]
}`

    const message = await groq.messages.create({
      model: 'mixtral-8x7b-32768',
      max_tokens: 2048,
      messages: [
        {
          role: 'user',
          content: prompt,
        },
      ],
    })

    const responseText =
      message.content[0].type === 'text' ? message.content[0].text : ''

    // 尝试解析 JSON
    let result
    try {
      const jsonMatch = responseText.match(/\{[\s\S]*\}/)
      result = jsonMatch ? JSON.parse(jsonMatch[0]) : { content: responseText }
    } catch {
      result = { content: responseText }
    }

    return NextResponse.json({
      success: true,
      data: {
        title: result.title || title || '新标题',
        excerpt: result.excerpt || excerpt || '',
        content: result.content || responseText,
        keywords: result.keywords || [],
        sourceUrl: sourceUrl || null,
      },
    })
  } catch (error: any) {
    return NextResponse.json(
      { error: error.message || 'Failed to rewrite content' },
      { status: 500 }
    )
  }
}
