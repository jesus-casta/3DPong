import http from 'node:http';
import {DatabaseSync} from 'node:sqlite';
import {randomBytes,scrypt,timingSafeEqual,createHash} from 'node:crypto';
import {promisify} from 'node:util';
import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {WebSocketServer,WebSocket} from 'ws';
import {createGame,step,clamp} from './physics.js';
const derive=promisify(scrypt),digest=t=>createHash('sha256').update(t).digest('hex');
export function createServer({dbPath=process.env.DB_PATH||'.data/pong.sqlite',origins=(process.env.ALLOWED_ORIGINS||'http://localhost,https://localhost').split(',')}={}){
 mkdirSync(dirname(dbPath),{recursive:true});const db=new DatabaseSync(dbPath);
 db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY,name TEXT NOT NULL UNIQUE COLLATE NOCASE,salt TEXT NOT NULL,password TEXT NOT NULL,rating INTEGER NOT NULL DEFAULT 1000,wins INTEGER NOT NULL DEFAULT 0,losses INTEGER NOT NULL DEFAULT 0); CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id INTEGER NOT NULL,expires INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS matches(id INTEGER PRIMARY KEY,winner INTEGER NOT NULL,loser INTEGER NOT NULL,ended INTEGER NOT NULL);');
 const clients=new Map(),queue=new Map(),matches=new Set(),limits=new Map();
 const user=id=>db.prepare('SELECT * FROM users WHERE id=?').get(id),pub=u=>({id:u.id,name:u.name,rating:u.rating,wins:u.wins,losses:u.losses});
 function auth(token){if(typeof token!=='string'||token.length>200)return null;const s=db.prepare('SELECT user_id FROM sessions WHERE token=? AND expires>?').get(digest(token),Date.now());return s?user(s.user_id):null;}
 function limited(key,max){let v=limits.get(key);if(!v||Date.now()-v.start>60000){v={start:Date.now(),n:0};limits.set(key,v);}return ++v.n>max;}
 const server=http.createServer(async(req,res)=>{
  const origin=req.headers.origin;if(origin&&!origins.includes(origin)){res.writeHead(403);res.end();return;}if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');res.setHeader('Cache-Control','no-store');
  const reply=(status,body)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(body));};if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  if(limited(req.socket.remoteAddress,120)){reply(429,{error:'Demasiadas solicitudes. Espera un minuto.'});return;}
  const path=new URL(req.url,'http://localhost').pathname;
  try{
   if(path==='/api/health'&&req.method==='GET'){reply(200,{ok:true});return;}
   if(path==='/api/ranking'&&req.method==='GET'){reply(200,db.prepare('SELECT id,name,rating,wins,losses FROM users ORDER BY rating DESC,wins DESC,id ASC LIMIT 50').all());return;}
   if(path==='/api/me'&&req.method==='GET'){const u=auth(req.headers.authorization?.replace(/^Bearer /,''));reply(u?200:401,u?pub(u):{error:'Inicia sesión de nuevo.'});return;}
   if(path==='/api/logout'&&req.method==='POST'){const token=req.headers.authorization?.replace(/^Bearer /,'');if(token){const u=auth(token);db.prepare('DELETE FROM sessions WHERE token=?').run(digest(token));if(u)clients.get(u.id)?.close(4001,'Signed out');}reply(200,{ok:true});return;}
   if(['/api/register','/api/login'].includes(path)&&req.method==='POST'){
    if(limited('auth:'+req.socket.remoteAddress,15)){reply(429,{error:'Demasiados intentos. Espera un minuto.'});return;}
    let body='';for await(const chunk of req){body+=chunk;if(body.length>4096){reply(413,{error:'Solicitud demasiado grande.'});return;}}
    const {name,password}=JSON.parse(body);if(typeof name!=='string'||!/^[a-zA-Z0-9_]{3,20}$/.test(name)||typeof password!=='string'||password.length<10||password.length>128){reply(400,{error:'Nombre: 3–20 letras, números o _. Contraseña: 10–128 caracteres.'});return;}
    let u=db.prepare('SELECT * FROM users WHERE name=?').get(name);
    if(path==='/api/register'){
     if(u){reply(409,{error:'Ese nombre ya está registrado.'});return;}const salt=randomBytes(16).toString('hex'),hash=(await derive(password,salt,64)).toString('hex');
     try{const result=db.prepare('INSERT INTO users(name,salt,password) VALUES(?,?,?)').run(name,salt,hash);u=user(Number(result.lastInsertRowid));}catch{reply(409,{error:'Ese nombre ya está registrado.'});return;}
    }else{const hash=await derive(password,u?.salt||'missing-user',64);if(!u||!timingSafeEqual(hash,Buffer.from(u.password,'hex'))){reply(401,{error:'Nombre o contraseña incorrectos.'});return;}}
    const token=randomBytes(32).toString('hex');db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(digest(token),u.id,Date.now()+7*86400000);reply(200,{token,user:pub(u)});return;
   }reply(404,{error:'Ruta no encontrada.'});
  }catch{reply(400,{error:'Solicitud no válida.'});}
 });
 const wss=new WebSocketServer({noServer:true,maxPayload:1024});server.on('upgrade',(req,socket,head)=>{if(req.url!=='/socket'||(req.headers.origin&&!origins.includes(req.headers.origin))){socket.destroy();return;}wss.handleUpgrade(req,socket,head,ws=>wss.emit('connection',ws));});
 const send=(ws,data)=>{if(ws.readyState===WebSocket.OPEN&&ws.bufferedAmount<65536)ws.send(JSON.stringify(data));};
 function finish(m,winner,reason='score'){
  if(m.done)return;m.done=true;matches.delete(m);const a=user(m.players[winner].uid),b=user(m.players[1-winner].uid),delta=Math.round(32*(1-1/(1+10**((b.rating-a.rating)/400))));
  db.exec('BEGIN');try{db.prepare('UPDATE users SET rating=rating+?,wins=wins+1 WHERE id=?').run(delta,a.id);db.prepare('UPDATE users SET rating=rating-?,losses=losses+1 WHERE id=?').run(delta,b.id);db.prepare('INSERT INTO matches(winner,loser,ended) VALUES(?,?,?)').run(a.id,b.id,Date.now());db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}
  m.players.forEach((ws,i)=>{ws.match=null;send(ws,{type:'result',won:i===winner,reason,user:pub(user(ws.uid)),score:i===0?m.game.score:[...m.game.score].reverse()});});
 }
 wss.on('connection',ws=>{
  ws.alive=true;ws.on('pong',()=>ws.alive=true);const timer=setTimeout(()=>{if(!ws.uid)ws.close(4001,'Authentication required');},5000);
  ws.on('message',raw=>{try{
   if(limited(ws,2400)){ws.close(4008,'Too many messages');return;}const msg=JSON.parse(raw);
   if(!ws.uid){if(msg.type!=='auth')return;const u=auth(msg.token);if(!u){ws.close(4001,'Invalid session');return;}if(clients.has(u.id)){send(ws,{type:'error',error:'Ya tienes una conexión activa.'});ws.close(4009);return;}ws.uid=u.id;ws.sessionToken=msg.token;clients.set(u.id,ws);clearTimeout(timer);send(ws,{type:'ready',user:pub(u)});return;}
   if(msg.type==='queue'&&!ws.match){queue.set(ws.uid,{ws,since:Date.now()});send(ws,{type:'queued'});}
   if(msg.type==='cancel'){queue.delete(ws.uid);send(ws,{type:'cancelled'});}
   if(msg.type==='move'&&ws.match&&Number.isFinite(msg.x)){const i=ws.match.players.indexOf(ws);ws.match.targets[i]=clamp(msg.x,-3.7,3.7)*(i===0?1:-1);}
  }catch{send(ws,{type:'error',error:'Mensaje no válido.'});}});
  ws.on('error',()=>{});ws.on('close',()=>{clearTimeout(timer);limits.delete(ws);if(clients.get(ws.uid)===ws){clients.delete(ws.uid);queue.delete(ws.uid);}if(ws.match)finish(ws.match,1-ws.match.players.indexOf(ws),'disconnect');});
 });
 const tick=setInterval(()=>{
  const entries=[...queue.values()];for(let i=0;i<entries.length;i++){const a=entries[i];if(!queue.has(a.ws.uid))continue;const b=entries.slice(i+1).find(b=>queue.has(b.ws.uid)&&Math.abs(user(a.ws.uid).rating-user(b.ws.uid).rating)<=100+Math.floor((Date.now()-Math.min(a.since,b.since))/1000)*10);if(!b)continue;queue.delete(a.ws.uid);queue.delete(b.ws.uid);const m={players:[a.ws,b.ws],game:createGame(),targets:[0,0],done:false,start:Date.now()+3000};m.game.playing=true;matches.add(m);m.players.forEach((ws,i)=>{ws.match=m;send(ws,{type:'matched',opponent:pub(user(m.players[1-i].uid)),countdown:3});});}
  for(const m of matches){if(Date.now()<m.start)continue;for(let i=0;i<2;i++){const key=i===0?'player':'cpu';m.game[key]+=clamp(m.targets[i]-m.game[key],-9/60,9/60);}step(m.game,1/60,'normal',true);m.players.forEach((ws,i)=>{const g=m.game;send(ws,{type:'state',state:{x:g.x*(i===0?1:-1),z:g.z*(i===0?1:-1),player:i===0?g.player:-g.cpu,cpu:i===0?g.cpu:-g.player,score:i===0?g.score:[...g.score].reverse(),playing:true,winner:null}});});if(m.game.winner!==null)finish(m,m.game.winner);}
 },1000/60);
 const heartbeat=setInterval(()=>{for(const ws of wss.clients){if(ws.uid&&!auth(ws.sessionToken)){ws.close(4001,'Session expired');continue;}if(!ws.alive){ws.terminate();continue;}ws.alive=false;ws.ping();}for(const [key,v] of limits)if(Date.now()-v.start>60000)limits.delete(key);db.prepare('DELETE FROM sessions WHERE expires<?').run(Date.now());},30000);
 return {server,close:async()=>{clearInterval(tick);clearInterval(heartbeat);for(const m of matches)m.done=true;for(const ws of wss.clients)ws.terminate();await new Promise(r=>wss.close(r));await new Promise(r=>server.close(r));db.close();}};
}
if(process.argv[1]&&import.meta.url===new URL(process.argv[1],'file:').href){const app=createServer();app.server.listen(Number(process.env.PORT||3001),'0.0.0.0',()=>console.log('3DPong server ready'));for(const signal of ['SIGTERM','SIGINT'])process.on(signal,async()=>{await app.close();process.exit(0);});}
