/*
library
canvas 3D Models 
License MIT 
Author NelikKKL
good using :3 !!!!!
 */
 /*
Библиотека
canvas 3D модели
Лицензия MIT 
Автор NelikKKL
Хорошего использования  Няя :3 !!!!!
 */
/*
⣇⣿⠘⣿⣿⣿⡿⡿⣟⣟⢟⢟⢝⠵⡝⣿⡿⢂⣼⣿⣷⣌⠩⡫⡻⣝⠹⢿⣿⣷
⡆⣿⣆⠱⣝⡵⣝⢅⠙⣿⢕⢕⢕⢕⢝⣥⢒⠅⣿⣿⣿⡿⣳⣌⠪⡪⣡⢑⢝⣇
⡆⣿⣿⣦⠹⣳⣳⣕⢅⠈⢗⢕⢕⢕⢕⢕⢈⢆⠟⠋⠉⠁⠉⠉⠁⠈⠼⢐⢕⢽
⡗⢰⣶⣶⣦⣝⢝⢕⢕⠅⡆⢕⢕⢕⢕⢕⣴⠏⣠⡶⠛⡉⡉⡛⢶⣦⡀⠐⣕⢕
⡝⡄⢻⢟⣿⣿⣷⣕⣕⣅⣿⣔⣕⣵⣵⣿⣿⢠⣿⢠⣮⡈⣌⠨⠅⠹⣷⡀⢱⢕
⡝⡵⠟⠈⢀⣀⣀⡀⠉⢿⣿⣿⣿⣿⣿⣿⣿⣼⣿⢈⡋⠴⢿⡟⣡⡇⣿⡇⡀⢕
⡝⠁⣠⣾⠟⡉⡉⡉⠻⣦⣻⣿⣿⣿⣿⣿⣿⣿⣿⣧⠸⣿⣦⣥⣿⡇⡿⣰⢗⢄
⠁⢰⣿⡏⣴⣌⠈⣌⠡⠈⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣬⣉⣉⣁⣄⢖⢕⢕⢕
⡀⢻⣿⡇⢙⠁⠴⢿⡟⣡⡆⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣵⣵⣿
⡻⣄⣻⣿⣌⠘⢿⣷⣥⣿⠇⣿⣿⣿⣿⣿⣿⠛⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣷⢄⠻⣿⣟⠿⠦⠍⠉⣡⣾⣿⣿⣿⣿⣿⣿⢸⣿⣦⠙⣿⣿⣿⣿⣿⣿⣿⣿⠟
⡕⡑⣑⣈⣻⢗⢟⢞⢝⣻⣿⣿⣿⣿⣿⣿⣿⠸⣿⠿⠃⣿⣿⣿⣿⣿⣿⡿⠁⣠
⡝⡵⡈⢟⢕⢕⢕⢕⣵⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣶⣿⣿⣿⣿⣿⠿⠋⣀⣈⠙
⡝⡵⡕⡀⠑⠳⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠛⢉⡠⡲⡫⡪⡪⡣ 
*/

// ── Pre-compiled regexes (avoids new RegExp() in hot loops) ──────────────────
const RE_SHAPE     = /^(image3|cube3|pyramid3|triangle3|sphere3|cylinder3)/;
const RE_MONO_ID   = /__mono\((\d+)\)/;
const RE_MONO_BLOCK = /mono\s*\(([\s\S]*?)\)/g;
const RE_PROPS     = /(\w+)\(([^)]*)\)/g;
const RE_ANIM_KV   = /([a-z]+)(-?[\d.]+)/g;

