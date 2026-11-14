import { I18nProvider } from '@/lib/i18n'

// 这里原来写死了一个中英混排的 title + description，会覆盖**所有**营销页：
//   · 首页标题变成 "MirrorSpeed — … | MirrorSpeed"（被根布局模板又追加一次品牌名）
//   · 中英混排让两种语言的搜索都拿不到好位置
//   · description 声称支持 iOS / macOS，与下载页「Apple 开发中」互相矛盾
// 现已移除：首页继承根布局的英文元数据，/cn 与各子页各自提供自己的元数据。
export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <I18nProvider>
      {children}
    </I18nProvider>
  )
}
