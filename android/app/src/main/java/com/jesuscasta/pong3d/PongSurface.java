package com.jesuscasta.pong3d;
import android.content.Context;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;
import android.view.MotionEvent;
import java.nio.*;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

public final class PongSurface extends GLSurfaceView implements GLSurfaceView.Renderer {
 private final NativeGame game;private int program,position,color,matrix;private long last;
 private final float[] projection=new float[16],view=new float[16],vp=new float[16];
 public PongSurface(Context context,NativeGame game){super(context);this.game=game;setEGLContextClientVersion(2);setRenderer(this);setPreserveEGLContextOnPause(true);}
 @Override public boolean onTouchEvent(MotionEvent e){if(e.getAction()==MotionEvent.ACTION_DOWN||e.getAction()==MotionEvent.ACTION_MOVE){synchronized(game){game.target=NativeGame.clamp((e.getX()/getWidth()-.5f)*12,-3.7f,3.7f);}return true;}if(e.getAction()==MotionEvent.ACTION_UP){performClick();return true;}return true;}
 @Override public boolean performClick(){super.performClick();return true;}
 private int shader(int type,String source){int id=GLES20.glCreateShader(type);GLES20.glShaderSource(id,source);GLES20.glCompileShader(id);int[] ok=new int[1];GLES20.glGetShaderiv(id,GLES20.GL_COMPILE_STATUS,ok,0);if(ok[0]==0)throw new IllegalStateException(GLES20.glGetShaderInfoLog(id));return id;}
 @Override public void onSurfaceCreated(GL10 gl,EGLConfig config){program=GLES20.glCreateProgram();GLES20.glAttachShader(program,shader(GLES20.GL_VERTEX_SHADER,"attribute vec3 a;uniform mat4 m;void main(){gl_Position=m*vec4(a,1.0);}"));GLES20.glAttachShader(program,shader(GLES20.GL_FRAGMENT_SHADER,"precision mediump float;uniform vec4 c;void main(){gl_FragColor=c;}"));GLES20.glLinkProgram(program);int[] ok=new int[1];GLES20.glGetProgramiv(program,GLES20.GL_LINK_STATUS,ok,0);if(ok[0]==0)throw new IllegalStateException(GLES20.glGetProgramInfoLog(program));position=GLES20.glGetAttribLocation(program,"a");color=GLES20.glGetUniformLocation(program,"c");matrix=GLES20.glGetUniformLocation(program,"m");GLES20.glEnable(GLES20.GL_DEPTH_TEST);GLES20.glClearColor(.03f,.05f,.09f,1);last=System.nanoTime();}
 @Override public void onSurfaceChanged(GL10 gl,int w,int h){GLES20.glViewport(0,0,w,h);float aspect=(float)w/h;float halfWidth=Math.max(6,10*aspect);Matrix.orthoM(projection,0,-halfWidth,halfWidth,-halfWidth/aspect,halfWidth/aspect,1,70);Matrix.setLookAtM(view,0,0,19,20,0,0,0,0,1,0);Matrix.multiplyMM(vp,0,projection,0,view,0);}
 @Override public void onDrawFrame(GL10 gl){long now=System.nanoTime();float dt=(now-last)/1e9f;last=now;GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT|GLES20.GL_DEPTH_BUFFER_BIT);GLES20.glUseProgram(program);GLES20.glUniformMatrix4fv(matrix,1,false,vp,0);synchronized(game){game.step(dt);box(0,-.2f,0,10,.2f,16,.07f,.12f,.2f);for(int n=-8;n<=8;n++)box(0,0,n,10,.02f,.025f,.15f,.2f,.3f);for(int n=-5;n<=5;n++)box(n,0,0,.025f,.02f,16,.15f,.2f,.3f);box(-5,.1f,0,.07f,.1f,16,.35f,.45f,.65f);box(5,.1f,0,.07f,.1f,16,.35f,.45f,.65f);box(game.player,.3f,7,2.2f,.4f,.35f,.45f,.96f,.8f);box(game.cpu,.3f,-7,2.2f,.4f,.35f,.73f,.61f,1);box(game.x,.35f,game.z,.4f,.4f,.4f,1,1,1);}}
 private void box(float x,float y,float z,float w,float h,float d,float r,float g,float b){float[] v={x-w/2,y-h/2,z-d/2,x+w/2,y-h/2,z-d/2,x+w/2,y+h/2,z-d/2,x-w/2,y+h/2,z-d/2,x-w/2,y-h/2,z+d/2,x+w/2,y-h/2,z+d/2,x+w/2,y+h/2,z+d/2,x-w/2,y+h/2,z+d/2};int[][] faces={{0,1,2,0,2,3},{4,6,5,4,7,6},{3,2,6,3,6,7},{0,5,1,0,4,5},{1,5,6,1,6,2},{0,3,7,0,7,4}};for(int f=0;f<6;f++){float[] data=new float[18];for(int i=0;i<6;i++)System.arraycopy(v,faces[f][i]*3,data,i*3,3);FloatBuffer buffer=ByteBuffer.allocateDirect(data.length*4).order(ByteOrder.nativeOrder()).asFloatBuffer();buffer.put(data).position(0);GLES20.glVertexAttribPointer(position,3,GLES20.GL_FLOAT,false,0,buffer);GLES20.glEnableVertexAttribArray(position);float shade=f==2?1:.65f;GLES20.glUniform4f(color,r*shade,g*shade,b*shade,1);GLES20.glDrawArrays(GLES20.GL_TRIANGLES,0,6);}}
}