// ── Static geometry (normalized, s=1) — built once, reused every frame ───────
const CUBE_V = [
    {x:-1,y:-1,z:-1},{x:1,y:-1,z:-1},{x:1,y:1,z:-1},{x:-1,y:1,z:-1},
    {x:-1,y:-1,z:1}, {x:1,y:-1,z:1}, {x:1,y:1,z:1}, {x:-1,y:1,z:1}
];
const CUBE_F     = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[2,3,7,6],[0,3,7,4],[1,2,6,5]];
const PYRAMID_V  = [{x:0,y:-1,z:0},{x:-1,y:1,z:-1},{x:1,y:1,z:-1},{x:1,y:1,z:1},{x:-1,y:1,z:1}];
const PYRAMID_F  = [[0,2,1],[0,3,2],[0,4,3],[0,1,4],[4,3,2,1]];
const TRIANGLE_V = [{x:0,y:-1,z:0},{x:1,y:1,z:0},{x:-1,y:1,z:0}];
const TRIANGLE_F = [[0,1,2]];
const IMAGE_V    = [{x:-1,y:-1,z:0},{x:1,y:-1,z:0},{x:1,y:1,z:0},{x:-1,y:1,z:0}];

// Sphere & cylinder built once and cached
const GEO_CACHE = {};
function buildSphereGeo() {
    if (GEO_CACHE.sphere) return GEO_CACHE.sphere;
    const lat = 8, lon = 8, v = [], faces = [];
    for (let la = 0; la <= lat; la++) {
        const theta = la * Math.PI / lat, sinT = Math.sin(theta), cosT = Math.cos(theta);
        for (let lo = 0; lo <= lon; lo++) {
            const phi = lo * 2 * Math.PI / lon;
            v.push({ x: Math.cos(phi) * sinT, y: cosT, z: Math.sin(phi) * sinT });
        }
    }
    for (let la = 0; la < lat; la++)
        for (let lo = 0; lo < lon; lo++) {
            const f = la * (lon + 1) + lo, s2 = f + lon + 1;
            faces.push([f, s2, f + 1]);
            faces.push([s2, s2 + 1, f + 1]);
        }
    return GEO_CACHE.sphere = { v, faces };
}
function buildCylinderGeo() {
    if (GEO_CACHE.cylinder) return GEO_CACHE.cylinder;
    const seg = 10, v = [], faces = [];
    for (let i = 0; i < seg; i++) {
        const theta = i * Math.PI * 2 / seg, cx = Math.cos(theta), cz = Math.sin(theta);
        v.push({ x: cx, y: -1, z: cz });
        v.push({ x: cx, y:  1, z: cz });
    }
    v.push({ x: 0, y: -1, z: 0 }, { x: 0, y: 1, z: 0 });
    const tc = v.length - 2, bc = v.length - 1;
    for (let i = 0; i < seg; i++) {
        const ct = i * 2, cb = ct + 1, nt = ((i + 1) % seg) * 2, nb = nt + 1;
        faces.push([ct, nt, nb, cb]);
        faces.push([tc, ct, nt]);
        faces.push([bc, nb, cb]);
    }
    return GEO_CACHE.cylinder = { v, faces };
}

