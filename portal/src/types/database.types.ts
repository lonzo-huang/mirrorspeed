// ============================================================
// 此文件由 supabase gen types typescript 自动生成
// 部署后执行: npm run db:generate 更新为实际类型
// ============================================================

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id:                         string
          email:                      string
          display_name:               string | null
          avatar_url:                 string | null
          role:                       string
          preferred_currency:         string
          stripe_customer_id:         string | null
          referral_code:              string | null
          referred_by:                string | null
          referral_bonus_expires_at:  string | null
          created_at:                 string
          updated_at:                 string
        }
        Insert: {
          id:                         string
          email:                      string
          display_name?:              string | null
          avatar_url?:                string | null
          role?:                      string
          preferred_currency?:        string
          stripe_customer_id?:        string | null
          referral_code?:             string | null
          referred_by?:               string | null
          referral_bonus_expires_at?: string | null
          created_at?:                string
          updated_at?:                string
        }
        Update: {
          id?:                        string
          email?:                     string
          display_name?:              string | null
          avatar_url?:                string | null
          role?:                      string
          preferred_currency?:        string
          stripe_customer_id?:        string | null
          referral_code?:             string | null
          referred_by?:               string | null
          referral_bonus_expires_at?: string | null
          updated_at?:                string
        }
      }
      referral_rewards: {
        Row: {
          id:          string
          referrer_id: string
          invitee_id:  string
          plan_name:   string | null
          bonus_days:  number
          created_at:  string
        }
        Insert: {
          id?:         string
          referrer_id: string
          invitee_id:  string
          plan_name?:  string | null
          bonus_days:  number
          created_at?: string
        }
        Update: {
          bonus_days?: number
        }
      }
      plans: {
        Row: {
          id:                string
          name:              string
          description:       string | null
          max_devices:       number
          price_usd_cents:   number
          price_eur_cents:   number
          price_cny_fen:     number
          stripe_price_usd:  string | null
          stripe_price_eur:  string | null
          stripe_price_cny:  string | null
          is_active:         boolean
          created_at:        string
        }
        Insert: {
          id?:               string
          name:              string
          description?:      string | null
          max_devices?:      number
          price_usd_cents:   number
          price_eur_cents:   number
          price_cny_fen:     number
          stripe_price_usd?: string | null
          stripe_price_eur?: string | null
          stripe_price_cny?: string | null
          is_active?:        boolean
          created_at?:       string
        }
        Update: {
          name?:             string
          description?:      string | null
          max_devices?:      number
          price_usd_cents?:  number
          price_eur_cents?:  number
          price_cny_fen?:    number
          stripe_price_usd?: string | null
          stripe_price_eur?: string | null
          stripe_price_cny?: string | null
          is_active?:        boolean
        }
      }
      subscriptions: {
        Row: {
          id:                      string
          user_id:                 string
          plan_id:                 string
          status:                  string
          currency:                string
          amount_paid_cents:       number | null
          started_at:              string | null
          expires_at:              string | null
          stripe_subscription_id:  string | null
          stripe_latest_invoice:   string | null
          cancel_at_period_end:    boolean
          created_at:              string
          updated_at:              string
        }
        Insert: {
          id?:                     string
          user_id:                 string
          plan_id:                 string
          status?:                 string
          currency:                string
          amount_paid_cents?:      number | null
          started_at?:             string | null
          expires_at?:             string | null
          stripe_subscription_id?: string | null
          stripe_latest_invoice?:  string | null
          cancel_at_period_end?:   boolean
          created_at?:             string
          updated_at?:             string
        }
        Update: {
          status?:                 string
          amount_paid_cents?:      number | null
          started_at?:             string | null
          expires_at?:             string | null
          stripe_subscription_id?: string | null
          stripe_latest_invoice?:  string | null
          cancel_at_period_end?:   boolean
          updated_at?:             string
        }
      }
      vpn_devices: {
        Row: {
          id:               string
          user_id:          string
          subscription_id:  string | null
          device_label:     string
          os_hint:          string | null
          sub_token:        string
          is_active:        boolean
          created_at:       string
        }
        Insert: {
          id?:              string
          user_id:          string
          subscription_id?: string | null
          device_label:     string
          os_hint?:         string | null
          sub_token?:       string
          is_active?:       boolean
          created_at?:      string
        }
        Update: {
          device_label?:    string
          os_hint?:         string | null
          sub_token?:       string
          is_active?:       boolean
        }
      }
      vpn_device_peers: {
        Row: {
          id:                string
          device_id:         string
          server_id:         string
          user_id:           string
          peer_name:         string
          public_key:        string
          private_key_enc:   string
          preshared_key_enc: string
          vpn_ip:            string
          is_active:         boolean
          created_at:        string
        }
        Insert: {
          id?:               string
          device_id:         string
          server_id:         string
          user_id:           string
          peer_name:         string
          public_key:        string
          private_key_enc:   string
          preshared_key_enc: string
          vpn_ip:            string
          is_active?:        boolean
          created_at?:       string
        }
        Update: {
          is_active?: boolean
        }
      }
      vpn_servers: {
        Row: {
          id:              string
          name:            string
          display_name:    string
          location:        string
          country_code:    string
          flag_emoji:      string
          endpoint:        string
          port:            number
          public_key:      string
          api_url:         string
          status:          string
          latency_ms:      number | null
          active_peers:    number
          max_peers:       number
          load_percent:    number
          cpu_percent:     number | null
          mem_percent:     number | null
          bandwidth_mbps:  number | null
          last_checked_at: string | null
          sort_order:      number
          is_active:       boolean
          created_at:      string
          port_secret:     string | null
          awg_jc:          number
          awg_jmin:        number
          awg_jmax:        number
          awg_s1:          number
          awg_s2:          number
          awg_h1:          number
          awg_h2:          number
          awg_h3:          number
          awg_h4:          number
          cf_relay_url:    string | null
        }
        Insert: {
          id?:             string
          name:            string
          display_name:    string
          location:        string
          country_code:    string
          flag_emoji?:     string
          endpoint:        string
          port?:           number
          public_key:      string
          api_url:         string
          port_secret?:    string | null
          awg_jc?:         number
          awg_jmin?:       number
          awg_jmax?:       number
          awg_s1?:         number
          awg_s2?:         number
          awg_h1?:         number
          awg_h2?:         number
          awg_h3?:         number
          awg_h4?:         number
          cf_relay_url?:   string | null
          status?:         string
          latency_ms?:     number | null
          active_peers?:   number
          max_peers?:      number
          load_percent?:   number
          cpu_percent?:    number | null
          mem_percent?:    number | null
          bandwidth_mbps?: number | null
          last_checked_at?: string | null
          sort_order?:     number
          is_active?:      boolean
          created_at?:     string
        }
        Update: {
          status?:         string
          latency_ms?:     number | null
          active_peers?:   number
          max_peers?:      number
          load_percent?:   number
          cpu_percent?:    number | null
          mem_percent?:    number | null
          bandwidth_mbps?: number | null
          last_checked_at?: string | null
          sort_order?:     number
          is_active?:      boolean
        }
      }
      payments: {
        Row: {
          id:                 string
          user_id:            string
          subscription_id:    string | null
          amount_cents:       number
          currency:           string
          status:             string
          stripe_payment_id:  string | null
          stripe_invoice_id:  string | null
          description:        string | null
          created_at:         string
        }
        Insert: {
          id?:                string
          user_id:            string
          subscription_id?:   string | null
          amount_cents:       number
          currency:           string
          status:             string
          stripe_payment_id?: string | null
          stripe_invoice_id?: string | null
          description?:       string | null
          created_at?:        string
        }
        Update: {
          status?:            string
          description?:       string | null
        }
      }
      audit_log: {
        Row: {
          id:         number
          user_id:    string | null
          action:     string
          detail:     Json | null
          created_at: string
        }
        Insert: {
          user_id?:   string | null
          action:     string
          detail?:    Json | null
          created_at?: string
        }
        Update: {
          action?:  string
          detail?:  Json | null
        }
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      is_admin: {
        Args:    Record<PropertyKey, never>
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
  }
}

// Convenience helper — mirrors what supabase-js provides
export type Tables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Row']

export type InsertTables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Insert']

export type UpdateTables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Update']
