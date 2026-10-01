export const products=[
{slug:'gang',category:'ORGANIZATIONS',title:'Gang Package',price:'$180',image:'/images/packages/gang.jpg',short:'Build your identity, establish your organization and create your story in the city.',features:['One approved gang territory','One gang chain','One gang outfit package','Official gang recognition','Gang roles and permissions']},
{slug:'family',category:'ORGANIZATIONS',title:'Family Package',price:'$225',image:'/images/packages/family.jpg',short:'Create a family legacy with approved housing, branding and organization features.',features:['One approved family house','One family chain','One family clothing piece','Official family recognition','Family roles and permissions']},
{slug:'business',category:'BUSINESS',title:'Business Package',price:'$280',image:'/images/packages/business.jpg',short:'Own and operate an approved business with defined features and employee management.',features:['One approved business','Business organization setup','Employee recruitment and management','Applicable business features','Staff setup assistance']},
{slug:'mlo',category:'PROPERTY',title:'MLO Package',price:'$250',image:'/images/packages/mlo.jpg',short:'Explore approved property options with clearly listed interiors and included features.',features:['Approved MLO selection','Property setup','Storage where included','Eligible elevator setup','Listed package features']}
];
export const coins=[
{slug:'10-coins',category:'MISFIT COINS',title:'10 Misfit Coins',price:'$12.50',image:'/images/coins/10.png',short:'10 Misfit Coins credited to your Project Misfits v2 account.',features:['10 Misfit Coins','Account delivery','Eligible PMv2 purchases']},
{slug:'25-coins',category:'MISFIT COINS',title:'25 Misfit Coins',price:'$30',image:'/images/coins/25.png',short:'25 Misfit Coins credited to your Project Misfits v2 account.',features:['25 Misfit Coins','Account delivery','Eligible PMv2 purchases']},
{slug:'50-coins',category:'MISFIT COINS',title:'50 Misfit Coins',price:'$60',image:'/images/coins/50.png',short:'50 Misfit Coins credited to your Project Misfits v2 account.',features:['50 Misfit Coins','Account delivery','Eligible PMv2 purchases']},
{slug:'100-coins',category:'MISFIT COINS',title:'100 Misfit Coins',price:'$125',image:'/images/coins/100.png',short:'100 Misfit Coins credited to your Project Misfits v2 account.',features:['100 Misfit Coins','Account delivery','Eligible PMv2 purchases']},
{slug:'250-coins',category:'MISFIT COINS',title:'250 Misfit Coins',price:'$280',image:'/images/coins/250.png',short:'250 Misfit Coins credited to your Project Misfits v2 account.',features:['250 Misfit Coins','Account delivery','Eligible PMv2 purchases']},
{slug:'500-coins',category:'MISFIT COINS',title:'500 Misfit Coins',price:'$550',image:'/images/coins/500.png',short:'500 Misfit Coins credited to your Project Misfits v2 account.',features:['500 Misfit Coins','Account delivery','Eligible PMv2 purchases']}
];
export const priorities=[
{slug:'bronze-priority',category:'PRIORITY',title:'Bronze Priority',price:'COMING SOON',image:'/images/priority/bronze.png',short:'Entry-level queue priority for Project Misfits v2.',features:['Bronze queue priority','Account-linked access','Subject to server priority rules']},
{slug:'silver-priority',category:'PRIORITY',title:'Silver Priority',price:'COMING SOON',image:'/images/priority/silver.png',short:'Upgraded queue priority for Project Misfits v2.',features:['Silver queue priority','Account-linked access','Subject to server priority rules']},
{slug:'gold-priority',category:'PRIORITY',title:'Gold Priority',price:'COMING SOON',image:'/images/priority/gold.png',short:'Premium queue priority for Project Misfits v2.',features:['Gold queue priority','Account-linked access','Subject to server priority rules']}
];
export const allStoreItems=[...products,...coins,...priorities];
export const getProduct=s=>allStoreItems.find(p=>p.slug===s);
