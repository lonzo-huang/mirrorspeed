'use client'

import { useEffect, useState } from 'react'

interface PostRow {
  slug: string
  title: string
  published: boolean
  published_at: string
  updated_at?: string
}

interface PostForm {
  slug: string
  title: string
  excerpt: string
  content: string
  tags: string
  author: string
  coverUrl: string
  published: boolean
  language: 'en' | 'zh'
  sourceUrl?: string
}

const empty: PostForm = {
  slug: '', title: '', excerpt: '', content: '', tags: '',
  author: 'MirrorSpeed', coverUrl: '', published: true, language: 'en', sourceUrl: '',
}

// Slug 生成：将中文转换为英文音译，保留 a-z0-9-
function slugify(s: string) {
  // 中文汉字转音译映射（常用词）
  const zhMap: Record<string, string> = {
    'vpn': 'vpn', '原理': 'principles', '及': 'and', '实现': 'implementation',
    '之': 'of', 'tcp': 'tcp', '还是': 'vs', 'udp': 'udp', '传输': 'transport',
    '协议': 'protocol', '的': 'of', '选择': 'choice', '与': 'and', '权衡': 'tradeoff',
    '为什么': 'why', '推荐': 'recommend', '跨境': 'cross-border', '网速': 'speed',
    '实测': 'benchmark', '对比': 'comparison', '速度': 'speed', '天花板': 'ceiling',
    '带宽': 'bandwidth', '网络': 'network', '高延迟': 'high-latency', '游戏': 'gaming',
    '流媒体': 'streaming', '加速': 'acceleration', '镜速': 'mirrorspeed',
  }

  let result = s.toLowerCase().trim()

  // 替换已知的中文词组
  for (const [cn, en] of Object.entries(zhMap)) {
    result = result.replace(new RegExp(cn, 'g'), en)
  }

  // 移除所有非ASCII字符（剩余的中文字符转为连字符）
  result = result.replace(/[^\w]+/g, '-')
  result = result.replace(/(^-|-$)/g, '')

  // 限制长度
  return result.slice(0, 80)
}

