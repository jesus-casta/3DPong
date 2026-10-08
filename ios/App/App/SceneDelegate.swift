import UIKit
import MetalKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = .systemGroupedBackground
        window.tintColor = .systemBlue
        window.rootViewController = NativePongController()
        window.makeKeyAndVisible()
        self.window = window
    }
    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? NativePongController)?.pauseOffline()
    }
}

final class PongGame {
    var x: Float = 0, z: Float = 0, vx: Float = 2, vz: Float = 7
    var player: Float = 0, cpu: Float = 0, target: Float = 0, difficulty: Float = 4
    var mine = 0, theirs = 0, winner: Int? = nil
    var playing = false, online = false
    func reset() { x=0;z=0;vx=2;vz=7;player=0;cpu=0;target=0;mine=0;theirs=0;winner=nil;playing=false;online=false }
    func clamp(_ v: Float,_ a: Float,_ b: Float) -> Float { max(a,min(b,v)) }
    func step(_ elapsed: Float) {
        guard playing && !online else { return }; let dt = min(elapsed,0.03)
        player=target;cpu=clamp(cpu+clamp(x-cpu,-difficulty*dt,difficulty*dt),-3.7,3.7)
        let old=z;x += vx*dt;z += vz*dt
        if abs(x)>4.8 { x=clamp(x,-4.8,4.8);vx = -vx }
        if old<7 && z>=7 && abs(x-player)<1.3 { z=7;vz = -min(abs(vz)*1.07,14);vx=(x-player)*5 }
        if old > -7 && z <= -7 && abs(x-cpu)<1.3 { z = -7;vz=min(abs(vz)*1.07,14);vx=(x-cpu)*5 }
        if abs(z)>8.2 { let won=z<0;if won {mine += 1}else{theirs += 1};if mine>=7 || theirs>=7 {winner=mine>=7 ? 0 : 1;playing=false};x=0;z=0;vx=2;vz=won ? 7 : -7 }
    }
}

final class MetalArena: NSObject, MTKViewDelegate {
    let game: PongGame, device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, depth: MTLDepthStencilState
    var last = CACurrentMediaTime()
    init(view: MTKView, game: PongGame) throws {
        self.game=game
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {throw NSError(domain:"Metal",code:1)}
        self.device=device;self.queue=queue;view.device=device;view.depthStencilPixelFormat = .depth32Float;view.colorPixelFormat = .bgra8Unorm;view.clearColor=MTLClearColor(red:0.03,green:0.05,blue:0.09,alpha:1)
        let source="""
        #include <metal_stdlib>
        using namespace metal;
        struct V { packed_float3 p; packed_float3 c; };
        struct Out { float4 p [[position]]; float3 c; };
        vertex Out vertexMain(const device V* v [[buffer(0)]],uint i [[vertex_id]]) { Out o;o.p=float4(float3(v[i].p),1);o.c=float3(v[i].c);return o; }
        fragment float4 fragmentMain(Out in [[stage_in]]) { return float4(in.c,1); }
        """
        let library=try device.makeLibrary(source:source,options:nil),descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name:"vertexMain");descriptor.fragmentFunction=library.makeFunction(name:"fragmentMain");descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm;descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline=try device.makeRenderPipelineState(descriptor:descriptor)
        let dd=MTLDepthStencilDescriptor();dd.depthCompareFunction = .less;dd.isDepthWriteEnabled=true
        guard let depth=device.makeDepthStencilState(descriptor:dd) else {throw NSError(domain:"Metal",code:2)};self.depth=depth
        super.init();view.delegate=self
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now=CACurrentMediaTime();game.step(Float(now-last));last=now
        guard let drawable=view.currentDrawable,let descriptor=view.currentRenderPassDescriptor,let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:descriptor) else {return}
        let aspect=Float(view.drawableSize.width/max(view.drawableSize.height,1)),hw=max(6,10*aspect),hh=hw/aspect
        var data=[Float]()
        func box(_ x:Float,_ y:Float,_ z:Float,_ w:Float,_ h:Float,_ d:Float,_ color:SIMD3<Float>) {
            let v:[SIMD3<Float>]=[.init(x-w/2,y-h/2,z-d/2),.init(x+w/2,y-h/2,z-d/2),.init(x+w/2,y+h/2,z-d/2),.init(x-w/2,y+h/2,z-d/2),.init(x-w/2,y-h/2,z+d/2),.init(x+w/2,y-h/2,z+d/2),.init(x+w/2,y+h/2,z+d/2),.init(x-w/2,y+h/2,z+d/2)]
            let faces=[[0,1,2,0,2,3],[4,6,5,4,7,6],[3,2,6,3,6,7],[0,5,1,0,4,5],[1,5,6,1,6,2],[0,3,7,0,7,4]]
            for (f,face) in faces.enumerated(){let c=color*(f==2 ? 1 : 0.65);for i in face {let p=v[i];data += [p.x/hw,(p.y*0.725-p.z*0.689)/hh,0.5-(p.y+p.z)*0.015,c.x,c.y,c.z]}}
        }
        box(0,-0.2,0,10,0.2,16,.init(0.07,0.12,0.2))
        for n in -8...8 {box(0,0,Float(n),10,0.02,0.025,.init(0.15,0.2,0.3))}
        for n in -5...5 {box(Float(n),0,0,0.025,0.02,16,.init(0.15,0.2,0.3))}
        for x in [Float(-5),Float(5)] {box(x,0.1,0,0.07,0.1,16,.init(0.35,0.45,0.65))}
        box(game.player,0.3,7,2.2,0.4,0.35,.init(0.45,0.96,0.8));box(game.cpu,0.3,-7,2.2,0.4,0.35,.init(0.73,0.61,1));box(game.x,0.35,game.z,0.4,0.4,0.4,.init(1,1,1))
        data.withUnsafeBytes { bytes in
            guard let address=bytes.baseAddress,let buffer=device.makeBuffer(bytes:address,length:bytes.count,options:.storageModeShared) else {return}
            encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth);encoder.setVertexBuffer(buffer,offset:0,index:0);encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:data.count/6)
        }
        encoder.endEncoding();command.present(drawable);command.commit()
    }
}

