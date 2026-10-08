#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
result_dir=$(mktemp -d)
trap 'rm -rf "$result_dir"' EXIT
cat > "$result_dir/PhysicsCheck.java" <<'JAVA'
import com.jesuscasta.pong3d.NativeGame;
public class PhysicsCheck {
 static void check(boolean ok,String name){if(!ok)throw new AssertionError(name);System.out.println("PASS "+name);}
 public static void main(String[] args){
  NativeGame g=new NativeGame();g.step(.02f);check(g.z==0,"pause");
  g.playing=true;g.x=4.79f;g.vx=5;g.step(.03f);check(g.vx<0&&g.x<=4.8f,"wall bounce");
  g.reset();g.playing=true;g.z=6.95f;g.vx=0;g.step(.02f);check(g.vz<0,"paddle return");
  g.reset();g.playing=true;g.z=8.19f;g.x=4;g.step(.02f);check(g.theirs==1&&g.z==0,"miss scores");
  g.reset();g.playing=true;g.z=-8.19f;g.vz=-7;g.mine=6;g.step(.02f);check(g.winner==0&&!g.playing,"match ends at seven");
  g.reset();g.playing=true;g.online=true;g.step(.02f);check(g.z==0,"online clients do not simulate");
 }
}
JAVA
"${JAVA_HOME:+$JAVA_HOME/bin/}javac" -d "$result_dir" android/app/src/main/java/com/jesuscasta/pong3d/NativeGame.java "$result_dir/PhysicsCheck.java"
"${JAVA_HOME:+$JAVA_HOME/bin/}java" -cp "$result_dir" PhysicsCheck
