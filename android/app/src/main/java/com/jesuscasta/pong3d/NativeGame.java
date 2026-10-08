package com.jesuscasta.pong3d;

/** Offline simulation; ranked matches use the authoritative server instead. */
public final class NativeGame {
 public float x,z,vx=2,vz=7,player,cpu;
 public int mine,theirs; public boolean playing,online; public int winner=-1;
 public float target; public float difficulty=4;
 public static float clamp(float v,float a,float b){return Math.max(a,Math.min(b,v));}
 public void reset(){x=z=player=cpu=target=0;vx=2;vz=7;mine=theirs=0;winner=-1;playing=false;online=false;}
 public void step(float dt){
  if(!playing||online)return;dt=Math.min(dt,.03f);player=target;cpu=clamp(cpu+clamp(x-cpu,-difficulty*dt,difficulty*dt),-3.7f,3.7f);
  float old=z;x+=vx*dt;z+=vz*dt;if(Math.abs(x)>4.8f){x=clamp(x,-4.8f,4.8f);vx=-vx;}
  if(old<7&&z>=7&&Math.abs(x-player)<1.3f){z=7;vz=-Math.min(Math.abs(vz)*1.07f,14);vx=(x-player)*5;}
  if(old>-7&&z<=-7&&Math.abs(x-cpu)<1.3f){z=-7;vz=Math.min(Math.abs(vz)*1.07f,14);vx=(x-cpu)*5;}
  if(Math.abs(z)>8.2f){boolean won=z<0;if(won)mine++;else theirs++;if(mine>=7||theirs>=7){winner=mine>=7?0:1;playing=false;}x=z=0;vx=2;vz=won?7:-7;}
 }
}
