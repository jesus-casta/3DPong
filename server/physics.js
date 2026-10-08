export const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
export function createGame() { return {x:0,z:0,vx:2,vz:7,player:0,cpu:0,score:[0,0],playing:false,winner:null}; }
export function serve(g, direction=1) {g.x=0;g.z=0;g.vx=2;g.vz=7*direction;}
export function step(g, dt, difficulty='normal', humanOpponent=false) {
 if (!g.playing) return;
 dt=Math.min(dt, 0.03);
 const speed={easy:2.5,normal:4,hard:6}[difficulty] ?? 4;
 if(!humanOpponent) g.cpu=clamp(g.cpu+clamp(g.x-g.cpu,-speed*dt,speed*dt),-3.7,3.7);
 const old=g.z;g.x+=g.vx*dt;g.z+=g.vz*dt;
 if(Math.abs(g.x)>4.8){g.x=clamp(g.x,-4.8,4.8);g.vx=-g.vx;}
 for(const [z,p] of [[7,g.player],[-7,g.cpu]]) {
 if((z>0 && old<z && g.z>=z)||(z<0 && old>z && g.z<=z)) {
 if(Math.abs(g.x-p)<1.3){g.z=z;g.vz=-Math.sign(z)*Math.min(Math.abs(g.vz)*1.07,14);g.vx=(g.x-p)*5;}
 }
 }
 if(Math.abs(g.z)>8.2){const scorer=g.z<0?0:1;g.score[scorer]++; if(g.score[scorer]>=7){g.winner=scorer;g.playing=false;}serve(g,scorer===0?1:-1);}
}
