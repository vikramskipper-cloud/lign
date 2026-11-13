import {type ReferenceCard,help} from './queries'
import FilePreview from './FilePreview'
export default function ReferenceSnapshot({cards}:{cards:ReferenceCard[]}){
 return <div className="grid gap-4 sm:grid-cols-2">{cards.map(c=><article key={c.id} className="space-y-2 rounded-lg border border-[#e5ddd3] p-4"><h3 className="break-words font-medium">{c.title}</h3><p className={help}>{c.boardTitle} · {c.areaPath??'Project-wide'} · Suggested by {c.authorName}</p>{c.file&&<FilePreview file={c.file}/>}<p className="whitespace-pre-wrap break-words text-sm">{c.description}</p>{c.url&&<a className="auth-link break-all text-sm" href={c.url} target="_blank" rel="noopener noreferrer">Open source reference</a>}{c.preferences.length>0&&<ul className={help}>{c.preferences.map(v=><li key={v.userId}>{v.name}: {v.choice}{v.note?` — ${v.note}`:''}</li>)}</ul>}</article>)}</div>
}
