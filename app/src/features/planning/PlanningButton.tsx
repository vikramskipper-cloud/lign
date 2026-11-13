import {Button as BaseButton,type ButtonProps} from '@/ui/button'
export function Button({variant='primary',style,...props}:ButtonProps){
 const primary=variant==='primary'
 return <BaseButton {...props} variant={variant} style={{borderRadius:8,border:primary?'1px solid var(--accent, #d9622b)':'1px solid #dcd3c8',background:primary?'var(--accent, #d9622b)':'#fffdf9',color:primary?'#fff':'#3a332d',...style}}/>
}
