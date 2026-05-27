'use client'

import { useState } from 'react'
import { RefreshCw } from 'lucide-react'

// CNY display prices for each plan
const CNY_PRICES: Record<string, string> = {
  monthly:   '¥24',
  quarterly: '¥36',
  yearly:    '¥96',
  biennial:  '¥168',
}

export function CnCheckoutButton({ planKey }: { planKey: string }) {
  const [loading, setLoading] = useState<'alipay' | 'wechat_pay' | null>(null)
  const [errMsg, setErrMsg]   = useState<string | null>(null)

  const price = CNY_PRICES[planKey] ?? ''

  async function startCnCheckout(method: 'alipay' | 'wechat_pay') {
    setLoading(method)
    setErrMsg(null)
    try {
      const res = await fetch('/api/billing/cn-checkout', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ plan: planKey, method }),
      })
      const data = await res.json()
      if (data.url) {
        window.location.href = data.url
      } else {
        setErrMsg(data.error ?? '未知错误')
        setLoading(null)
      }
    } catch (e: any) {
      setErrMsg(e?.message ?? '网络错误')
      setLoading(null)
    }
  }

  return (
    <div className="space-y-2 mt-2">
      {/* Divider */}
      <div className="flex items-center gap-2">
        <div className="flex-1 h-px bg-border/60" />
        <span className="text-[10px] text-muted-foreground uppercase tracking-widest">人民币支付</span>
        <div className="flex-1 h-px bg-border/60" />
      </div>

      <div className="grid grid-cols-2 gap-2">
        {/* Alipay */}
        <button
          onClick={() => startCnCheckout('alipay')}
          disabled={loading !== null}
          className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-[#1677ff]/40 bg-[#1677ff]/10 hover:bg-[#1677ff]/20 text-[#1677ff] text-sm font-semibold transition-all disabled:opacity-50"
        >
          {loading === 'alipay'
            ? <RefreshCw className="h-3.5 w-3.5 animate-spin" />
            : (
              <>
                {/* Alipay icon */}
                <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current" xmlns="http://www.w3.org/2000/svg">
                  <path d="M3.648 12.267c0 4.765 3.868 8.633 8.633 8.633a8.607 8.607 0 005.605-2.07c-.756-.385-3.975-1.988-6.3-3.293-1.218 1.522-2.493 2.478-4.088 2.478-2.096 0-3.204-1.516-3.204-3.09 0-2.294 2.127-3.836 5.125-3.836.98 0 2.016.148 3.052.43-.21-.448-.406-.9-.586-1.343H5.607v-.816h4.865a31.32 31.32 0 01-.307-.98H5.607v-.816h4.26c-.15-.757-.238-1.466-.238-2.082 0-3.052 2.085-4.706 4.707-4.706 1.93 0 3.437.804 4.436 2.054l-1.49 1.273c-.672-.868-1.664-1.39-2.946-1.39-1.72 0-2.793 1.037-2.793 2.827 0 .588.085 1.264.23 1.954h5.122v.816H11.8c.098.316.2.642.3.98h5.088v.816h-4.76c.182.47.378.94.587 1.4 1.93.684 3.64 1.537 4.727 2.1A8.61 8.61 0 0020.281 12a8.633 8.633 0 00-8.633-8.633A8.633 8.633 0 003.015 12c.006.09.012.179.012.267H3.648z"/>
                </svg>
                支付宝 {price}
              </>
            )
          }
        </button>

        {/* WeChat Pay */}
        <button
          onClick={() => startCnCheckout('wechat_pay')}
          disabled={loading !== null}
          className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-[#07c160]/40 bg-[#07c160]/10 hover:bg-[#07c160]/20 text-[#07c160] text-sm font-semibold transition-all disabled:opacity-50"
        >
          {loading === 'wechat_pay'
            ? <RefreshCw className="h-3.5 w-3.5 animate-spin" />
            : (
              <>
                {/* WeChat Pay icon */}
                <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current" xmlns="http://www.w3.org/2000/svg">
                  <path d="M9.5 4C5.36 4 2 6.92 2 10.5c0 1.95 1.05 3.7 2.7 4.87L4 17.5l2.5-.83C7.55 17.1 8.5 17.3 9.5 17.3c.2 0 .4 0 .6-.02A6.5 6.5 0 009.5 15c0-3.59 3.14-6.5 7-6.5.22 0 .44.01.65.03C16.1 6.07 13.07 4 9.5 4zm0 2c2.12 0 4 1.11 4.88 2.73A8.06 8.06 0 0016.5 6.5C20.09 6.5 23 9.08 23 12.25c0 1.55-.72 2.95-1.88 3.97l.38 2.28-2.12-.94c-.68.26-1.43.44-2.22.44C13.85 18 11 15.42 11 12.25c0-.18.01-.36.03-.54A7.27 7.27 0 019.5 12C7.02 12 5 11.13 5 10.5S7.02 9 9.5 9s4.5.87 4.5 1.5c0 .06 0 .12-.02.18.47-.11.96-.18 1.47-.18.18 0 .35.01.52.03A4.28 4.28 0 009.5 6z"/>
                </svg>
                微信 {price}
              </>
            )
          }
        </button>
      </div>

      {errMsg && (
        <p className="text-xs text-red-400 text-center">{errMsg}</p>
      )}
    </div>
  )
}
