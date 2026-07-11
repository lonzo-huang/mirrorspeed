// 退款原因 + 挽留话术（中英）。表单与 API 共用，保证 reason_code 一致。

export interface RefundReason {
  code:      string
  emoji:     string
  group:     string   // zh group label
  groupEn:   string
  zh:        string
  en:        string
  // 用户勾选后动态显示的挽留话术（Churn Mitigation）
  retentionZh: string
  retentionEn: string
  // 是否引导留邮箱（如「设备不支持」，上线后通知）
  askEmail?: boolean
}

const NET = {
  retentionZh: '非常抱歉！各地区运营商网络环境复杂。请在「设置」中切换为 AmneziaWG 或「全局模式」后重试；也可在节点列表更换其他节点。若仍无法连接，联系技术支持我们帮你排查。',
  retentionEn: 'Sorry about that. Network conditions vary by ISP. Please switch to AmneziaWG or Global mode in Settings and retry, or pick a different node. If it still fails, contact support and we’ll help you troubleshoot.',
}
const UNBLOCK = {
  retentionZh: '专属提示：解锁流媒体或 AI 工具需使用特定节点。请在节点列表中更换其他节点服务器重新尝试。',
  retentionEn: 'Tip: unblocking streaming or AI tools requires a specific node. Please switch to a different node in the list and try again.',
}

export const REFUND_REASONS: RefundReason[] = [
  // 1. 网络与连接性能
  {
    code: 'cannot_connect', emoji: '🔴', group: '网络与连接性能', groupEn: 'Network & Connection',
    zh: '连不上服务器 / 无法建立连接', en: 'Cannot connect to any servers', ...NET,
  },
  {
    code: 'frequent_disconnect', emoji: '🔴', group: '网络与连接性能', groupEn: 'Network & Connection',
    zh: '连接极其不稳定 / 频繁掉线', en: 'Frequent disconnections / Unstable connection', ...NET,
  },
  {
    code: 'slow_speed', emoji: '🔴', group: '网络与连接性能', groupEn: 'Network & Connection',
    zh: '网速太慢 / 延迟太高，无法正常使用', en: 'Speed is too slow / Latency is too high', ...NET,
  },
  // 2. 设备与兼容性
  {
    code: 'os_not_supported', emoji: '📱', group: '设备与兼容性', groupEn: 'Devices & Compatibility',
    zh: '不支持我常用的操作系统 / 设备', en: 'My operating system/device is not supported',
    retentionZh: '我们的 Mac / iOS / 更多平台正在加紧开发中！留下邮箱，一旦上线我们会第一时间通知你，并赠送 1 个月免费时长。你现在仍要坚持退款吗？',
    retentionEn: 'Our Mac / iOS / more platforms are in active development! Leave your email and we’ll notify you the moment it launches, plus 1 month free. Still want to refund?',
    askEmail: true,
  },
  {
    code: 'app_crash', emoji: '🐛', group: '设备与兼容性', groupEn: 'Devices & Compatibility',
    zh: '客户端软件闪退、崩溃或报错', en: 'The app crashes, freezes, or shows errors',
    retentionZh: '请尝试更新到最新版本或重装客户端。若仍崩溃，联系技术支持并附上截图，我们会尽快修复。',
    retentionEn: 'Please update to the latest version or reinstall the app. If it still crashes, contact support with a screenshot and we’ll fix it quickly.',
  },
  // 3. 特定服务无法解锁
  {
    code: 'ai_tools', emoji: '🤖', group: '特定服务无法解锁', groupEn: 'Content & Service Unblocking',
    zh: '无法访问特定的 AI 工具（如 ChatGPT / Claude 等）', en: 'Cannot access AI tools (e.g. ChatGPT/Claude)', ...UNBLOCK,
  },
  {
    code: 'streaming', emoji: '🎬', group: '特定服务无法解锁', groupEn: 'Content & Service Unblocking',
    zh: '无法解锁特定地区的流媒体（如 Netflix / Disney+ / YouTube）', en: 'Cannot unblock streaming services', ...UNBLOCK,
  },
  {
    code: 'gaming', emoji: '🎮', group: '特定服务无法解锁', groupEn: 'Content & Service Unblocking',
    zh: '游戏加速效果不佳 / 丢包严重', en: 'Poor gaming acceleration / High packet loss', ...UNBLOCK,
  },
  // 4. 账户、计费与价格
  {
    code: 'wrong_plan', emoji: '🛒', group: '账户、计费与价格', groupEn: 'Billing & Pricing',
    zh: '不小心买错了套餐', en: 'Purchased the wrong plan by mistake',
    retentionZh: '买错套餐无需退款重买——联系客服可协助你换成正确的套餐。',
    retentionEn: 'Bought the wrong plan? No need to refund and rebuy — contact support and we’ll switch you to the correct plan.',
  },
  {
    code: 'double_charge', emoji: '💳', group: '账户、计费与价格', groupEn: 'Billing & Pricing',
    zh: '系统重复扣款或计费异常', en: 'Double charged or billing error',
    retentionZh: '重复扣款请放心，核实后会全额退回多扣部分。请在下方留言框注明订单信息，我们会优先处理。',
    retentionEn: 'For double charges, rest assured we’ll fully refund the extra charge after verification. Please note your order details below and we’ll prioritize it.',
  },
  // 5. 个人原因
  {
    code: 'no_longer_need', emoji: '🕊️', group: '个人原因', groupEn: 'Personal Reasons',
    zh: '我已经不再需要使用 VPN 了', en: 'No longer need a VPN service',
    retentionZh: '感谢你曾经的信任。如未来再有需要，欢迎随时回来，你的账号会一直保留。',
    retentionEn: 'Thanks for your trust. If you need us again in the future, you’re always welcome back — your account stays with you.',
  },
  {
    code: 'found_alternative', emoji: '🔍', group: '个人原因', groupEn: 'Personal Reasons',
    zh: '找到了更便宜或更好的替代品', en: 'Found a better or cheaper alternative',
    retentionZh: '我们很希望能继续为你服务。如果是价格因素，可联系客服了解当前的续费优惠方案。',
    retentionEn: 'We’d love to keep serving you. If it’s about price, contact support to learn about current renewal offers.',
  },
  {
    code: 'other', emoji: '✏️', group: '个人原因', groupEn: 'Personal Reasons',
    zh: '其他原因（请在下方留言框注明）', en: 'Other — please specify below',
    retentionZh: '请在下方尽量详细描述你的问题，我们会认真对待每一条反馈。',
    retentionEn: 'Please describe your issue in detail below — we take every piece of feedback seriously.',
  },
]

export function getRefundReason(code: string): RefundReason | undefined {
  return REFUND_REASONS.find(r => r.code === code)
}
