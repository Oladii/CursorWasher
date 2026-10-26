import Foundation
import CoreGraphics

/// Painting coordinates stay in the approved source's top-left 1254px space.
struct FoamCluster: Equatable {
    var id = "", assetFile = ""
    var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0
    var variant = 0
    var mirrorX = false
    var opacity: CGFloat = 1
    var maskActive = true
    var surfaceReveal: CGFloat = 1, localMaskOffsetY: CGFloat = 0
    var maskScale: CGFloat = 1
    var supportX: CGFloat?, supportY: CGFloat?, occlusionDepthY: CGFloat?
    var surfaceX: CGFloat?, surfaceY: CGFloat?
    var position: CGPoint { CGPoint(x: 32 + (x+width/2)*128/1254, y: 160-(y+height/2)*128/1254) }
    var size: CGSize { CGSize(width: width*128/1254, height: height*128/1254) }
}

struct FoamFrame: Equatable {
    var clusters: [FoamCluster] = []
    var agitation = 0.0
    var offset = CGPoint.zero
    var foregroundOffset: CGFloat = 0
    var maskFile = "anchors/rest-mask.json"
    var maskOffsetX: CGFloat = 0, maskOffsetY: CGFloat = 0, maskHorizontalScale: CGFloat = 1
    var physicalOpeningOffset: CGFloat?
    var usePhysicalOpening = false
    var flowPhase = 0.0
    func translated(by delta: CGPoint) -> Self {
        var result = self; result.offset.x += delta.x; result.offset.y += delta.y; return result
    }
}

