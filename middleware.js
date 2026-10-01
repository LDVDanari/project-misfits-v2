import {NextResponse} from 'next/server';

function basicAuth(request,user,pass,realm){
 if(!user||!pass)return new NextResponse('Not Found',{status:404});
 const auth=request.headers.get('authorization')||'';
 if(!auth.startsWith('Basic '))return new NextResponse('Authentication required',{status:401,headers:{'WWW-Authenticate':`Basic realm="${realm}"`}});
 try{
  const decoded=atob(auth.slice(6));
  const split=decoded.indexOf(':');
  const u=decoded.slice(0,split);
  const p=decoded.slice(split+1);
  if(u===user&&p===pass)return NextResponse.next();
 }catch{}
 return new NextResponse('Unauthorized',{status:401,headers:{'WWW-Authenticate':`Basic realm="${realm}"`}});
}

export function middleware(request){
 const path=request.nextUrl.pathname;
 if(path.startsWith('/owner')||path.startsWith('/api/owner'))return basicAuth(request,process.env.OWNER_USERNAME,process.env.OWNER_PASSWORD,'PMv2 Owner');
 if(path.startsWith('/admin'))return basicAuth(request,process.env.ADMIN_USERNAME,process.env.ADMIN_PASSWORD,'PMv2 Admin');
 return NextResponse.next();
}
export const config={matcher:['/admin/:path*','/owner/:path*','/api/owner/:path*']};
