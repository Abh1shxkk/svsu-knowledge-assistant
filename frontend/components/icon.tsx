import {
  AlertTriangle, ArrowUpRight, Ban, BarChart3, Bell, Bookmark, Calendar, Check, ChevronDown, ChevronLeft,
  ChevronRight, Clock, Copy, ExternalLink, Eye, FileText, Filter, Globe, History, LayoutDashboard, LayoutGrid,
  Layers, Link2, List, LogOut, Menu, MessageCircle, Moon, PanelLeftClose, PanelLeftOpen, Pencil, Plus, RefreshCw,
  Save, Search, Send, Share2, ShieldCheck, SlidersHorizontal, Sparkles, Sun, Tag, ThumbsDown, ThumbsUp, Trash2,
  Upload, User, X, ZoomIn, ZoomOut, type LucideIcon,
} from "lucide-react";

/** Icon names mirror the prototype so screens read the same. */
const ICONS: Record<string, LucideIcon> = {
  panelClose: PanelLeftClose, panelOpen: PanelLeftOpen, sun: Sun, moon: Moon, logout: LogOut, arrow: ArrowUpRight,
  home: LayoutDashboard, chat: MessageCircle, file: FileText, upload: Upload, check: Check,
  shield: ShieldCheck, layers: Layers, cal: Calendar, bm: Bookmark, chart: BarChart3,
  sliders: SlidersHorizontal, search: Search, bell: Bell, x: X, cl: ChevronLeft, cr: ChevronRight,
  cd: ChevronDown, plus: Plus, copy: Copy, up: ThumbsUp, down: ThumbsDown, export: Share2,
  save: Save, filter: Filter, grid: LayoutGrid, list: List, menu: Menu, zin: ZoomIn, zout: ZoomOut,
  link: Link2, edit: Pencil, tag: Tag, alert: AlertTriangle, clock: Clock, send: Send,
  spark: Sparkles, eye: Eye, user: User, trash: Trash2, hist: History, globe: Globe, ban: Ban,
  rev: RefreshCw, open: ExternalLink,
};

export function Icon({ n, s = false, className = "" }: { n: string; s?: boolean; className?: string }) {
  const C = ICONS[n] ?? FileText;
  return <C size={s ? 15 : 18} strokeWidth={1.8} className={className} aria-hidden />;
}