// ── Custom element ────────────────────────────────────────────────────────────
class OmmModel extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.canvas = document.createElement('canvas');
        this.ctx = this.canvas.getContext('2d');
        this.shadowRoot.appendChild(this.canvas);

        this.camera = { z: 600, rx: 0.4, ry: 0.4, cx: 0, cy: 0 };
        this.objects = [];
        this.monoGroups = {};
        this.textures = {};
        this.focal = 600;
        this.isAnimating = false;
        this.animationRequested = false;
        // Per-frame camera trig cache — computed once in render(), shared per vertex
        this._cam = { srx: 0, crx: 1, sry: 0, cry: 1 };
    }

    connectedCallback() {
        this.canvas.style.cssText = 'width:100%;height:100%;display:block';
        if (this.hasAttribute('freer')) this.initControls();
        setTimeout(() => { this.resize(); this.loadContent(); }, 50);
    }

    initControls() {
        let isDragging = false, dragMode = 0, lastX = 0, lastY = 0;
        let initialPinchDist = null, initialZ = null;
        this.canvas.style.cursor = 'grab';

        const startDrag = (x, y, btn) => {
            isDragging = true; lastX = x; lastY = y;
            dragMode = (btn === 2 || btn === 1) ? 1 : 0;
            this.canvas.style.cursor = dragMode === 0 ? 'grabbing' : 'move';
        };
        const doDrag = (x, y) => {
            if (!isDragging) return;
            const dx = x - lastX, dy = y - lastY;
            lastX = x; lastY = y;
            if (dragMode === 0) { this.camera.ry -= dx * 0.01; this.camera.rx += dy * 0.01; }
            else                { this.camera.cx += dx;        this.camera.cy += dy; }
            if (!this.isAnimating) this.render();
        };
        const endDrag = () => { isDragging = false; this.canvas.style.cursor = 'grab'; };

        this.canvas.addEventListener('mousedown', e => startDrag(e.clientX, e.clientY, e.button));
        window.addEventListener('mousemove', e => { if (isDragging) doDrag(e.clientX, e.clientY); });
        window.addEventListener('mouseup', endDrag);
        this.canvas.addEventListener('contextmenu', e => e.preventDefault());
        this.canvas.addEventListener('wheel', e => {
            e.preventDefault();
            this.camera.z += e.deltaY * 0.5;
            if (this.camera.z < -this.focal + 10) this.camera.z = -this.focal + 10;
            if (!this.isAnimating) this.render();
        }, { passive: false });

        this.canvas.addEventListener('touchstart', e => {
            e.preventDefault();
            if (e.touches.length === 1) {
                startDrag(e.touches[0].clientX, e.touches[0].clientY, 0);
            } else if (e.touches.length === 2) {
                isDragging = false;
                initialPinchDist = Math.hypot(
                    e.touches[0].clientX - e.touches[1].clientX,
                    e.touches[0].clientY - e.touches[1].clientY);
                initialZ = this.camera.z;
            }
        }, { passive: false });

        this.canvas.addEventListener('touchmove', e => {
            e.preventDefault();
            if (e.touches.length === 1 && isDragging) {
                doDrag(e.touches[0].clientX, e.touches[0].clientY);
            } else if (e.touches.length === 2 && initialPinchDist) {
                const d = Math.hypot(
                    e.touches[0].clientX - e.touches[1].clientX,
                    e.touches[0].clientY - e.touches[1].clientY);
                this.camera.z = initialZ * (initialPinchDist / d);
                if (this.camera.z < -this.focal + 10) this.camera.z = -this.focal + 10;
                if (!this.isAnimating) this.render();
            }
        }, { passive: false });

        this.canvas.addEventListener('touchend', () => { endDrag(); initialPinchDist = null; });
    }

    async loadContent() {
        const content = this.getAttribute('src') || this.textContent.trim();
        if (content.endsWith('.omm')) {
            try {
                const res = await fetch(content);
                if (res.ok) this.parse(await res.text());
                else console.error(`OMM Error: failed to load ${content}`);
            } catch (e) { console.error('OMM Error:', e); }
        } else {
            this.parse(content);
        }
        if (this.hasAttribute('autorate') || this.isAnimating) {
            this.isAnimating = true;
            if (!this.animationRequested) { this.animationRequested = true; this.animate(); }
        } else {
            this.render();
        }
    }

    resize() {
        this.canvas.width  = this.offsetWidth  || 300;
        this.canvas.height = this.offsetHeight || 300;
    }

    // ── Parser ────────────────────────────────────────────────────────────────

    parse(txt) {
        this.objects = [];
        this.monoGroups = {};
        let current = null;
        let monoCounter = 0;
        const monoGroupDefs = {};

        // Pre-process mono(...) blocks — extract group transforms, tag shape lines
        RE_MONO_BLOCK.lastIndex = 0;
        const collapsed = txt.replace(RE_MONO_BLOCK, (_, inner) => {
            const id = monoCounter++;
            const gt = { x: 0, y: 0, z: 0, rx: 0, ry: 0, scale: 1 };
            let shapeFound = false;
            const lines = inner.split('\n');
            const out = lines.map(line => {
                const t = line.trim();
                if (!t || t.startsWith('//')) return line;
                const isShape = RE_SHAPE.test(t);
                if (!shapeFound && !isShape) {
                    RE_PROPS.lastIndex = 0;
                    let m;
                    while ((m = RE_PROPS.exec(t)) !== null) {
                        const v = parseFloat(m[2]);
                        switch (m[1]) {
                            case 'x': gt.x = v; break; case 'y': gt.y = v; break;
                            case 'z': gt.z = v; break; case 'scale': gt.scale = v; break;
                            case 'rr': gt.ry = v * Math.PI / 180; break;
                            case 'ru': gt.rx = v * Math.PI / 180; break;
                        }
                    }
                    return '';
                }
                if (isShape) { shapeFound = true; return t + ` __mono(${id})`; }
                return line;
            });
            monoGroupDefs[id] = gt;
            return out.join('\n');
        });

        const lines = collapsed.split('\n');
        for (let li = 0; li < lines.length; li++) {
            const l = lines[li].trim();
            if (!l || l.startsWith('//')) continue;

            const shapeMatch = RE_SHAPE.exec(l);
            if (shapeMatch) {
                const typeStr = shapeMatch[1];
                let sy = 1;
                const colonIdx = l.indexOf(':');
                if (colonIdx !== -1) sy = 1 / parseFloat(l.slice(colonIdx + 1));

                const monoMatch = RE_MONO_ID.exec(l);
                const monoId = monoMatch ? parseInt(monoMatch[1]) : null;

                current = {
                    type: typeStr.slice(0, -1), // strip trailing '3'
                    x: 0, y: 0, z: 0, s: 50, sy,
                    rx: 0, ry: 0,
                    col: '200,200,200',
                    rgb: [200, 200, 200], // pre-parsed RGB for fast shading
                    tex: null,
                    ur: 0, ul: 0, ug: 0, um: 0, ud: 0, uu: 0,
                    monoId,
                    anim: null, animIndex: 0, animSpeed: 2.0
                };

                if (monoId !== null) {
                    if (!this.monoGroups[monoId])
                        this.monoGroups[monoId] = { members: [] };
                    this.monoGroups[monoId].members.push(current);
                }
                this.objects.push(current);
            }

            if (current) {
                RE_PROPS.lastIndex = 0;
                let m;
                while ((m = RE_PROPS.exec(l)) !== null) {
                    const k = m[1], raw = m[2];
                    switch (k) {
                        case 'x':       current.x   = parseFloat(raw); break;
                        case 'y':       current.y   = parseFloat(raw); break;
                        case 'z':       current.z   = parseFloat(raw); break;
                        case 'scale':   current.s  *= parseFloat(raw); break;
                        case 'rr':      current.ry  = parseFloat(raw) * Math.PI / 180; break;
                        case 'ru':      current.rx  = parseFloat(raw) * Math.PI / 180; break;
                        case 'color': {
                            current.col = raw.replace(/\s/g, '');
                            const p = current.col.split(',');
                            current.rgb = [parseInt(p[0]), parseInt(p[1]), parseInt(p[2])];
                            break;
                        }
                        case 'texture': current.tex = this.getImg(raw.trim()); break;
                        case 'ur': current.ur = parseFloat(raw); break;
                        case 'ul': current.ul = parseFloat(raw); break;
                        case 'ug': current.ug = parseFloat(raw); break;
                        case 'um': current.um = parseFloat(raw); break;
                        case 'ud': current.ud = parseFloat(raw); break;
                        case 'uu': current.uu = parseFloat(raw); break;
                        case 'animation': {
                            current.anim = [];
                            const frames = raw.split(',');
                            for (let fi = 0; fi < frames.length; fi++) {
                                const kf = {};
                                RE_ANIM_KV.lastIndex = 0;
                                let am;
                                while ((am = RE_ANIM_KV.exec(frames[fi])) !== null)
                                    kf[am[1]] = parseFloat(am[2]);
                                current.anim.push(kf);
                            }
                            this.isAnimating = true;
                            break;
                        }
                    }
                }
            }
        }

        // Apply mono group-level transforms
        for (const id in monoGroupDefs) {
            const gt = monoGroupDefs[id];
            const group = this.monoGroups[id];
            if (!group) continue;
            const cosRy = Math.cos(gt.ry), sinRy = Math.sin(gt.ry);
            const cosRx = Math.cos(gt.rx), sinRx = Math.sin(gt.rx);
            for (let i = 0; i < group.members.length; i++) {
                const obj = group.members[i];
                obj.s *= gt.scale;
                const lx = obj.x, ly = obj.y, lz = obj.z;
                const rx1 =  lx * cosRy + lz * sinRy;
                const rz1 = -lx * sinRy + lz * cosRy;
                const ry1 =  ly * cosRx - rz1 * sinRx;
                const rz2 =  ly * sinRx + rz1 * cosRx;
                obj.x  = rx1 * gt.scale + gt.x;
                obj.y  = ry1 * gt.scale + gt.y;
                obj.z  = rz2 * gt.scale + gt.z;
                obj.rx += gt.rx;
                obj.ry += gt.ry;
            }
        }

        this.render();
    }

    // ── Texture cache ─────────────────────────────────────────────────────────

    getImg(src) {
        if (this.textures[src]) return this.textures[src];
        const img = new Image();
        img.src = src;
        img.onload = () => this.render();
        return this.textures[src] = img;
    }

    // ── Projection (uses per-frame camera trig from this._cam) ───────────────
    // Object trig is cached per object per frame inside render() to avoid
    // recomputing cos/sin for every vertex of the same object.

    projectV(px, py, pz, cosRx, sinRx, cosRy, sinRy, ox, oy, oz) {
        // Object rotation
        let ty = py * cosRx - pz * sinRx;
        let tz = py * sinRx + pz * cosRx;
        let tx = px * cosRy + tz * sinRy;
        tz     = -px * sinRy + tz * cosRy;
        tx += ox; ty += oy; tz += oz;

        // Camera rotation (pre-cached)
        const { srx, crx, sry, cry } = this._cam;
        let ry = ty * crx - tz * srx;
        let rz = ty * srx + tz * crx;
        const rx = tx * cry + rz * sry;
        rz        = -tx * sry + rz * cry;

        const sc = this.focal / (this.focal + rz + this.camera.z);
        return {
            x: rx * sc + this.canvas.width  * 0.5 + this.camera.cx,
            y: ry * sc + this.canvas.height * 0.5 + this.camera.cy,
            z: rz
        };
    }

    // ── Textured triangle ─────────────────────────────────────────────────────

    drawTexturedTriangle(p1, p2, p3, u1, v1, u2, v2, u3, v3, img) {
        const ctx = this.ctx;
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(p1.x, p1.y);
        ctx.lineTo(p2.x, p2.y);
        ctx.lineTo(p3.x, p3.y);
        ctx.closePath();
        ctx.clip();
        const det  = (u2 - u1) * (v3 - v1) - (u3 - u1) * (v2 - v1);
        const idet = 1 / det;
        const m11 = ((p2.x - p1.x) * (v3 - v1) - (p3.x - p1.x) * (v2 - v1)) * idet;
        const m12 = ((p2.y - p1.y) * (v3 - v1) - (p3.y - p1.y) * (v2 - v1)) * idet;
        const m21 = ((p3.x - p1.x) * (u2 - u1) - (p2.x - p1.x) * (u3 - u1)) * idet;
        const m22 = ((p3.y - p1.y) * (u2 - u1) - (p2.y - p1.y) * (u3 - u1)) * idet;
        ctx.setTransform(m11, m12, m21, m22,
            p1.x - m11 * u1 - m21 * v1,
            p1.y - m12 * u1 - m22 * v1);
        ctx.drawImage(img, 0, 0);
        ctx.restore();
    }

    // ── Animation loop ────────────────────────────────────────────────────────

    animate() {
        if (!this.isAnimating) return;
        if (this.hasAttribute('autorate')) this.camera.ry += 0.01;

        const objs = this.objects;
        for (let i = 0; i < objs.length; i++) {
            const obj = objs[i];
            if (!obj.anim || obj.anim.length === 0) continue;

            const target   = obj.anim[obj.animIndex];
            const speed    = obj.animSpeed;
            const rotSpeed = 0.05;

            const tx   = target.x  !== undefined ? target.x  : obj.x;
            const ty   = target.y  !== undefined ? target.y  : obj.y;
            const tz   = target.z  !== undefined ? target.z  : obj.z;
            const trx  = target.ru !== undefined ? target.ru * Math.PI / 180 : obj.rx;
            const try_ = target.rr !== undefined ? target.rr * Math.PI / 180 : obj.ry;

            const dx = tx - obj.x, dy = ty - obj.y, dz = tz - obj.z;
            const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);

            if (dist > speed) {
                const inv = speed / dist;
                obj.x += dx * inv; obj.y += dy * inv; obj.z += dz * inv;
            } else {
                obj.x = tx; obj.y = ty; obj.z = tz;
            }

            const drx = trx - obj.rx, dry = try_ - obj.ry;
            obj.rx = Math.abs(drx) > rotSpeed ? obj.rx + Math.sign(drx) * rotSpeed : trx;
            obj.ry = Math.abs(dry) > rotSpeed ? obj.ry + Math.sign(dry) * rotSpeed : try_;

            if (dist <= speed && Math.abs(drx) <= rotSpeed && Math.abs(dry) <= rotSpeed)
                if (++obj.animIndex >= obj.anim.length) obj.animIndex = 0;
        }

        this.render();
        requestAnimationFrame(() => this.animate());
    }

    // ── Render ────────────────────────────────────────────────────────────────

    render() {
        const ctx = this.ctx;
        const W   = this.canvas.width, H = this.canvas.height;
        ctx.clearRect(0, 0, W, H);

        // Cache camera trig once per frame
        this._cam.srx = Math.sin(this.camera.rx);
        this._cam.crx = Math.cos(this.camera.rx);
        this._cam.sry = Math.sin(this.camera.ry);
        this._cam.cry = Math.cos(this.camera.ry);

        // Compute mono group average Z for unified depth sorting
        const monoGroupZ = {};
        for (const id in this.monoGroups) {
            const members = this.monoGroups[id].members;
            let zSum = 0;
            for (let i = 0; i < members.length; i++) zSum += members[i].z;
            monoGroupZ[id] = zSum / members.length;
        }

        // Depth sort (back-to-front)
        this.objects.sort((a, b) => {
            const az = (a.monoId != null && monoGroupZ[a.monoId] !== undefined) ? monoGroupZ[a.monoId] : a.z;
            const bz = (b.monoId != null && monoGroupZ[b.monoId] !== undefined) ? monoGroupZ[b.monoId] : b.z;
            return bz - az;
        });

        const objs = this.objects;
        for (let oi = 0; oi < objs.length; oi++) {
            const obj  = objs[oi];
            const s    = obj.s, sy = s * obj.sy;
            const type = obj.type;

            // Geometry selection
            let rawV, faces;
            if      (type === 'cube')     { rawV = CUBE_V;     faces = CUBE_F; }
            else if (type === 'pyramid')  { rawV = PYRAMID_V;  faces = PYRAMID_F; }
            else if (type === 'triangle') { rawV = TRIANGLE_V; faces = TRIANGLE_F; }
            else if (type === 'sphere')   { const g = buildSphereGeo();   rawV = g.v; faces = g.faces; }
            else if (type === 'cylinder') { const g = buildCylinderGeo(); rawV = g.v; faces = g.faces; }
            else if (type === 'image')    { rawV = IMAGE_V; faces = null; }
            else continue;

            // Cache object trig once per object (shared across all vertices)
            const cosRx = Math.cos(obj.rx), sinRx = Math.sin(obj.rx);
            const cosRy = Math.cos(obj.ry), sinRy = Math.sin(obj.ry);
            const ox = obj.x, oy = obj.y, oz = obj.z;

            const hasDeform = obj.ur || obj.ul || obj.ug || obj.um || obj.ud || obj.uu;
            const nv  = rawV.length;
            const pts = new Array(nv);

            for (let vi = 0; vi < nv; vi++) {
                const rv = rawV[vi];
                let vx = rv.x * s, vy = rv.y * sy, vz = rv.z * s;

                if (hasDeform) {
                    if (vx > 0)       vx = (vx / s)  * (s  + obj.ur);
                    else if (vx < 0)  vx = (vx / s)  * (s  + obj.ul);
                    if (vy > 0 && sy) vy = (vy / sy) * (sy + obj.ud);
                    else if (vy < 0 && sy) vy = (vy / sy) * (sy + obj.uu);
                    if (vz > 0)       vz = (vz / s)  * (s  + obj.ug);
                    else if (vz < 0)  vz = (vz / s)  * (s  + obj.um);
                }

                pts[vi] = this.projectV(vx, vy, vz, cosRx, sinRx, cosRy, sinRy, ox, oy, oz);
            }

            // Image: two triangles, no face loop
            if (type === 'image') {
                if (obj.tex && obj.tex.complete) {
                    const tw = obj.tex.width, th = obj.tex.height;
                    this.drawTexturedTriangle(pts[0], pts[1], pts[2], 0, 0, tw, 0, tw, th, obj.tex);
                    this.drawTexturedTriangle(pts[0], pts[2], pts[3], 0, 0, tw, th, 0, th, obj.tex);
                }
                continue;
            }

            // Face depth sort
            const nf = faces.length;
            const sortedFaces = new Array(nf);
            for (let fi = 0; fi < nf; fi++) {
                const f = faces[fi];
                let zSum = 0;
                for (let k = 0; k < f.length; k++) zSum += pts[f[k]].z;
                sortedFaces[fi] = { f, i: fi, z: zSum / f.length };
            }
            sortedFaces.sort((a, b) => b.z - a.z);

            const hasTex = obj.tex && obj.tex.complete;
            const tw = hasTex ? obj.tex.width : 0, th = hasTex ? obj.tex.height : 0;
            const rgb = obj.rgb;

            for (let fi = 0; fi < nf; fi++) {
                const fd = sortedFaces[fi];
                const f  = fd.f;
                const p1 = pts[f[0]], p2 = pts[f[1]], p3 = pts[f[2]];

                if (hasTex) {
                    if (f.length === 4) {
                        const p4 = pts[f[3]];
                        this.drawTexturedTriangle(p1, p2, p3, 0,      0,  tw, 0,  tw, th, obj.tex);
                        this.drawTexturedTriangle(p1, p3, p4, 0,      0,  tw, th, 0,  th, obj.tex);
                    } else {
                        this.drawTexturedTriangle(p1, p2, p3, tw*0.5, 0,  tw, th, 0,  th, obj.tex);
                    }
                } else {
                    ctx.beginPath();
                    ctx.moveTo(p1.x, p1.y);
                    ctx.lineTo(p2.x, p2.y);
                    ctx.lineTo(p3.x, p3.y);
                    if (f.length === 4) ctx.lineTo(pts[f[3]].x, pts[f[3]].y);
                    ctx.closePath();

                    // Shading: bitwise OR instead of Math.floor for int conversion
                    let sh;
                    const idx = fd.i;
                    if      (type === 'sphere')   sh = 0.8  + (idx % 8)  * 0.05;
                    else if (type === 'cylinder') sh = 0.85 + (idx % 10) * 0.04;
                    else                          sh = 0.85 + (idx % nf) * 0.05;
                    if (sh > 1) sh = 1;

                    ctx.fillStyle   = `rgb(${rgb[0]*sh|0},${rgb[1]*sh|0},${rgb[2]*sh|0})`;
                    ctx.fill();
                    ctx.strokeStyle = 'rgba(0,0,0,0.15)';
                    ctx.stroke();
                }
            }
        }
    }
}

customElements.define('omm-model', OmmModel);
