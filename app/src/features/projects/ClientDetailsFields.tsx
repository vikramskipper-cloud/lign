export interface ClientDetails {
  clientCompany: string
  clientContactName: string
  clientEmail: string
  clientPhone: string
}
export const emptyClientDetails = (): ClientDetails => ({clientCompany:'',clientContactName:'',clientEmail:'',clientPhone:''})
export default function ClientDetailsFields({value,onChange,disabled=false}:{value:ClientDetails;onChange:(value:ClientDetails)=>void;disabled?:boolean}) {
  return <fieldset className="space-y-3" disabled={disabled}>
    <legend className="text-sm font-medium">Client details (optional)</legend>
    <p className="text-xs text-[--color-text-muted]">Record the client contact here. Portal access is assigned separately through project approvers and Team & access.</p>
    <div className="grid gap-3 sm:grid-cols-2">
      {([
        ['clientCompany','Client company','text',200],
        ['clientContactName','Client contact name','text',200],
        ['clientEmail','Client contact email','email',254],
        ['clientPhone','Client contact phone','tel',40],
      ] as const).map(([key,label,type,max])=><label key={key} className="block text-sm">{label}<input className="auth-field mt-1 w-full" type={type} maxLength={max} value={value[key]} onChange={e=>onChange({...value,[key]:e.target.value})} /></label>)}
    </div>
  </fieldset>
}
