export const DESIGN_DISCIPLINES=[{id:'interiors',label:'Interiors'},{id:'architecture',label:'Architecture'},{id:'product',label:'Product design'},{id:'furniture',label:'Furniture design'},{id:'fashion',label:'Fashion design'}] as const
export function disciplineNames(ids:string[]){return ids.map(id=>DESIGN_DISCIPLINES.find(d=>d.id===id)?.label??id).join(', ')||'General design'}
