#!/usr/bin/env node
/**
 * 构建后处理：把中文路由预渲染出来的 HTML 里的 <html lang="en"> 改成 zh-CN。
 *
 * 为什么要这么做：
 *   App Router 里 <html> 只能由根布局输出。要让它随路由变化，只有三条路——
 *     1) 根布局调 headers() 读路径 → 整站退出静态渲染，营销页全部变成每请求现算；
 *     2) 拆成多个根布局 → 必须删掉 app/layout.tsx，把 dashboard/admin/auth 整棵树
 *        搬进路由组，为一个属性改动支付与登录代码，风险不成比例；
 *     3) 构建完直接改预渲染产物 —— 页面仍是纯静态，爬虫拿到的 HTML 里 lang 正确。
 *   取 3。客户端路由跳转时 <html> 不会被 React 重渲染，那一侧由各中文 layout 里的
 *   内联脚本兜底，两者合起来覆盖所有情况。
 *
 * 注意：本脚本在 package.json 的 build 里串联执行。直接跑 `next build` 会跳过它，
 * 导致中文页的 lang 回退成 en —— 验证请用 `npm run build`。
 */
import { readdir, readFile, writeFile } from 'node:fs/promises'
import { join, relative, sep } from 'node:path'

const APP_DIR = '.next/server/app'

/** 需要标成中文的路由前缀（相对 .next/server/app） */
const ZH_PREFIXES = ['cn', 'tutorials']
const ZH_LANG = 'zh-CN'

async function* walk(dir) {
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return   // 目录不存在（例如没有任何中文路由）
  }
  for (const e of entries) {
    const full = join(dir, e.name)
    if (e.isDirectory()) yield* walk(full)
    else if (e.isFile() && e.name.endsWith('.html')) yield full
  }
}

const isZhRoute = (file) => {
  const rel = relative(APP_DIR, file).split(sep)
  // 段本身的页面产出在上一层，叫 <段>.html（例如 /cn → cn.html），
  // 子页面才在 <段>/ 目录下（/cn/pricing → cn/pricing.html）。两种都要匹配。
  const first = rel[0].replace(/\.html$/, '')
  return ZH_PREFIXES.includes(first)
}

let patched = 0
let alreadyOk = 0

for await (const file of walk(APP_DIR)) {
  if (!isZhRoute(file)) continue
  const html = await readFile(file, 'utf8')

  if (html.includes(`<html lang="${ZH_LANG}"`)) { alreadyOk++; continue }

  // 只改开头的 <html ... lang="en">，不碰正文里可能出现的同样字符串
  const next = html.replace(/(<html[^>]*?\blang=")en(")/i, `$1${ZH_LANG}$2`)
  if (next !== html) {
    await writeFile(file, next)
    patched++
  } else {
    console.warn(`[fix-html-lang] 未找到 lang 属性，跳过: ${file}`)
  }
}

console.log(`[fix-html-lang] 已改写 ${patched} 个中文页面的 lang=${ZH_LANG}（${alreadyOk} 个本就正确）`)

// 中文路由是存在的，却一个都没改到 —— 说明路径约定变了，必须让构建失败而不是静默退化。
if (patched === 0 && alreadyOk === 0) {
  console.error('[fix-html-lang] 没有匹配到任何中文页面。ZH_PREFIXES 是否已过期？')
  process.exit(1)
}