export function BlogEditor() {
  const [posts, setPosts] = useState<PostRow[]>([])
  const [form, setForm]   = useState({ ...empty })
  const [msg, setMsg]     = useState<string | null>(null)
  const [busy, setBusy]   = useState(false)
  const [slugLocked, setSlugLocked] = useState(false)  // 编辑已有文章时锁 slug
  const [aiMode, setAiMode] = useState<'rewrite' | 'polish' | 'translate'>('rewrite')

  async function load() {
    const res = await fetch('/api/admin/blog', { cache: 'no-store' })
    const data = await res.json()
    if (res.ok) setPosts(data.posts ?? [])
  }
  useEffect(() => { load() }, [])

  // 从列表点“编辑”：拉整篇（含正文）填表
  async function editFull(slug: string) {
    setBusy(true); setMsg(null)
    try {
      const r = await fetch(`/api/admin/blog?slug=${encodeURIComponent(slug)}`, { cache: 'no-store' })
      if (r.ok) {
        const d = await r.json()
        const p = d.post
        setForm({
          slug: p.slug, title: p.title, excerpt: p.excerpt ?? '',
          content: p.content ?? '', tags: (p.tags ?? []).join(', '),
          author: p.author ?? 'MirrorSpeed', coverUrl: p.cover_url ?? '',
          published: p.published ?? true, language: p.language ?? 'en',
          sourceUrl: p.source_url ?? '',
        })
        setSlugLocked(true)
        window.scrollTo({ top: 0, behavior: 'smooth' })
      }
    } finally { setBusy(false) }
  }

  function newPost() {
    setForm({ ...empty }); setSlugLocked(false); setMsg(null)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  async function importDocx(file: File) {
    setMsg('正在解析 Word…')
    try {
      const mod: any = await import('mammoth/mammoth.browser')
      const mammoth = mod.default ?? mod
      const arrayBuffer = await file.arrayBuffer()
      const result = await mammoth.convertToHtml({ arrayBuffer })
      setForm(f => ({ ...f, content: (f.content ? f.content + '\n' : '') + result.value }))
      setMsg('Word 导入成功，已填入正文（可再编辑）')
    } catch (e: any) {
      setMsg('Word 解析失败：' + (e?.message ?? e))
    }
  }

  async function save() {
    setBusy(true); setMsg(null)
    const slug = form.slug.trim() || slugify(form.title)
    const body = {
      slug, title: form.title, excerpt: form.excerpt, content: form.content,
      tags: form.tags.split(',').map(t => t.trim()).filter(Boolean),
      author: form.author, coverUrl: form.coverUrl || null, published: form.published,
      language: form.language,
      sourceUrl: form.sourceUrl || null,
    }
    const res = await fetch('/api/admin/blog', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    })
    const data = await res.json()
    setBusy(false)
    if (res.ok) {
      setMsg(`已保存：/blog/${data.post.slug}`)
      setSlugLocked(true); setForm(f => ({ ...f, slug }))
      load()
    } else {
      setMsg('保存失败：' + (data.error ?? res.status))
    }
  }

  async function importFromUrl() {
    const url = prompt('输入文章 URL:')
    if (!url) return
    setMsg('正在导入...')
    setBusy(true)
    try {
      const res = await fetch('/api/blog/import-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url }),
      })
      const data = await res.json()
      if (res.ok) {
        setForm(f => ({
          ...f,
          title: data.data.title || f.title,
          excerpt: data.data.excerpt || f.excerpt,
          content: data.data.content || f.content,
          sourceUrl: data.data.sourceUrl,
        }))
        setMsg('✅ 导入成功，点"AI 改写"优化内容')
      } else {
        setMsg('❌ 导入失败：' + (data.error || res.status))
      }
    } catch (e) {
      setMsg('❌ 导入错误：' + String(e))
    } finally {
      setBusy(false)
    }
  }

  async function aiRewrite() {
    if (!form.content) { setMsg('❌ 请先输入或导入内容'); return }
    const modeLabel = aiMode === 'rewrite' ? '改写' : aiMode === 'polish' ? '润色' : '翻译'
    setMsg(`✨ AI ${modeLabel}中...`)
    setBusy(true)
    try {
      const res = await fetch('/api/blog/ai-rewrite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          content: form.content,
          title: form.title,
          excerpt: form.excerpt,
          sourceUrl: form.sourceUrl,
          mode: aiMode,
        }),
      })
      const data = await res.json()
      if (res.ok) {
        setForm(f => ({
          ...f,
          title: data.data.title || f.title,
          excerpt: data.data.excerpt || f.excerpt,
          content: data.data.content || f.content,
        }))
        setMsg(`✅ AI ${modeLabel}完成！可继续编辑后保存`)
      } else {
        setMsg(`❌ ${modeLabel}失败：` + (data.error || res.status))
      }
    } catch (e) {
      setMsg(`❌ ${modeLabel}错误：` + String(e))
    } finally {
      setBusy(false)
    }
  }

  async function remove(slug: string) {
    if (!confirm(`删除文章 ${slug}？此操作不可恢复。`)) return
    const res = await fetch(`/api/admin/blog?slug=${encodeURIComponent(slug)}`, { method: 'DELETE' })
    if (res.ok) { setMsg(`已删除 ${slug}`); load(); if (form.slug === slug) newPost() }
    else setMsg('删除失败')
  }

  const input = 'w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-app-primary placeholder:text-app-muted focus:outline-none focus:border-[var(--accent-cyan)]'

  return (
    <div className="max-w-3xl mx-auto px-6 py-10">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">博客管理</h1>
        <a href="/blog" className="text-sm text-accent-cyan" target="_blank">查看博客 ↗</a>
      </div>

      {msg && <div className="mb-4 rounded-lg bg-accent-cyan/10 border border-accent-cyan/30 px-4 py-2 text-sm text-accent-cyan">{msg}</div>}

      {/* 编辑表单 */}
      <div className="glass-panel rounded-2xl p-5 space-y-3 mb-8">
        <div className="flex items-center justify-between">
          <span className="text-sm font-semibold">{slugLocked ? `编辑：${form.slug}` : '新建文章'}</span>
          <button onClick={newPost} className="text-xs text-app-muted hover:text-app-primary">+ 新建</button>
        </div>

        <input className={input} placeholder="标题 *" value={form.title}
          onChange={e => setForm(f => ({ ...f, title: e.target.value }))} />

        <div className="grid grid-cols-2 gap-3">
          <select className={input} value={form.language}
            onChange={e => setForm(f => ({ ...f, language: e.target.value }))}>
            <option value="en">English 英文</option>
            <option value="zh">中文 Chinese</option>
          </select>
          <input className={input} placeholder="Slug（留空自动生成，如 udp-vs-tcp-speed）" value={form.slug}
            disabled={slugLocked}
            onChange={e => setForm(f => ({ ...f, slug: e.target.value }))} />
        </div>
        {slugLocked && <p className="text-[11px] text-app-muted">slug 已锁定（编辑已有文章）。要改 URL 请新建一篇。</p>}

        <input className={input} placeholder="摘要（列表页显示）" value={form.excerpt}
          onChange={e => setForm(f => ({ ...f, excerpt: e.target.value }))} />

        <div className="flex items-center gap-2 flex-wrap">
          <label className="text-xs text-app-muted shrink-0">导入 Word：</label>
          <input type="file" accept=".docx" className="text-xs"
            onChange={e => { const f = e.target.files?.[0]; if (f) importDocx(f) }} />
          <button type="button" onClick={importFromUrl} disabled={busy}
            className="ml-auto text-xs px-2 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded disabled:opacity-50">
            📥 从 URL 导入
          </button>
          <div className="flex items-center gap-1">
            <select value={aiMode} onChange={e => setAiMode(e.target.value as any)}
              className="text-xs px-2 py-1 bg-white/5 border border-white/10 rounded text-app-primary">
              <option value="rewrite">✨ AI 改写</option>
              <option value="polish">✏️ AI 润色</option>
              <option value="translate">🌐 AI 翻译</option>
            </select>
            <button type="button" onClick={aiRewrite} disabled={busy || !form.content}
              className="text-xs px-2 py-1 bg-purple-600 hover:bg-purple-700 text-white rounded disabled:opacity-50">
              执行
            </button>
          </div>
        </div>

        <textarea className={input + ' font-mono text-xs'} rows={16}
          placeholder="正文（支持 HTML 或纯文本/Markdown；Word 导入会填入 HTML）"
          value={form.content}
          onChange={e => setForm(f => ({ ...f, content: e.target.value }))} />

        <div className="grid grid-cols-2 gap-3">
          <input className={input} placeholder="标签（逗号分隔）" value={form.tags}
            onChange={e => setForm(f => ({ ...f, tags: e.target.value }))} />
          <input className={input} placeholder="作者" value={form.author}
            onChange={e => setForm(f => ({ ...f, author: e.target.value }))} />
        </div>
        <input className={input} placeholder="封面图 URL（可选，如 /og-cn.png 或完整链接）" value={form.coverUrl}
          onChange={e => setForm(f => ({ ...f, coverUrl: e.target.value }))} />

        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={form.published}
            onChange={e => setForm(f => ({ ...f, published: e.target.checked }))} />
          发布（取消勾选=存为草稿，不对外显示）
        </label>

        <button onClick={save} disabled={busy || !form.title || !form.content}
          className="w-full py-2.5 rounded-lg font-bold disabled:opacity-50"
          style={{ background: 'linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)', color: '#000' }}>
          {busy ? '保存中…' : '保存并发布'}
        </button>
      </div>

      {/* 已有文章列表 */}
      <h2 className="text-sm font-semibold text-app-secondary mb-3">全部文章（{posts.length}）</h2>
      <div className="space-y-2">
        {posts.map(p => (
          <div key={p.slug} className="glass-panel rounded-xl px-4 py-3 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium truncate">{p.title}</div>
              <div className="text-[11px] text-app-muted truncate">
                /{p.slug} · {p.published ? '已发布' : '草稿'} · {new Date(p.published_at).toLocaleDateString()}
              </div>
            </div>
            <button onClick={() => editFull(p.slug)} className="text-xs text-accent-cyan shrink-0">编辑</button>
            <button onClick={() => remove(p.slug)} className="text-xs text-red-400 shrink-0">删除</button>
          </div>
        ))}
      </div>
    </div>
  )
}
