'use client'

import { useEffect } from 'react'

/**
 * 强制把 <html data-theme> 锁为 dark，用于纯深色页面（登录/注册/dashboard/admin）。
 * 配合根 layout 的 head 内联脚本（处理整页加载首屏），本组件覆盖 SPA 客户端跳转
 * （内联脚本不会在路由切换时重跑）。离开时不主动还原——目标页（主页/内容页）自身
 * 会按 ms_theme 重新设置 data-theme。
 */
export function ForceDarkTheme() {
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', 'dark')
  }, [])
  return null
}
