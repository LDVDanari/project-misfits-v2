import './globals.css';import Nav from '../components/Nav';
export const metadata={title:'Project Misfits v2',description:'Your Story. Your Choices. Your Legacy.'};
export default function Layout({children}){return <html lang="en"><body><Nav/>{children}<footer id="community"><b>PROJECT MISFITS v2</b><span>Your Story. Your Choices. Your Legacy.</span></footer></body></html>}
