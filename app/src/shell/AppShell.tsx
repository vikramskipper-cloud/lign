import * as React from 'react'
import {Link,useLocation,useNavigate} from 'react-router'
import {Home,Building2,Library,Inbox,Menu,UserRound,Users,X} from 'lucide-react'
import {useNotificationBadgeCount} from '@/features/notifications/queries'
import {NotificationBell} from '@/features/notifications/NotificationBell'
import {RealtimeIndicator} from '@/features/realtime/RealtimeIndicator'
import {UserMenu} from './UserMenu'
import {Wordmark} from '@/auth/AuthShell'
import {persistLastWorkspace} from './WorkspaceSwitcher'
import {useWorkspaceAccess} from '@/lib/capabilities'
import {useNavigationContext} from './navigationContext'
import '@/styles/auth-theme.css'

/** Global destinations only; workspace/project navigation belongs to its layout. */
export function AppShell({children}:{children:React.ReactNode}){
 const context=useNavigationContext(),{pathname}=useLocation(),navigate=useNavigate(),access=useWorkspaceAccess(context.workspaceId),badge=useNotificationBadgeCount(context.workspaceId)
 const [navOpen,setNavOpen]=React.useState(false),drawer=React.useRef<HTMLDivElement>(null),toggle=React.useRef<HTMLButtonElement>(null)
 React.useEffect(()=>setNavOpen(false),[pathname])
 React.useEffect(()=>{const media=window.matchMedia('(min-width:1024px)');const close=()=>{if(media.matches)setNavOpen(false)};media.addEventListener('change',close);return()=>media.removeEventListener('change',close)},[])
 React.useEffect(()=>{if(!navOpen)return;const previous=document.body.style.overflow;document.body.style.overflow='hidden';drawer.current?.querySelector<HTMLElement>('select,a,button')?.focus();const onKey=(e:KeyboardEvent)=>{if(e.key==='Escape'){setNavOpen(false);toggle.current?.focus()}if(e.key==='Tab'){const targets=Array.from(drawer.current?.querySelectorAll<HTMLElement>('a,button,select')??[]).filter(x=>!x.hasAttribute('disabled'));if(!targets.length)return;const first=targets[0],last=targets.at(-1)!;if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}};document.addEventListener('keydown',onKey);return()=>{document.body.style.overflow=previous;document.removeEventListener('keydown',onKey)}},[navOpen])
 const org=context.organizationId,ws=context.workspaceId,workspaceOverview=ws&&access.data?.['workspace.manage']?`/workspace/${ws}/overview`:null
 const overview=context.isAdmin&&org?`/org/${org}/overview`:workspaceOverview??'/dashboard',directory=`/workspaces${org?'?org='+org:''}`,scopedInbox=pathname.endsWith('/inbox')&&pathname.startsWith('/workspace/'),scopedWork=pathname==='/my-work'
 const switchOrg=(id:string)=>{const target=context.workspaces.find(w=>w.organization_id===id);setNavOpen(false);navigate(`/workspaces?org=${id}${target?'&ws='+target.id:''}`)}
 const activeKey=pathname.endsWith('/library')?'library':pathname===overview||pathname==='/dashboard'?'overview':pathname.startsWith('/org/')&&(pathname.endsWith('/people')||pathname.endsWith('/access'))?'people':scopedInbox?'inbox':scopedWork?'work':pathname.startsWith('/workspace/')||pathname==='/workspaces'||pathname==='/workspace-picker'?'workspaces':''
 const entries=[{key:'overview',to:overview,label:'Overview',icon:<Home size={17}/>},{key:'workspaces',to:directory,label:'Workspaces',icon:<Building2 size={17}/>},...(context.isMember&&org?[{key:'library',to:`/org/${org}/library`,label:'Library',icon:<Library size={17}/>}]:[]),{key:'work',to:`/my-work${ws?'?ws='+ws:''}`,label:'My work',icon:<UserRound size={17}/>},...(ws?[{key:'inbox',to:`/workspace/${ws}/inbox`,label:'Inbox',icon:<Inbox size={17}/>}]:[]),...(context.isAdmin&&org?[{key:'people',to:`/org/${org}/access`,label:'People & access',icon:<Users size={17}/>}]:[])]
 const rail=(mobile:boolean)=><div ref={mobile?drawer:undefined} className={'app-global-rail '+(mobile?'app-global-rail-mobile':'')}>
  <div className="app-org-picker"><label htmlFor={mobile?'drawer-org':'sidebar-org'}>Organisation</label><select id={mobile?'drawer-org':'sidebar-org'} aria-label="Organisation" value={org??''} onChange={e=>switchOrg(e.target.value)}>{!context.organizations.length&&<option value="">Your work</option>}{context.organizations.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></div>
  <nav aria-label="Main" className="app-global-links">{mobile&&<button type="button" className="app-close-nav" onClick={()=>{setNavOpen(false);toggle.current?.focus()}} aria-label="Close navigation"><X size={18}/></button>}{entries.map(e=><Link key={e.key} to={e.to} aria-current={activeKey===e.key?'page':undefined} onClick={()=>setNavOpen(false)}><span aria-hidden="true">{e.icon}</span><span>{e.label}</span>{e.key==='inbox'&&(badge.data?.total_unread??0)>0&&<span className="app-global-count">{Math.min(badge.data!.total_unread,99)}{badge.data!.total_unread>99?'+':''}</span>}</Link>)}</nav>
 </div>
 return <div className="lign-warm app-frame"><header className="app-topbar app-global-topbar"><button ref={toggle} className="app-nav-toggle" aria-label="Open navigation" aria-expanded={navOpen} onClick={()=>setNavOpen(!navOpen)}><Menu size={20}/></button><Link className="app-brand" to={overview} aria-label="Overview"><Wordmark/></Link><span className="app-global-org-name">{context.organizationName}</span><span className="app-topbar-spacer"/><RealtimeIndicator/><NotificationBell/><UserMenu/></header>
 <div className="app-frame-body"><aside className="app-global-sidebar">{rail(false)}</aside>{navOpen&&<div className="app-global-drawer" role="dialog" aria-modal="true" aria-label="Navigation" onClick={()=>{setNavOpen(false);toggle.current?.focus()}}><div onClick={e=>e.stopPropagation()}>{rail(true)}</div></div>}
 <main className="app-main">{(scopedInbox||scopedWork)&&ws&&<div className="app-feed-scope"><label htmlFor="feed-workspace">Viewing workspace</label><select id="feed-workspace" value={ws} onChange={e=>{persistLastWorkspace(e.target.value);navigate(scopedWork?`/my-work?ws=${e.target.value}`:`/workspace/${e.target.value}/inbox`)}}>{context.workspaces.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></div>}{children}</main></div></div>
}
