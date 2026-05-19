import type { Config } from 'tailwindcss'

const config: Config = {
  darkMode: ['class'],
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // ── Portal light-theme ─────────────────────────────────────────
        brand: {
          50:  '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          900: '#1e3a8a',
        },
        // ── Marketing dark-theme (oklch + <alpha-value> for /N modifiers)
        mirror:     'oklch(0.85 0.16 210 / <alpha-value>)',
        warn:       'oklch(0.78 0.16 60  / <alpha-value>)',
        background: 'oklch(0.13 0.005 285)',
        foreground: 'oklch(0.985 0 0     / <alpha-value>)',
        card: {
          DEFAULT:    'oklch(0.17 0.006 285)',
          foreground: 'oklch(0.985 0 0)',
        },
        muted: {
          DEFAULT:    'oklch(0.22 0.008 285)',
          foreground: 'oklch(0.65 0.01 285)',
        },
        popover: {
          DEFAULT:    'oklch(0.17 0.006 285)',
          foreground: 'oklch(0.985 0 0)',
        },
        primary: {
          DEFAULT:    'oklch(0.985 0 0)',
          foreground: 'oklch(0.13 0.005 285)',
        },
        secondary: {
          DEFAULT:    'oklch(0.22 0.008 285)',
          foreground: 'oklch(0.985 0 0)',
        },
        accent: {
          DEFAULT:    'oklch(0.85 0.16 210)',
          foreground: 'oklch(0.13 0.005 285)',
        },
        destructive: {
          DEFAULT:    'oklch(0.65 0.22 25 / <alpha-value>)',
          foreground: 'oklch(0.985 0 0)',
        },
        border: 'rgba(255,255,255,0.08)',
        input:  'rgba(255,255,255,0.10)',
        ring:   'oklch(0.85 0.16 210)',
      },
      borderRadius: {
        lg: '0.5rem',
        md: '0.375rem',
        sm: '0.25rem',
      },
    },
  },
  plugins: [],
}

export default config
