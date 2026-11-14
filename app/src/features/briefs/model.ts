export type BriefKind = 'mandatory' | 'preference' | 'assumption' | 'question'
export interface BriefField { id: string; label: string; help: string; answer: string }
export interface BriefItem {
  id: string; title: string; detail: string; kind: BriefKind
  priority: 'critical' | 'high' | 'medium' | 'low' | 'informational'
  source: 'client' | 'consultant' | 'internal_team' | 'other'
  areaIds?: string[]; areaSnapshot?: {id:string;path:string;kind?:string}[]
  acceptance: string; appliesTo: string; ownerProfileId: string; resolution: string
}
export interface BriefDocument {
  referenceSelection?: import('@/features/planning/queries').ReferenceCard[]
  disciplines: string[]; fields: BriefField[]; items: BriefItem[]
  references: { id: string; label: string; url: string }[]
}
const field = (id: string, label: string, help: string): BriefField => ({ id, label, help, answer: '' })
export const CORE_FIELDS = [
  field('objective', 'What should this project achieve?', 'Describe the problem, desired outcome and why it matters.'),
  field('audience', 'Who are we designing for?', 'Users, customers, occupants or the intended audience.'),
  field('deliverables', 'What should we deliver?', 'List the designs, products, spaces, samples or other outcomes expected.'),
  field('scope', 'What is included and excluded?', 'Define the boundaries of the work and any existing work to retain.'),
  field('budget', 'What budget or cost constraints apply?', 'Include the currency, what the budget covers, and anything not yet agreed.'),
  field('schedule', 'What timing or milestones matter?', 'Target dates, dependencies and any deadlines that are still assumptions.'),
  field('success', 'How will we judge success?', 'Describe the outcomes, references or checks the client and team should agree on.'),
  field('stakeholders', 'Who should contribute and decide?', 'Identify the client decision-makers, team members and consultant reviewers. Assign their project access through Team & access.'),
]
export const BRIEF_TEMPLATES = [
  { id: 'interiors', label: 'Interiors', fields: [field('interiors_spaces','Spaces and activities','Which spaces are involved, who uses them, and for which activities?'),field('interiors_finishes','Finishes, furniture and services','Materials, lighting, furniture, services and existing conditions to consider.')] },
  { id: 'architecture', label: 'Architecture', fields: [field('architecture_site','Site and context','Location, site information, access, surroundings and known constraints.'),field('architecture_accommodation','Accommodation and performance','Required uses, capacity, relationships, access and performance expectations.')] },
  { id: 'product', label: 'Product design', fields: [field('product_use','Use and functions','Who uses the product, in which situations, and what must it do?'),field('product_production','Components and production','Dimensions, interfaces, materials, manufacturing, assembly and quantities.')] },
  { id: 'furniture', label: 'Furniture design', fields: [field('furniture_fit','Items, dimensions and fit','Which items are needed, their dimensions, quantities and intended setting?'),field('furniture_build','Materials, finishes and assembly','Material and finish references, hardware, durability, assembly and delivery constraints.')] },
  { id: 'fashion', label: 'Fashion design', fields: [field('fashion_collection','Collection, audience and sizing','Garments, occasion, audience, fit references, size ranges and quantities.'),field('fashion_construction','Fabric and construction','Fabric, trims, construction, sampling, production and care expectations.')] },
]
export const newBriefDocument = (disciplines:string[]=[]): BriefDocument => {const selected=BRIEF_TEMPLATES.filter(t=>disciplines.includes(t.id));return {disciplines:selected.map(t=>t.id),fields:[...CORE_FIELDS,...selected.flatMap(t=>t.fields)].map(f=>({...f})),items:[],references:[]}}
export const newBriefItem = (): BriefItem => ({ id:crypto.randomUUID(),title:'',detail:'',kind:'mandatory',priority:'medium',source:'client',acceptance:'',appliesTo:'',ownerProfileId:'',resolution:'' })
