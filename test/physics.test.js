import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createGame,step} from '../server/physics.js';
test('paused game does not advance',()=>{const g=createGame();step(g,.02);assert.equal(g.z,0);});
test('ball bounces off side wall',()=>{const g=createGame();Object.assign(g,{playing:true,x:4.79,vx:5});step(g,.03);assert.ok(g.vx<0);assert.ok(g.x<=4.8);});
test('player returns ball with paddle',()=>{const g=createGame();Object.assign(g,{playing:true,z:6.95,x:0,vx:0,vz:7});step(g,.02);assert.ok(g.vz<0);assert.equal(g.score[1],0);});
test('miss awards point and serves again',()=>{const g=createGame();Object.assign(g,{playing:true,z:8.19,x:4,vz:7});step(g,.02);assert.equal(g.score[1],1);assert.equal(g.z,0);});
test('seven points ends match',()=>{const g=createGame();Object.assign(g,{playing:true,z:-8.19,vz:-7});g.score[0]=6;step(g,.02);assert.equal(g.winner,0);assert.equal(g.playing,false);});
