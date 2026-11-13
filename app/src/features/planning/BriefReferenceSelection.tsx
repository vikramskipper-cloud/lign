import {Link} from 'react-router'
import {type ReferenceCard,help} from './queries'
import ReferenceSnapshot from './ReferenceSnapshot'
export default function BriefReferenceSelection({projectId,workspaceId,snapshot}:{projectId:string;workspaceId:string;snapshot?:ReferenceCard[]}){
 return <section className="space-y-3 rounded-xl border border-[#e5ddd3] p-5"><h2 className="font-semibold">Visual direction and reference boards</h2>{snapshot?<><p className={help}>These references and preferences were captured for this exact brief revision. External websites may change; uploaded files retain the reviewed copy.</p>{snapshot.length?<ReferenceSnapshot cards={snapshot}/>:<p className="text-sm">No visual references were selected for this revision.</p>}</>:<><p className="text-sm">Use mood boards, client shortlists and suggested references to clarify the direction. Project leadership selects which references to include when requesting brief agreement.</p><Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/references`}>Open reference boards</Link></>}</section>
}
