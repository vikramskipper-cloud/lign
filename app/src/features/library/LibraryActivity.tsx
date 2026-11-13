import {createContext,useEffect,useRef,useState,type ReactNode} from 'react'
import {useBlocker} from 'react-router'
export const LibrarySaving=createContext(false)
export const LibraryActivity=createContext<(delta:number)=>void>(()=>{})
/** Keep a file upload and its reference registration together when navigating. */
export function LibrarySaveGuard({children}:{children:ReactNode}){
 const count=useRef(0),[active,setActive]=useState(0),blocker=useBlocker(()=>count.current>0)
 useEffect(()=>{if(blocker.state==='blocked'){if(window.confirm('A library save is in progress. Leave this page?'))blocker.proceed();else blocker.reset()}},[blocker])
 useEffect(()=>{if(!active)return;const warn=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue=''};window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn)},[active])
 return <LibrarySaving.Provider value={active>0}><LibraryActivity.Provider value={delta=>{count.current=Math.max(0,count.current+delta);setActive(count.current)}}>{children}</LibraryActivity.Provider></LibrarySaving.Provider>
}
