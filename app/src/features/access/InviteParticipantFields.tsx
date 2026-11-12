import {Input} from '@/ui/input'
import {FormRow} from '@/ui/form-row'
export function InviteParticipantFields({label,onLabel,canSubmit,onCanSubmit,showSubmission,disabled}:{label:string;onLabel:(value:string)=>void;canSubmit:boolean;onCanSubmit:(value:boolean)=>void;showSubmission:boolean;disabled:boolean}){
 return <div className="space-y-3"><FormRow label="Professional label (optional)" htmlFor="invite-professional"><Input id="invite-professional" maxLength={80} value={label} disabled={disabled} placeholder="Structural consultant, client, fabric supplier…" onChange={e=>onLabel(e.target.value)}/></FormRow>{showSubmission&&<><label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={canSubmit} disabled={disabled} onChange={e=>onCanSubmit(e.target.checked)}/>Can submit deliverables</label><p className="text-xs text-[--color-text-muted]">Allows their own draft submissions. A project lead or contributor reviews and publishes them.</p></>}</div>
}