struct FoamArtwork {
    struct Sprite { let id: String, file: String; let original: Bool; let pivot: CGPoint, foot: CGPoint }
    struct Sample { let time: Double; let frame: FoamFrame }
    let directory: URL, sprites: [Sprite], baseAssetFile: String
    let normal: [Sample], interrupted: [Sample]
    let referenceCut: Double, restTime: Double, releaseDuration: Double
    let xmin: Double, xmax: Double, columns: [String: [Double]]
    var isAvailable: Bool { sprites.count == 36 && !normal.isEmpty }
    var rest: FoamFrame { normal.first?.frame ?? FoamFrame() }
    static let bundled: FoamArtwork = {
        let directory = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.resourceURL!.appendingPathComponent("Foam", isDirectory: true)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Foam")
        return (try? load(from: directory)) ?? FoamArtwork(directory: directory, sprites: [],
            baseAssetFile: "figma-assets/1ce55.png", normal: [], interrupted: [], referenceCut: 1.81,
            restTime: 3.65, releaseDuration: 1.4, xmin: 301, xmax: 987, columns: [:])
    }()
    static func load(from directory: URL) throws -> Self {
        struct Point: Decodable { let x: Double, y: Double; var value: CGPoint { CGPoint(x: x,y: y) } }
        struct Object: Decodable { let id: String, file: String; let original: Bool; let pivot: Point, foot: Point }
        struct Metadata: Decodable {
            let schemaVersion: Int, objectCount: Int, originalObjectCount: Int
            let baseAssetFile: String, sequenceFile: String, waterGeometryFile: String
            let referenceCut: Double, normalRestTime: Double, releaseDuration: Double
            let objects: [Object]
        }
        struct Slot: Decodable {
            let id: String, assetFile: String
            let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
            let mirrorX: Bool?, opacity: CGFloat?, maskActive: Bool
            let surfaceReveal: CGFloat?, localMaskOffsetY: CGFloat?
            let supportX: CGFloat?, supportY: CGFloat?, occlusionDepthY: CGFloat?, surfaceX: CGFloat?, surfaceY: CGFloat?
        }
        struct Frame: Decodable {
            let timeSeconds: Double, slots: [Slot], chapter: Int?, videoIndex: Int?
            let maskFile: String?, maskOffsetX: CGFloat?, maskOffsetY: CGFloat?, maskHorizontalScale: CGFloat?
            let physicalOpeningOffset: CGFloat?, usePhysicalOpening: Bool?, inertiaPhase: Double?
        }
        struct Sequence: Decodable { let frames: [Frame] }
        struct Water: Decodable { let xmin: Double, xmax: Double; let columns: [String: [Double]] }
        let decoder = JSONDecoder()
        let m = try decoder.decode(Metadata.self, from: Data(contentsOf: directory.appendingPathComponent("metadata.json")))
        guard m.schemaVersion == 3, m.objectCount == 36, m.originalObjectCount == 8,
              m.objects.count == 36, Set(m.objects.map(\.id)).count == 36 else {
            throw NSError(domain: "CursorWasher.FoamArtwork", code: 3)
        }
        let variants = Dictionary(uniqueKeysWithValues: m.objects.enumerated().map { ($1.id,$0) })
        let originals = Set(m.objects.filter(\.original).map(\.id))
        let sequence = try decoder.decode(Sequence.self, from: Data(contentsOf: directory.appendingPathComponent(m.sequenceFile)))
        let water = try decoder.decode(Water.self, from: Data(contentsOf: directory.appendingPathComponent(m.waterGeometryFile)))
        var chapters = [[Double: FoamFrame](), [Double: FoamFrame]()]
        for source in sequence.frames where source.videoIndex != nil {
            guard let chapter = source.chapter, chapters.indices.contains(chapter) else { continue }
            var f = FoamFrame()
            f.maskFile = source.maskFile ?? f.maskFile
            f.maskOffsetX = source.maskOffsetX ?? 0; f.maskOffsetY = source.maskOffsetY ?? 0
            f.maskHorizontalScale = source.maskHorizontalScale ?? 1
            f.physicalOpeningOffset = source.physicalOpeningOffset
            f.usePhysicalOpening = source.usePhysicalOpening ?? false
            f.flowPhase = source.inertiaPhase ?? 0
            f.clusters = try source.slots.map { s in
                guard let variant = variants[s.id], m.objects[variant].file == s.assetFile,
                      [s.x,s.y,s.width,s.height].allSatisfy(\.isFinite), s.width > 0, s.height > 0 else {
                    throw NSError(domain: "CursorWasher.FoamArtwork", code: 4)
                }
                return FoamCluster(id:s.id,assetFile:s.assetFile,x:s.x,y:s.y,width:s.width,height:s.height,
                    variant:variant,mirrorX:s.mirrorX ?? false,opacity:s.opacity ?? 1,maskActive:s.maskActive,
                    surfaceReveal:s.surfaceReveal ?? 1,localMaskOffsetY:s.localMaskOffsetY ?? 0,
                    supportX:s.supportX,supportY:s.supportY,occlusionDepthY:s.occlusionDepthY,
                    surfaceX:s.surfaceX,surfaceY:s.surfaceY)
            }
            f.agitation = f.clusters.filter { !originals.contains($0.id) }.reduce(0) { $0+Double($1.surfaceReveal) }/25
            chapters[chapter][source.timeSeconds] = f
        }
        let samples = chapters.map { $0.sorted { $0.key < $1.key }.map { Sample(time:$0.key,frame:$0.value) } }
        guard samples[0].count > 200, samples[1].count > 200, samples[0].first!.frame.clusters.count == 8 else {
            throw NSError(domain: "CursorWasher.FoamArtwork", code: 5)
        }
        return FoamArtwork(directory:directory,sprites:m.objects.map {
            Sprite(id:$0.id,file:$0.file,original:$0.original,pivot:$0.pivot.value,foot:$0.foot.value)
        },baseAssetFile:m.baseAssetFile,normal:samples[0],interrupted:samples[1],referenceCut:m.referenceCut,
            restTime:m.normalRestTime,releaseDuration:m.releaseDuration,xmin:water.xmin,xmax:water.xmax,columns:water.columns)
    }
    func frame(at time: Double, chapter: Int = 0) -> FoamFrame {
        let samples = chapter == 1 ? interrupted : normal
        guard let first = samples.first, let last = samples.last else { return FoamFrame() }
        if time <= first.time { return first.frame }; if time >= last.time { return last.frame }
        var lo = 0, hi = samples.count-1
        while hi-lo > 1 { let m=(lo+hi)/2; if samples[m].time <= time { lo=m } else { hi=m } }
        let a=samples[lo],b=samples[hi]
        if abs(time-a.time)<1e-9 { return a.frame }; if abs(time-b.time)<1e-9 { return b.frame }
        return interpolate(a.frame,b.frame,(time-a.time)/(b.time-a.time))
    }
    func interpolate(_ a: FoamFrame,_ b: FoamFrame,_ u: Double) -> FoamFrame {
        var f = u < 0.5 ? a : b
        f.agitation=mix(a.agitation,b.agitation,u)
        let phaseB=b.flowPhase == 0 && a.flowPhase > .pi ? ceil(a.flowPhase/(2 * .pi))*2 * .pi:b.flowPhase
        f.flowPhase=mix(a.flowPhase,phaseB,u)
        f.maskOffsetX=mix(a.maskOffsetX,b.maskOffsetX,u);f.maskOffsetY=mix(a.maskOffsetY,b.maskOffsetY,u)
        f.maskHorizontalScale=mix(a.maskHorizontalScale,b.maskHorizontalScale,u)
        f.physicalOpeningOffset=optionalMix(a.physicalOpeningOffset,b.physicalOpeningOffset,u)
        let aa=Dictionary(uniqueKeysWithValues:a.clusters.map{($0.id,$0)}),bb=Dictionary(uniqueKeysWithValues:b.clusters.map{($0.id,$0)})
        let order=(u<0.5 ? a.clusters:b.clusters).map(\.id)
        let ids=order+(u<0.5 ? b.clusters:a.clusters).map(\.id).filter{!order.contains($0)}
        f.clusters=ids.compactMap { id in
            guard var s=aa[id] ?? bb[id] else { return nil }
            if let x=aa[id],let y=bb[id] {
                s.x=mix(x.x,y.x,u);s.y=mix(x.y,y.y,u);s.width=mix(x.width,y.width,u);s.height=mix(x.height,y.height,u)
                s.surfaceReveal=mix(x.surfaceReveal,y.surfaceReveal,u);s.opacity=mix(x.opacity,y.opacity,u)
                s.localMaskOffsetY=mix(x.localMaskOffsetY,y.localMaskOffsetY,u)
                s.supportX=optionalMix(x.supportX,y.supportX,u);s.supportY=optionalMix(x.supportY,y.supportY,u)
                s.surfaceX=optionalMix(x.surfaceX,y.surfaceX,u);s.surfaceY=optionalMix(x.surfaceY,y.surfaceY,u)
                s.occlusionDepthY=optionalMix(x.occlusionDepthY,y.occlusionDepthY,u)
                if a.flowPhase != 0 || b.flowPhase != 0 {
                    // Screen-space chords through the measured water contour
                    // can turn backwards between valid samples. Interpolate
                    // the actual painted centre in its polar water space.
                    let pa=uv(centre(x)),pb=uv(centre(y))
                    let angle=atan2(Double(pa.y),Double(pa.x))
                    let delta=wrap(atan2(Double(pb.y),Double(pb.x))-angle)
                    let p=project(radius:mix(hypot(Double(pa.x),Double(pa.y)),hypot(Double(pb.x),Double(pb.y)),u),angle:angle+delta*u)
                    let sprite=sprites[s.variant]
                    s.x=p.x-sprite.pivot.x*s.width;s.y=p.y-sprite.pivot.y*s.height
                    s.surfaceX=p.x;s.surfaceY=p.y
                    s.supportX=s.x+sprite.foot.x*s.width
                    let raw=s.y+sprite.foot.y*s.height,c=column(Double(s.supportX!))
                    s.supportY=min(CGFloat(c.1),max(CGFloat(c.0),raw))
                }
            } else { s.surfaceReveal *= CGFloat(aa[id] == nil ? u:1-u) }
            return s.surfaceReveal>1e-8 ? s:nil
        }
        return f
    }
    func centre(_ s:FoamCluster)->CGPoint {
        let p=sprites[s.variant].pivot;return CGPoint(x:s.x+p.x*s.width,y:s.y+p.y*s.height)
    }
    func uv(_ p:CGPoint)->CGPoint {
        let u=min(0.99999,max(-0.99999,(Double(p.x)-(xmin+xmax)/2)/((xmax-xmin)/2))),c=column(Double(p.x))
        let f=min(1,max(-1,(2*Double(p.y)-c.0-c.1)/max(0.001,c.1-c.0)))
        return CGPoint(x:u,y:f*sqrt(1-u*u))
    }
    func project(radius:Double,angle:Double)->CGPoint {
        let u=min(0.99999,max(-0.99999,radius*cos(angle))),x=(xmin+xmax)/2+(xmax-xmin)/2*u,c=column(x)
        let f=min(1,max(-1,radius*sin(angle)/max(0.0001,sqrt(1-u*u))))
        return CGPoint(x:x,y:(c.0+c.1)/2+(c.1-c.0)/2*f)
    }
    func column(_ value:Double)->(Double,Double) {
        let x=min(xmax,max(xmin,value)),lo=floor(x),hi=ceil(x)
        guard let a=columns[String(Int(lo))],let b=columns[String(Int(hi))] else { return (336,500) }
        return (mix(a[0],b[0],x-lo),mix(a[1],b[1],x-lo))
    }
    func maskTranslation(from file:String,to target:String,scale:CGFloat)->CGPoint {
        func origin(_ name:String)->CGPoint {
            guard let data=try? Data(contentsOf:directory.appendingPathComponent(name)),
                  let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                  let m=json["relativeTransform"] as? [[NSNumber]],m.count == 2,m[0].count == 3,m[1].count == 3 else { return .zero }
            return CGPoint(x:CGFloat(truncating:m[0][2]),y:CGFloat(truncating:m[1][2]))
        }
        let a=origin(file),b=origin(target)
        return CGPoint(x:(a.x-b.x)*scale,y:a.y-b.y)
    }
}
private func mix<T:BinaryFloatingPoint>(_ a:T,_ b:T,_ u:Double)->T { a+(b-a)*T(u) }
private func optionalMix(_ a:CGFloat?,_ b:CGFloat?,_ u:Double)->CGFloat? {
    guard let x=a ?? b,let y=b ?? a else { return nil };return mix(x,y,u)
}
private func smooth(_ v:Double)->Double { let u=min(1,max(0,v));return u*u*u*(10+u*(-15+6*u)) }
private func hermite(_ a:Double,_ velocity:Double,_ b:Double,_ t:Double,_ duration:Double)->Double {
    let u=min(1,max(0,t/duration))
    return (2*u*u*u-3*u*u+1)*a+(u*u*u-2*u*u+u)*velocity*duration+(-2*u*u*u+3*u*u)*b
}
private func wrap(_ a:Double)->Double { atan2(sin(a),cos(a)) }
private func orderedDepths(_ clusters:[FoamCluster])->[String:Double] {
    var blocks:[(first:Int,last:Int,total:Double,weight:Double)]=[]
    for (i,s) in clusters.enumerated() {
        let depth=Double(s.occlusionDepthY ?? s.supportY ?? (s.y+s.height*0.82))
        blocks.append((i,i,depth-Double(i)*0.01,1))
        while blocks.count>1 && blocks[blocks.count-2].total/blocks[blocks.count-2].weight>blocks.last!.total/blocks.last!.weight {
            let z=blocks.removeLast(),a=blocks.removeLast()
            blocks.append((a.first,z.last,a.total+z.total,a.weight+z.weight))
        }
    }
    var result:[String:Double]=[:]
    for b in blocks { for i in b.first...b.last { result[clusters[i].id]=b.total/b.weight+Double(i)*0.01 } }
    return result
}

