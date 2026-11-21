'use client'

import { useCallback, useEffect, useState } from 'react'

export default function RoutingSettings() {
  const [text, setText]         = useState('')
  const [isDefault, setDefault] = useState(true)
  const [loading, setLoading]   = useState(true)
  const [saving, setSaving]     = useState(false)
  const [msg, setMsg]           = useState<{ kind: 'ok' | 'err'; text: string } | null>(null)

  const apply = (domains: string[], isDef: boolean) => {
    setText(domains.join('\n'))
    setDefault(isDef)
  }

  const load = useCallback(async () => {
    setLoading(true); setMsg(null)
    try {
      const res = await fetch('/api/admin/force-proxy-domains', { cache: 'no-store' })
      const data = await res.json()
      if (!res.ok) { setMsg({ kind: 'err', text: data?.error ?? `HTTP ${res.status}` }); return }
      apply(data.domains ?? [], !!data.isDefault)
    } catch (e: any) {
      setMsg({ kind: 'err', text: String(e?.message ?? e) })
    } finally { setLoading(false) }
  }, [])

  useEffect(() => { load() }, [load])

  const save = async () => {
    setSaving(true); setMsg(null)
    try {
      const domains = text.split(/[\s,]+/).map(s => s.trim()).filter(Boolean)
      const res = await fetch('/api/admin/force-proxy-domains', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ domains }),
      })
      const data = await res.json()
      if (!res.ok) { setMsg({ kind: 'err', text: data?.error ?? `HTTP ${res.status}` }); return }
      apply(data.domains ?? [], false)
      setMsg({ kind: 'ok', text: `已保存 ${data.domains?.length ?? 0} 个域名，客户端下次刷新配置即生效` })
    } catch (e: any) {
      setMsg({ kind: 'err', text: String(e?.message ?? e) })
    } finally { setSaving(false) }
  }

  const resetDefault = async () => {
    if (!confirm('确定恢复内置默认列表？会删除当前自定义配置。')) return
    setSaving(true); setMsg(null)
    try {
      const res = await fetch('/api/admin/force-proxy-domains', { method: 'DELETE' })
      const data = await res.json()
      if (!res.ok) { setMsg({ kind: 'err', text: data?.error ?? `HTTP ${res.status}` }); return }
      apply(data.domains ?? [], true)
      setMsg({ kind: 'ok', text: '已恢复内置默认列表' })
    } catch (e: any) {
      setMsg({ kind: 'err', text: String(e?.message ?? e) })
    } finally { setSaving(false) }
  }

  const count = text.split(/[\s,]+/).map(s => s.trim()).filter(Boolean).length

  return (
    <div className="ms-landing min-h-screen bg-app text-app-primary px-5 py-8 md:px-10 relative overflow-hidden">
      <div className="absolute inset-0 grid-bg opacity-20 pointer-events-none" />
      <div className="absolute -top-32 right-1/4 h-96 w-96 rounded-full pointer-events-none" style={{ background: 'var(--accent-cyan-glow)', filter: 'blur(140px)', opacity: 0.15 }} />
      <div className="relative mx-auto max-w-3xl">
        <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="font-heading text-3xl font-black tracking-tighter">
              <span className="text-gradient-cyan">券商强制代理域名</span>
            </h1>
            <p className="text-sm text-app-muted mt-1">
              这些域名在智能模式下也强制走节点，避免老虎/富途等中资券商连到中国 IP 被判「国内网络」。
            </p>
          </div>
          <a href="/admin" className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors">← 返回后台</a>
        </header>

        <section className="glass-panel rounded-2xl p-5 ring-1 ring-white/5">
          <div className="mb-3 flex items-center justify-between gap-3">
            <span className={`rounded-full px-2.5 py-1 text-xs font-medium ring-1 ${
              isDefault ? 'bg-sky-400/10 text-sky-300 ring-sky-400/30'
                        : 'bg-emerald-400/10 text-emerald-300 ring-emerald-400/30'}`}>
              {isDefault ? '当前：内置默认' : '当前：自定义'}
            </span>
            <span className="text-xs text-app-muted font-mono">{count} 个域名</span>
          </div>

          <label className="block text-xs text-app-muted mb-2">每行一个域名（填主域即可，自动覆盖子域，例如 <code>tigerfintech.com</code>）</label>
          <textarea
            value={text}
            onChange={e => setText(e.target.value)}
            disabled={loading || saving}
            spellCheck={false}
            rows={14}
            className="w-full rounded-xl bg-black/30 ring-1 ring-white/10 focus:ring-accent-cyan/50 outline-none px-4 py-3 font-mono text-sm resize-y disabled:opacity-60"
            placeholder={loading ? '加载中…' : 'tigerfintech.com\nitigerup.net\n…'}
          />

          {msg && (
            <div className={`mt-3 rounded-lg px-4 py-3 text-sm border ${
              msg.kind === 'ok' ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-300'
                                : 'bg-red-500/10 border-red-500/30 text-red-400'}`}>
              {msg.text}
            </div>
          )}

          <div className="mt-4 flex flex-wrap items-center gap-2">
            <button onClick={save} disabled={loading || saving}
              className="rounded-xl px-5 py-2 text-sm font-semibold glow-cyan hover:scale-[1.02] transition-transform disabled:opacity-50">
              {saving ? '保存中…' : '保存'}</button>
            <button onClick={resetDefault} disabled={loading || saving}
              className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors disabled:opacity-50">
              恢复默认</button>
            <button onClick={load} disabled={loading || saving}
              className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors disabled:opacity-50">
              重新加载</button>
          </div>

          <p className="mt-4 text-[11px] text-app-muted leading-relaxed">
            保存后立即对接口生效；<span className="text-app-secondary">已连接的客户端需下次刷新配置/重连</span>才会拿到新列表。
            非法项（空行、带路径、格式错误）会在保存时自动剔除。
          </p>
        </section>
      </div>
    </div>
  )
}
