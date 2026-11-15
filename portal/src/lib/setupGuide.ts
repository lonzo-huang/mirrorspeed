// 英文上手指南数据。
//
// 为什么不直接翻译中文教程：那 9 篇里「华为保活」「Apple ID 换区」是中国大陆特有
// 场景，直译给英文用户只是噪音；而英文市场真正缺的是一篇覆盖各平台的安装指南。
// 这里的步骤直接对应 lib/tutorials.ts 里的真实流程（同一套客户端），只是按英文
// 用户的使用习惯重新组织，并去掉了只对国内网络环境成立的部分。

import { PLATFORMS } from './product'

export interface SetupStep { t: string; d: string }

export interface SetupPlatform {
  key: string
  name: string
  /** 取自 product.ts，保证与全站平台状态一致 */
  available: boolean
  intro: string
  steps: SetupStep[]
  tips?: string[]
}

const statusOf = (key: string) =>
  PLATFORMS.find(p => p.key === key)?.status === 'available'

export const SETUP_PLATFORMS: SetupPlatform[] = [
  {
    key: 'windows',
    name: 'Windows',
    available: statusOf('windows'),
    intro: 'Works on Windows 10 and 11. Windows 7 needs SP1 and up-to-date root certificates first, or sign-in will fail for lack of modern TLS support.',
    steps: [
      {
        t: 'Download the installer',
        d: 'Go to mirrorspeed.com/download and choose the Windows build. If your browser warns about an uncommon download, choose Keep — that warning is about how many people have downloaded the file, not about its contents.',
      },
      {
        t: 'Run it as administrator',
        d: 'Right-click the installer and choose "Run as administrator". This matters: without elevation the virtual network adapter cannot be installed and the app will connect but carry no traffic. If SmartScreen shows a blue "Windows protected your PC" box, click More info, then Run anyway.',
      },
      {
        t: 'Sign in',
        d: 'Open the app and sign in with your email. You can use a one-time code sent to your inbox, an email and password, or your Google account. If the code does not arrive within a minute, check your spam folder.',
      },
      {
        t: 'Connect',
        d: 'Press the power button in the middle of the window. Automatic selection picks the node with the best combination of latency and current load. The button turns green once the tunnel is up.',
      },
      {
        t: 'Check that it is working',
        d: 'Open any site that was previously unreachable. If it loads, traffic is going through the tunnel.',
      },
    ],
    tips: [
      'Connected but nothing loads: switch to a different node first, then try Global mode in settings.',
      'If the app will not install, confirm you ran it as administrator — this is the most common cause.',
    ],
  },
  {
    key: 'android',
    name: 'Android',
    available: statusOf('android'),
    intro: 'Install from Google Play, or download the APK directly from our site if Play is unavailable to you.',
    steps: [
      {
        t: 'Install the app',
        d: 'Install from Google Play, or download the APK from mirrorspeed.com/download. Installing an APK requires allowing your browser to install unknown apps — Android will prompt you, and the permission applies only to that browser.',
      },
      {
        t: 'Sign in',
        d: 'Open the app and sign in with your email, using a one-time code, a password, or Google sign-in.',
      },
      {
        t: 'Approve the VPN request',
        d: 'The first time you connect, Android shows a system dialog asking to allow a VPN connection. You have to accept it — without it the app cannot create the tunnel. A key icon appears in the status bar while connected.',
      },
      {
        t: 'Stop Android from killing it in the background',
        d: 'Android aggressively suspends background apps, which drops the tunnel when your screen is off. In Settings, exclude MirrorSpeed from battery optimisation and lock it in the recent-apps list. Manufacturer skins add their own layer — Huawei, Xiaomi, OPPO and Samsung each have a separate auto-start or protected-apps setting.',
      },
    ],
    tips: [
      'Per-app routing lets you send only chosen apps through the tunnel; the rest keep using your normal connection.',
      'If the connection drops whenever the screen turns off, the background restriction above is almost always the cause.',
    ],
  },
  {
    key: 'harmonyos',
    name: 'HarmonyOS',
    available: statusOf('harmonyos'),
    intro: 'HarmonyOS devices install the Android package, with one extra step for the system app manager.',
    steps: [
      {
        t: 'Install the APK',
        d: 'Download the Android package from mirrorspeed.com/download and allow installation when prompted.',
      },
      {
        t: 'Turn off automatic app management',
        d: 'In Settings, open Battery, then App launch, find MirrorSpeed and turn off "Manage automatically". Then enable auto-launch, secondary launch and run in background manually. Leaving this on automatic is what causes the tunnel to drop after the screen locks.',
      },
      {
        t: 'Lock it in recent apps',
        d: 'Open the recent-apps view, swipe down on the MirrorSpeed card and tap the lock icon so the system will not clear it.',
      },
      {
        t: 'Sign in and connect',
        d: 'Sign in with your email, then press connect and accept the system VPN prompt.',
      },
    ],
  },
]

/** 连接成功却上不了网 —— 按真实处理顺序排列 */
export const TROUBLESHOOTING: SetupStep[] = [
  {
    t: 'Confirm your underlying connection works',
    d: 'Disconnect the tunnel and load any local site. If nothing loads with the tunnel off, the problem is your network or Wi-Fi, not MirrorSpeed.',
  },
  {
    t: 'Switch to a different node',
    d: 'A single node can be congested or temporarily unreachable from your network. Pick another one from the list rather than reconnecting to the same node repeatedly.',
  },
  {
    t: 'Switch routing mode',
    d: 'Smart mode sends only part of your traffic through the tunnel. If a site still will not load, switch to Global mode so everything goes through it.',
  },
  {
    t: 'Reconnect once',
    d: 'Disconnect and connect again. This rebuilds the tunnel and re-applies DNS settings, which fixes most cases where the handshake succeeded but traffic does not flow.',
  },
  {
    t: 'Check your system clock',
    d: 'A clock that is wrong by more than a few minutes breaks the TLS handshake and the connection will fail in ways that look unrelated. Set date and time to automatic.',
  },
]