final class NativePongController: UIViewController, UITextFieldDelegate {
    let game=PongGame(),score=UILabel(),status=UILabel(),profile=UILabel(),endpoint=UITextField(),name=UITextField(),password=UITextField()
    let search=UIButton(type:.system),play=UIButton(type:.system),reset=UIButton(type:.system)
    var renderer:MetalArena?,arena:MTKView!,timer:Timer?,socket:URLSessionWebSocketTask?,token:String?,base="",ready=false,queued=false,generation=0
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor = .systemGroupedBackground
        let stack=UIStackView();stack.axis = .vertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12),stack.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-16)])
        let title=UILabel();title.text="3DPong · Liga";title.font = .preferredFont(forTextStyle:.largeTitle);stack.addArrangedSubview(title)
        profile.text="Partidas rápidas y clasificación por nivel";profile.font = .preferredFont(forTextStyle:.caption1);stack.addArrangedSubview(profile)
        for (field,hint) in [(endpoint,"Servidor HTTPS"),(name,"Jugador"),(password,"Contraseña (mín. 10 caracteres)")] {field.placeholder=hint;field.borderStyle = .roundedRect;field.autocapitalizationType = .none;field.autocorrectionType = .no;field.delegate=self;field.returnKeyType = .done;stack.addArrangedSubview(field)}
        endpoint.keyboardType = .URL;endpoint.text=UserDefaults.standard.string(forKey:"endpoint");password.isSecureTextEntry=true;password.textContentType = .password;name.textContentType = .username
        let auth=row();stack.addArrangedSubview(auth);button(auth,"Entrar",#selector(login));button(auth,"Crear cuenta",#selector(register));button(auth,"Salir",#selector(logout))
        let online=row();stack.addArrangedSubview(online);search.setTitle("Buscar rival",for:.normal);search.addTarget(self,action:#selector(matchmake),for:.touchUpInside);online.addArrangedSubview(search);button(online,"Ranking",#selector(ranking))
        status.text="Arrastra para mover la pala";status.font = .preferredFont(forTextStyle:.caption1);status.numberOfLines=2;stack.addArrangedSubview(status)
        score.textAlignment = .center;score.font = .monospacedDigitSystemFont(ofSize:24,weight:.medium);stack.addArrangedSubview(score)
        arena=MTKView();arena.layer.cornerRadius=16;arena.clipsToBounds=true;arena.heightAnchor.constraint(greaterThanOrEqualToConstant:160).isActive=true;stack.addArrangedSubview(arena);arena.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(drag(_:))))
        do {renderer=try MetalArena(view:arena,game:game)}catch{status.text="Este dispositivo no puede inicializar Metal"}
        let controls=row();stack.addArrangedSubview(controls);play.setTitle("Jugar / pausa",for:.normal);play.addTarget(self,action:#selector(toggle),for:.touchUpInside);controls.addArrangedSubview(play);reset.setTitle("Reiniciar",for:.normal);reset.addTarget(self,action:#selector(restart),for:.touchUpInside);controls.addArrangedSubview(reset)
        let difficulty=UISegmentedControl(items:["Relax","Clásica","Intensa"]);difficulty.selectedSegmentIndex=1;difficulty.addTarget(self,action:#selector(level(_:)),for:.valueChanged);stack.addArrangedSubview(difficulty)
        timer=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self] _ in self?.pulse()}
    }
    func textFieldShouldReturn(_ textField:UITextField)->Bool {textField.resignFirstResponder();return true}
    func row()->UIStackView{let r=UIStackView();r.axis = .horizontal;r.distribution = .fillEqually;r.spacing=8;r.heightAnchor.constraint(equalToConstant:44).isActive=true;return r}
    func button(_ row:UIStackView,_ title:String,_ action:Selector){let b=UIButton(type:.system);b.setTitle(title,for:.normal);b.addTarget(self,action:action,for:.touchUpInside);row.addArrangedSubview(b)}
    func pulse(){score.text="TÚ  \(game.mine) — \(game.theirs)  \(game.online ? "RIVAL" : "CPU")";play.isEnabled = !game.online;reset.isEnabled = !game.online;if let winner=game.winner,!game.playing {status.text=winner==0 ? "Victoria · juega otra partida" : "Derrota · juega otra partida"};if game.online && game.playing {send(["type":"move","x":game.target])}}
    @objc func drag(_ gesture:UIPanGestureRecognizer){view.endEditing(true);game.target=game.clamp(Float(gesture.location(in:arena).x/max(arena.bounds.width,1)-0.5)*12,-3.7,3.7)}
    @objc func toggle(){if game.winner != nil {game.reset()};game.playing.toggle();view.endEditing(true)}
    @objc func restart(){game.reset()}
    @objc func level(_ sender:UISegmentedControl){game.difficulty=[2.5,4,6][sender.selectedSegmentIndex]}
    func pauseOffline(){if !game.online {game.playing=false}}
    func configure()->Bool{let text=(endpoint.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/"));guard let url=URLComponents(string:text),url.scheme=="https",url.host != nil,url.user==nil,url.password==nil,url.path.isEmpty,url.query==nil,url.fragment==nil else {status.text="Introduce la dirección HTTPS del servidor, sin rutas";return false};base=text;UserDefaults.standard.set(text,forKey:"endpoint");return true}
    func request(_ path:String,body:[String:Any]?=nil,auth:String?=nil,completion:@escaping(Any)->Void){guard let url=URL(string:base+path) else{return};var request=URLRequest(url:url);request.timeoutInterval=15;if let body=body{request.httpMethod="POST";request.httpBody=try? JSONSerialization.data(withJSONObject:body);request.setValue("application/json",forHTTPHeaderField:"Content-Type")};if let auth=auth{request.setValue("Bearer "+auth,forHTTPHeaderField:"Authorization")}
        URLSession.shared.dataTask(with:request){[weak self] data,response,error in DispatchQueue.main.async {guard let self=self else{return};guard error==nil,let data=data,let json=try? JSONSerialization.jsonObject(with:data),let response=response as? HTTPURLResponse else{self.status.text="No se pudo conectar";return};guard (200...299).contains(response.statusCode) else{self.status.text=(json as? [String:Any])?["error"] as? String ?? "Error del servidor";return};completion(json)}}.resume()
    }
    @objc func login(){account(false)}
    @objc func register(){account(true)}
    func account(_ register:Bool){guard !game.online else{status.text="Termina la partida antes de cambiar de cuenta";return};guard configure() else{return};request(register ? "/api/register" : "/api/login",body:["name":name.text ?? "","password":password.text ?? ""]){[weak self] json in guard let self=self,let data=json as? [String:Any],let token=data["token"] as? String,let user=data["user"] as? [String:Any] else{return};self.token=token;self.password.text="";self.showProfile(user);self.connect()}}
    func showProfile(_ u:[String:Any]){profile.text="\(u["name"] as? String ?? "") · \(u["rating"] as? Int ?? 1000) Elo · \(u["wins"] as? Int ?? 0) victorias"}
    func connect(){generation += 1;let id=generation;socket?.cancel(with:.normalClosure,reason:nil);ready=false;guard let url=URL(string:base.replacingOccurrences(of:"https://",with:"wss://")+"/socket") else{return};let task=URLSession.shared.webSocketTask(with:url);socket=task;task.resume();send(["type":"auth","token":token ?? ""]);receive(task,id:id)}
    func send(_ message:[String:Any]){guard let data=try? JSONSerialization.data(withJSONObject:message),let text=String(data:data,encoding:.utf8) else{return};socket?.send(.string(text)){[weak self] error in if error != nil {DispatchQueue.main.async{self?.status.text="No se pudo enviar al servidor"}}}}
    func receive(_ task:URLSessionWebSocketTask,id:Int){task.receive{[weak self] result in DispatchQueue.main.async {guard let self=self,id==self.generation else{return};switch result {case .success(let message):if case .string(let text)=message,let data=text.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any]{self.message(json)};self.receive(task,id:id);case .failure:self.ready=false;self.queued=false;self.game.online=false;self.game.playing=false;self.search.setTitle("Buscar rival",for:.normal);self.status.text="Desconectado. Inicia sesión para reconectar."}}}}
    func message(_ m:[String:Any]){switch m["type"] as? String {
    case "ready":ready=true;if let u=m["user"] as? [String:Any]{showProfile(u)};status.text="Conectado"
    case "queued":queued=true;search.setTitle("Cancelar",for:.normal);status.text="Buscando rival de nivel similar…"
    case "cancelled":queued=false;search.setTitle("Buscar rival",for:.normal);status.text="Búsqueda cancelada"
    case "matched":queued=false;search.setTitle("Buscar rival",for:.normal);game.reset();game.online=true;let opponent=m["opponent"] as? [String:Any];status.text="Contra \(opponent?["name"] as? String ?? "rival") · empieza en 3 segundos"
    case "state":guard let s=m["state"] as? [String:Any],let score=s["score"] as? [Int],score.count==2 else{return};game.x=(s["x"] as? NSNumber)?.floatValue ?? 0;game.z=(s["z"] as? NSNumber)?.floatValue ?? 0;game.player=(s["player"] as? NSNumber)?.floatValue ?? 0;game.cpu=(s["cpu"] as? NSNumber)?.floatValue ?? 0;game.mine=score[0];game.theirs=score[1];game.playing=true
    case "result":game.online=false;game.playing=false;let won=m["won"] as? Bool ?? false;game.winner=won ? 0 : 1;if let score=m["score"] as? [Int],score.count==2 {game.mine=score[0];game.theirs=score[1]};if let u=m["user"] as? [String:Any]{showProfile(u)};status.text=won ? "Victoria" : "Derrota"
    case "error":status.text=m["error"] as? String
    default:break}}
    @objc func matchmake(){guard ready else{status.text="Primero inicia sesión";return};send(["type":queued ? "cancel" : "queue"])}
    @objc func ranking(){guard configure() else{return};request("/api/ranking"){[weak self] json in guard let self=self,let rows=json as? [[String:Any]] else{return};let text=rows.enumerated().map{"\($0.offset+1). \($0.element["name"] as? String ?? "") · \($0.element["rating"] as? Int ?? 0) Elo"}.joined(separator:"\n");let alert=UIAlertController(title:"Ranking",message:text.isEmpty ? "Todavía no hay jugadores" : text,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"Cerrar",style:.default));self.present(alert,animated:true)}}
    @objc func logout(){if game.online {let alert=UIAlertController(title:"Salir de la partida",message:"Salir concede la victoria al rival.",preferredStyle:.alert);alert.addAction(UIAlertAction(title:"Salir",style:.destructive){[weak self] _ in self?.doLogout()});alert.addAction(UIAlertAction(title:"Cancelar",style:.cancel));present(alert,animated:true)}else{doLogout()}}
    func doLogout(){guard let token=token else{return};request("/api/logout",body:[:],auth:token){[weak self] _ in guard let self=self else{return};self.generation += 1;self.socket?.cancel(with:.normalClosure,reason:nil);self.token=nil;self.ready=false;self.queued=false;self.game.online=false;self.game.playing=false;self.profile.text="Sesión cerrada";self.search.setTitle("Buscar rival",for:.normal)}}
    deinit{timer?.invalidate();socket?.cancel(with:.normalClosure,reason:nil)}
}
