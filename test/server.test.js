import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {WebSocket} from 'ws';
import {createServer} from '../server/index.js';
function receive(ws,type){return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{ws.off('message',handler);reject(Error(`Timed out: ${type}`));},7000);function handler(raw){const m=JSON.parse(raw);if(m.type===type){clearTimeout(timer);ws.off('message',handler);resolve(m);}}ws.on('message',handler);});}
test('accounts, ranked matchmaking, authoritative states and persisted Elo',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'pong-'));let app=createServer({dbPath:join(dir,'db.sqlite')});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));let base=`http://127.0.0.1:${app.server.address().port}`;const sockets=[];
 const request=async(path,body,token)=>{const response=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json()};};
 try{
  const a=await request('/api/register',{name:'PlayerA',password:'a-secure-password'}),b=await request('/api/register',{name:'PlayerB',password:'b-secure-password'});assert.equal(a.status,200);assert.equal(b.status,200);assert.equal(a.body.user.rating,1000);
  assert.equal((await request('/api/login',{name:'PlayerA',password:'wrong-password'})).status,401);
  assert.equal((await request('/api/register',{name:'playera',password:'a-secure-password'})).status,409);
  assert.equal((await request('/api/me',null,'invalid')).status,401);
  const blocked=await fetch(base+'/api/health',{headers:{Origin:'https://unknown.example'}});assert.equal(blocked.status,403);
  const wa=new WebSocket(base.replace('http','ws')+'/socket'),wb=new WebSocket(base.replace('http','ws')+'/socket');sockets.push(wa,wb);
  const readyA=receive(wa,'ready'),readyB=receive(wb,'ready');wa.on('open',()=>wa.send(JSON.stringify({type:'auth',token:a.body.token})));wb.on('open',()=>wb.send(JSON.stringify({type:'auth',token:b.body.token})));await Promise.all([readyA,readyB]);
  const ma=receive(wa,'matched'),mb=receive(wb,'matched'),sa=receive(wa,'state'),sb=receive(wb,'state');wa.send(JSON.stringify({type:'queue'}));wb.send(JSON.stringify({type:'queue'}));assert.equal((await ma).opponent.name,'PlayerB');assert.equal((await mb).opponent.name,'PlayerA');const [s1,s2]=await Promise.all([sa,sb]);assert.equal(s1.state.z,-s2.state.z);
  const result=receive(wa,'result');wb.close();const end=await result;assert.equal(end.won,true);assert.equal(end.reason,'disconnect');assert.equal(end.user.rating,1016);
  const ranking=await request('/api/ranking');assert.equal(ranking.body[0].name,'PlayerA');assert.equal(ranking.body[1].rating,984);wa.close();
  await app.close();app=createServer({dbPath:join(dir,'db.sqlite')});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${app.server.address().port}`;
  assert.equal((await request('/api/me',null,a.body.token)).body.rating,1016);
  await request('/api/logout',{},a.body.token);assert.equal((await request('/api/me',null,a.body.token)).status,401);
 }finally{for(const ws of sockets)ws.terminate();await app.close();rmSync(dir,{recursive:true,force:true});}
});