/// Approved samples are immutable. Other cancellation times own an immutable
/// captured pose and velocity; they never jump to the 1.81-second reference.
struct FoamAnimation {
    static let settleDuration=1.4
    private(set) var enabled=false
    private(set) var agitation=0.0
    private let artwork:FoamArtwork
    private var startedAt:Double?
    private var release:Release?
    private var currentFrame=FoamFrame()
    private var acceptsImplicitCycle=true
    private struct Node {
        let source:FoamCluster,goal:FoamCluster?
        let start:CGPoint,velocity:CGPoint
        let radius:Double,radiusSpeed:Double,angle:Double,distance:Double,angularSpeed:Double
        let drag:Double?,widthSpeed:Double,heightSpeed:Double,initialDepth:Double
    }
    private struct Release {
        let startedAt:Double,duration:Double,reference:Bool,orbiting:Bool
        let source:FoamFrame,nodes:[Node]
        let maskTranslation:CGPoint
    }
    init(artwork:FoamArtwork = .bundled) { self.artwork=artwork }
    var snapshot:FoamFrame { currentFrame }
    var isSettling:Bool { enabled && (startedAt != nil || release != nil) }
    mutating func setEnabled(_ value:Bool) { enabled=value;reset();acceptsImplicitCycle=true }
    mutating func begin(_ animation:WashAnimation,at time:TimeInterval) {
        reset();acceptsImplicitCycle=false;if enabled && artwork.isAvailable { startedAt=time }
    }
    mutating func cancel(at time:TimeInterval) {
        advance(at:time)
        guard release == nil,let start=startedAt else { return }
        let elapsed=max(0,time-start)
        if elapsed<=0 || currentFrame == artwork.rest { reset();return }
        release=makeRelease(at:time,elapsed:elapsed);startedAt=nil
    }
    @discardableResult mutating func update(at time:TimeInterval,frame:WashAnimationFrame?,reduceMotion:Bool=false)->FoamFrame {
        guard enabled else { return FoamFrame() }
        if reduceMotion { reset();acceptsImplicitCycle=frame == nil;return snapshot }
        if let f=frame,startedAt == nil,release == nil,acceptsImplicitCycle,
           f.waterImpulses.contains(where:{$0.kind == .dip && $0.isActive}) {
            startedAt=time-f.phase.start-f.phaseProgress*f.phase.duration;acceptsImplicitCycle=false
        }
        if frame == nil,let start=startedAt,time-start<2.0833333333333335 { cancel(at:time) }
        advance(at:time)
        if frame == nil && startedAt == nil && release == nil { acceptsImplicitCycle=true }
        return snapshot
    }
    private mutating func reset() {
        startedAt=nil;release=nil;agitation=0;currentFrame=enabled ? artwork.rest:FoamFrame()
    }
    private mutating func advance(at time:Double) {
        if let r=release {
            let elapsed=max(0,time-r.startedAt)
            if elapsed>=r.duration { reset();return }
            if elapsed<=1e-12 { currentFrame=r.source }
            else if r.reference {
                // CUT lies between two authored 60Hz samples. Bridge only the
                // unsampled sliver from the exact captured runtime snapshot.
                let next=artwork.interrupted.first{$0.time>artwork.referenceCut+1e-9}!
                let span=next.time-artwork.referenceCut
                currentFrame=elapsed<span
                    ? artwork.interpolate(r.source,next.frame,elapsed/span)
                    : artwork.frame(at:artwork.referenceCut+elapsed,chapter:1)
            }
            else { currentFrame=releaseFrame(r,at:elapsed) }
        } else if let start=startedAt {
            let elapsed=max(0,time-start)
            if elapsed>=artwork.restTime { reset();return }
            currentFrame=artwork.frame(at:elapsed)
        }
        agitation=currentFrame.agitation
    }
    private func makeRelease(at time:Double,elapsed:Double)->Release {
        let e=1.0/600
        let before=Dictionary(uniqueKeysWithValues:artwork.frame(at:max(0,elapsed-e)).clusters.map{($0.id,$0)})
        let after=Dictionary(uniqueKeysWithValues:artwork.frame(at:elapsed+e).clusters.map{($0.id,$0)})
        let homes=Dictionary(uniqueKeysWithValues:artwork.rest.clusters.map{($0.id,$0)})
        let full=Dictionary(uniqueKeysWithValues:artwork.frame(at:67.0/60).clusters.map{($0.id,$0)})
        let orbiting=elapsed>67.0/60+0.001
        let depths=orderedDepths(currentFrame.clusters)
        var winding=0.0
        if orbiting {
            for s in currentFrame.clusters where homes[s.id] != nil {
                let o=artwork.uv(artwork.centre(full[s.id]!)),p=artwork.uv(artwork.centre(s)),h=artwork.uv(artwork.centre(homes[s.id]!))
                let base=atan2(Double(o.y),Double(o.x))
                let a=base+currentFrame.flowPhase+wrap(atan2(Double(p.y),Double(p.x))-base-currentFrame.flowPhase)
                let b=base+wrap(atan2(Double(h.y),Double(h.x))-base)
                winding=max(winding,ceil((a-b)/(.pi*2)-1e-9))
            }
        }
        var maximumDistance=0.0,speeds:[Double]=[],nodes:[Node]=[]
        for s in currentFrame.clusters {
            let p=artwork.centre(s),uv=artwork.uv(p),prior=before[s.id] ?? s,next=after[s.id] ?? s
            let pa=artwork.centre(prior),pb=artwork.centre(next),ua=artwork.uv(pa),ub=artwork.uv(pb)
            let speed=orbiting ? max(0,wrap(atan2(Double(ub.y),Double(ub.x))-atan2(Double(ua.y),Double(ua.x)))/(2*e)):0
            var a=atan2(Double(uv.y),Double(uv.x)),distance=0.0
            if orbiting {
                let o=artwork.uv(artwork.centre(full[s.id] ?? s)),base=atan2(Double(o.y),Double(o.x))
                a=base+currentFrame.flowPhase+wrap(a-base-currentFrame.flowPhase)
                if let goal=homes[s.id] {
                    let h=artwork.uv(artwork.centre(goal))
                    distance=max(0,base+wrap(atan2(Double(h.y),Double(h.x))-base)+winding * .pi * 2-a)
                } else { distance=max(0,winding * .pi * 2-currentFrame.flowPhase) }
            }
            maximumDistance=max(maximumDistance,distance)
            if artwork.sprites[s.variant].original { speeds.append(speed) }
            nodes.append(Node(source:s,goal:homes[s.id],start:p,velocity:CGPoint(x:(pb.x-pa.x)/(2*e),y:(pb.y-pa.y)/(2*e)),
                radius:hypot(Double(uv.x),Double(uv.y)),radiusSpeed:(hypot(Double(ub.x),Double(ub.y))-hypot(Double(ua.x),Double(ua.y)))/(2*e),
                angle:a,distance:distance,angularSpeed:speed,drag:nil,widthSpeed:Double(next.width-prior.width)/(2*e),heightSpeed:Double(next.height-prior.height)/(2*e),initialDepth:depths[s.id]!))
        }
        let reference=abs(elapsed-artwork.referenceCut)<1e-6,speed=speeds.reduce(0,+)/Double(max(1,speeds.count))
        let duration=reference || !orbiting ? artwork.releaseDuration:max(artwork.releaseDuration,min(3.5,2*maximumDistance/max(0.5,speed)))
        nodes=nodes.map { n in
            var drag:Double?
            if n.angularSpeed>1e-8 && n.distance>0 && n.distance<n.angularSpeed*duration/2 {
                var lo=0.0,hi=64.0
                while n.angularSpeed*coastIntegral(duration,drag:hi,duration:duration)>n.distance && hi<1e8 { hi*=2 }
                for _ in 0..<60 { let mid=(lo+hi)/2
                    if n.angularSpeed*coastIntegral(duration,drag:mid,duration:duration)>n.distance { lo=mid } else { hi=mid }
                }
                drag=(lo+hi)/2
            }
            return Node(source:n.source,goal:n.goal,start:n.start,velocity:n.velocity,radius:n.radius,radiusSpeed:n.radiusSpeed,
                angle:n.angle,distance:n.distance,angularSpeed:n.angularSpeed,drag:drag,widthSpeed:n.widthSpeed,heightSpeed:n.heightSpeed,initialDepth:n.initialDepth)
        }
        return Release(startedAt:time,duration:duration,reference:reference,orbiting:orbiting,source:currentFrame,nodes:nodes,
            maskTranslation:artwork.maskTranslation(from:currentFrame.maskFile,to:artwork.rest.maskFile,scale:currentFrame.maskHorizontalScale))
    }
    private func coastIntegral(_ t:Double,drag k:Double,duration T:Double)->Double {
        if k<0.01 {
            let n=24,h=t/24
            func f(_ x:Double)->Double { let u=x/T;return exp(-k*x)*(1-3*u*u+2*u*u*u) }
            var sum=f(0)+f(t)
            for i in 1..<n { sum += (i%2 == 1 ? 4:2)*f(Double(i)*h) }
            return h/3*sum
        }
        let z=k*t,e=exp(-z),i0=(1-e)/k,i2=(2-e*(2+2*z+z*z))/(k*k*k)
        let i3=(6-e*(6+6*z+3*z*z+z*z*z))/(k*k*k*k)
        return max(0,i0-3*i2/(T*T)+2*i3/(T*T*T))
    }
    private func releaseFrame(_ r:Release,at elapsed:Double)->FoamFrame {
        let u=elapsed/r.duration,home=smooth((elapsed-0.18)/(r.duration-0.18))
        var f=r.source
        f.agitation=r.source.agitation*(1-smooth(u));f.maskOffsetX=mix(f.maskOffsetX+r.maskTranslation.x,artwork.rest.maskOffsetX,home)
        f.maskOffsetY=mix(f.maskOffsetY+r.maskTranslation.y,artwork.rest.maskOffsetY,home);f.maskHorizontalScale=mix(f.maskHorizontalScale,artwork.rest.maskHorizontalScale,home)
        f.maskFile=artwork.rest.maskFile
        if let value=r.source.physicalOpeningOffset { f.physicalOpeningOffset=CGFloat(Double(value)*(1-home)) }
        if home>0.99 { f.usePhysicalOpening=artwork.rest.usePhysicalOpening }
        let restDepth=orderedDepths(artwork.rest.clusters)
        let poses:[(cluster:FoamCluster,order:CGFloat)]=r.nodes.compactMap { n in
            var s=n.source
            let sprite=artwork.sprites[s.variant]
            var p=n.start
            if r.orbiting {
                let advance=n.drag.map{min(n.distance,n.angularSpeed*coastIntegral(elapsed,drag:$0,duration:r.duration))}
                    ?? hermite(0,n.angularSpeed,n.distance,elapsed,r.duration)
                let goal=n.goal.map{artwork.uv(artwork.centre($0))}
                let targetRadius=goal.map{hypot(Double($0.x),Double($0.y))} ?? n.radius
                let radius=min(0.99999,max(0.001,hermite(n.radius,n.radiusSpeed,targetRadius,elapsed,r.duration)))
                p=artwork.project(radius:radius,angle:n.angle+max(0,advance))
            } else if let goal=n.goal {
                let h=artwork.centre(goal)
                p=CGPoint(x:hermite(Double(p.x),Double(n.velocity.x),Double(h.x),elapsed,r.duration),y:hermite(Double(p.y),Double(n.velocity.y),Double(h.y),elapsed,r.duration))
            } else { p.x += n.velocity.x*CGFloat(elapsed*exp(-10*elapsed));p.y += n.velocity.y*CGFloat(elapsed*exp(-10*elapsed)) }
            if let goal=n.goal {
                s.width=CGFloat(max(1,hermite(Double(s.width),n.widthSpeed,Double(goal.width),elapsed,r.duration)))
                s.height=CGFloat(max(1,hermite(Double(s.height),n.heightSpeed,Double(goal.height),elapsed,r.duration)))
                s.maskActive=s.maskActive || goal.maskActive
                s.maskScale=mix(n.source.maskActive ? n.source.maskScale:4,goal.maskScale,home)
                let from=n.source.localMaskOffsetY
                let to=goal.localMaskOffsetY
                s.localMaskOffsetY=mix(from,to,home)
            } else {
                s.width += CGFloat(n.widthSpeed*elapsed*exp(-10*elapsed));s.height += CGFloat(n.heightSpeed*elapsed*exp(-10*elapsed))
                let phase=Double(s.variant),start=0.08+0.22*(phase*0.61803398875).truncatingRemainder(dividingBy:1)
                let end=r.duration-0.04-0.20*(phase*0.41421356237).truncatingRemainder(dividingBy:1)
                s.surfaceReveal *= CGFloat(1-smooth((elapsed-start)/max(0.1,end-start)))
                if s.surfaceReveal<1e-6 { return nil }
            }
            s.x=p.x-sprite.pivot.x*s.width;s.y=p.y-sprite.pivot.y*s.height;s.surfaceX=p.x;s.surfaceY=p.y
            let sx=s.x+sprite.foot.x*s.width,raw=s.y+sprite.foot.y*s.height,c=artwork.column(Double(sx))
            s.supportX=sx;s.supportY=min(CGFloat(c.1),max(CGFloat(c.0),raw))
            var depth=CGFloat(mix(n.initialDepth,Double(raw),smooth(elapsed/0.10)))
            if let target=restDepth[s.id] { depth=mix(depth,CGFloat(target),home) }
            let sourceDepth=n.source.occlusionDepthY ?? n.source.supportY ?? (n.source.y+n.source.height*0.82)
            var cursorDepth=mix(sourceDepth,raw,smooth(elapsed/0.10))
            if let goal=n.goal {
                let target=goal.occlusionDepthY ?? goal.supportY ?? (goal.y+goal.height*0.82)
                cursorDepth=mix(cursorDepth,target,home)
            }
            s.occlusionDepthY=cursorDepth
            return (s,depth)
        }
        f.clusters=poses.sorted{$0.order<$1.order}.map(\.cluster)
        return f
    }
}
