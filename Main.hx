import js.Browser;
import js.html.KeyboardEvent;
import js.html.MouseEvent;

typedef Box = {x:Float, y:Float, z:Float, w:Float, h:Float, d:Float};
typedef Coin = {m:Dynamic, x:Float, y:Float, z:Float, got:Bool};

/**
 * マリオ64風 3Dアクション(プロトタイプ)
 * - Haxe -> JS / 描画は Three.js (CDN)
 * - 素材はすべてプリミティブで自作(任天堂の素材は不使用)
 */
class Main {
	static inline var R = 0.4; // 当たり判定の半径
	static inline var H = 1.6; // 身長
	static inline var GRAVITY = 28.0;
	static final JUMP_V:Array<Float> = [9.5, 11.5, 14.5]; // 1段 / 2段 / 3段ジャンプ

	// three.js objects
	static var scene:Dynamic;
	static var camera:Dynamic;
	static var renderer:Dynamic;
	static var player:Dynamic;
	static var shadow:Dynamic;
	static var star:Dynamic;

	// world
	static var boxes:Array<Box> = [];
	static var coins:Array<Coin> = [];
	static var starX = 0.0;
	static var starY = 0.0;
	static var starZ = 0.0;
	static var starGot = false;
	static var winTimer = 0.0;

	// player state
	static var px = 0.0;
	static var py = 0.0;
	static var pz = 8.0;
	static var vx = 0.0;
	static var vy = 0.0;
	static var vz = 0.0;
	static var facing = 0.0;
	static var onGround = false;
	static var pounding = false;
	static var chain = 0;
	static var sinceLand = 99.0;
	static var jumpBuf = 0.0;
	static var coyote = 0.0;
	static var squash = 0.0;
	static var coinCount = 0;

	// camera
	static var camYaw = 0.0;
	static var dragging = false;

	// input
	static var keys:Map<String, Bool> = new Map();
	static var last = 0.0;

	// ---------------------------------------------------------------- helpers
	static function geoBox(w:Float, h:Float, d:Float):Dynamic
		return js.Syntax.code("new THREE.BoxGeometry({0},{1},{2})", w, h, d);

	static function geoCyl(rt:Float, rb:Float, h:Float):Dynamic
		return js.Syntax.code("new THREE.CylinderGeometry({0},{1},{2},20)", rt, rb, h);

	static function geoSph(r:Float):Dynamic
		return js.Syntax.code("new THREE.SphereGeometry({0},20,14)", r);

	static function mesh(g:Dynamic, color:Int, emissive:Int = 0):Dynamic {
		var o:Dynamic = {color: color, emissive: emissive};
		var mat:Dynamic = js.Syntax.code("new THREE.MeshLambertMaterial({0})", o);
		return js.Syntax.code("new THREE.Mesh({0},{1})", g, mat);
	}

	static function place(m:Dynamic, x:Float, y:Float, z:Float):Dynamic {
		m.position.set(x, y, z);
		return m;
	}

	static inline function key(code:String):Bool
		return keys.exists(code) && keys.get(code);

	static function plat(x:Float, z:Float, w:Float, d:Float, top:Float, thick:Float = 1.0, color:Int = 0x6bbf59) {
		var b:Box = {x: x, y: top - thick / 2, z: z, w: w, h: thick, d: d};
		boxes.push(b);
		scene.add(place(mesh(geoBox(w, thick, d), color), b.x, b.y, b.z));
	}

	static function addCoin(x:Float, y:Float, z:Float) {
		var g:Dynamic = geoCyl(0.4, 0.4, 0.1);
		g.rotateX(Math.PI / 2);
		var m = place(mesh(g, 0xffd400, 0x664400), x, y, z);
		scene.add(m);
		coins.push({m: m, x: x, y: y, z: z, got: false});
	}

	// ---------------------------------------------------------------- setup
	static function buildLevel() {
		// 地面
		plat(0, 0, 90, 90, 0, 2, 0x4caf50);

		// 手前の浮きブロック(連続ジャンプの練習)
		plat(-10, 2, 4, 4, 1.2, 1.2, 0xc98b4b);
		plat(-14, -2, 4, 4, 2.4, 2.4, 0xc98b4b);
		plat(-18, -6, 4, 4, 3.6, 3.6, 0xc98b4b);
		addCoin(-10, 2.4, 2);
		addCoin(-14, 3.6, -2);
		addCoin(-18, 4.8, -6);

		// らせん階段 -> 頂上にスター
		var cx = 0.0;
		var cz = -14.0;
		var rad = 9.0;
		var steps = 14;
		for (i in 0...steps) {
			var a = i * 0.5;
			var x = cx + Math.cos(a) * rad;
			var z = cz + Math.sin(a) * rad;
			var top = (i + 1) * 1.0;
			plat(x, z, 3, 3, top, 1.0, (i % 2 == 0) ? 0xe8e0c8 : 0xb9a98a);
			if (i % 2 == 1) addCoin(x, top + 1.2, z);
		}
		var aTop = steps * 0.5;
		var tx = cx + Math.cos(aTop) * rad;
		var tz = cz + Math.sin(aTop) * rad;
		var topY = (steps + 1) * 1.0;
		plat(tx, tz, 6, 6, topY, 1.0, 0xf2c94c);
		starX = tx;
		starY = topY + 1.4;
		starZ = tz;

		// スタート地点のコインリング
		for (i in 0...8) {
			var a = i / 8 * Math.PI * 2;
			addCoin(Math.cos(a) * 6, 1.1, 4 + Math.sin(a) * 6);
		}

		// スター
		var sg:Dynamic = js.Syntax.code("new THREE.OctahedronGeometry({0})", 0.7);
		star = mesh(sg, 0xffe14d, 0x997700);
		star.position.set(starX, starY, starZ);
		scene.add(star);
	}

	static function buildPlayer() {
		player = js.Syntax.code("new THREE.Group()");
		// オリジナルキャラ: 丸い体のミントグリーンのカエル風「ポヨ」
		player.add(place(mesh(geoSph(0.45), 0x5fd6a0), 0, 0.62, 0)); // 体
		player.add(place(mesh(geoSph(0.30), 0xfff3c4), 0, 0.55, 0.20)); // おなか
		player.add(place(mesh(geoSph(0.34), 0x5fd6a0), 0, 1.20, 0)); // 頭
		player.add(place(mesh(geoSph(0.13), 0xffffff), -0.17, 1.42, 0.16)); // 左目(白)
		player.add(place(mesh(geoSph(0.13), 0xffffff), 0.17, 1.42, 0.16)); // 右目(白)
		player.add(place(mesh(geoSph(0.06), 0x222222), -0.17, 1.43, 0.27)); // 左目(黒)
		player.add(place(mesh(geoSph(0.06), 0x222222), 0.17, 1.43, 0.27)); // 右目(黒)
		player.add(place(mesh(geoBox(0.30, 0.04, 0.05), 0xd9534f), 0, 1.08, 0.32)); // くち
		player.add(place(mesh(geoCyl(0.40, 0.40, 0.08), 0xffb627), 0, 0.98, 0)); // 黄色いスカーフ
		player.add(place(mesh(geoBox(0.24, 0.14, 0.38), 0xff8c42), -0.18, 0.07, 0.08)); // 左足
		player.add(place(mesh(geoBox(0.24, 0.14, 0.38), 0xff8c42), 0.18, 0.07, 0.08)); // 右足
		scene.add(player);

		// 丸影
		var cg:Dynamic = js.Syntax.code("new THREE.CircleGeometry({0},24)", 0.5);
		cg.rotateX(-Math.PI / 2);
		var o:Dynamic = {color: 0x000000, transparent: true, opacity: 0.35};
		var mat:Dynamic = js.Syntax.code("new THREE.MeshBasicMaterial({0})", o);
		shadow = js.Syntax.code("new THREE.Mesh({0},{1})", cg, mat);
		scene.add(shadow);
	}

	static function respawn() {
		px = 0;
		py = 0;
		pz = 8;
		vx = vy = vz = 0;
		pounding = false;
		camYaw = 0;
	}

	static function resetGame() {
		respawn();
		coinCount = 0;
		for (c in coins) {
			c.got = false;
			c.m.visible = true;
		}
		starGot = false;
		star.visible = true;
		winTimer = 0;
		Browser.document.getElementById("msg").textContent = "";
	}

	// ---------------------------------------------------------------- update
	static function groundHeightAt(x:Float, z:Float, maxY:Float):Float {
		var best = -100.0;
		for (b in boxes) {
			var top = b.y + b.h / 2;
			if (top <= maxY && Math.abs(x - b.x) < b.w / 2 && Math.abs(z - b.z) < b.d / 2 && top > best)
				best = top;
		}
		return best;
	}

	static function angleLerp(cur:Float, target:Float, k:Float):Float {
		var d = target - cur;
		while (d > Math.PI) d -= Math.PI * 2;
		while (d < -Math.PI) d += Math.PI * 2;
		return cur + d * Math.min(1, k);
	}

	static function update(dt:Float) {
		// カメラ回転
		if (key("KeyQ") || key("ArrowLeft")) camYaw -= 2.2 * dt;
		if (key("KeyE") || key("ArrowRight")) camYaw += 2.2 * dt;

		// 入力
		var f:Float = ((key("KeyW") || key("ArrowUp")) ? 1 : 0) - ((key("KeyS") || key("ArrowDown")) ? 1 : 0);
		var r:Float = (key("KeyD") ? 1 : 0) - (key("KeyA") ? 1 : 0);
		var fx = -Math.sin(camYaw);
		var fz = -Math.cos(camYaw);
		var rx = Math.cos(camYaw);
		var rz = -Math.sin(camYaw);
		var mx = fx * f + rx * r;
		var mz = fz * f + rz * r;
		var len = Math.sqrt(mx * mx + mz * mz);

		var tvx = 0.0;
		var tvz = 0.0;
		if (len > 0.01 && !pounding) {
			mx /= len;
			mz /= len;
			tvx = mx * 8.0;
			tvz = mz * 8.0;
			facing = angleLerp(facing, Math.atan2(mx, mz), 14 * dt);
		}
		var acc = (onGround ? 60.0 : 25.0) * dt;
		vx += Math.max(-acc, Math.min(acc, tvx - vx));
		vz += Math.max(-acc, Math.min(acc, tvz - vz));
		if (pounding) {
			vx = 0;
			vz = 0;
		}

		// ジャンプ(バッファ + コヨーテタイム)
		jumpBuf -= dt;
		coyote -= dt;
		sinceLand += dt;
		if (onGround) coyote = 0.1;
		if (jumpBuf > 0 && coyote > 0 && !pounding) {
			if (sinceLand < 0.25 && len > 0.01)
				chain = Std.int(Math.min(chain + 1, 2));
			else
				chain = 0;
			vy = JUMP_V[chain];
			jumpBuf = 0;
			coyote = 0;
			onGround = false;
		}
		// ジャンプボタンを離したら低く
		if (!key("Space") && vy > 4 && !pounding) vy -= GRAVITY * dt;

		// ---- 縦方向
		var prevY = py;
		vy -= GRAVITY * dt;
		if (vy < -40) vy = -40;
		py += vy * dt;
		var wasGround = onGround;
		onGround = false;
		for (b in boxes) {
			var top = b.y + b.h / 2;
			var bot = b.y - b.h / 2;
			if (Math.abs(px - b.x) < b.w / 2 + R * 0.6 && Math.abs(pz - b.z) < b.d / 2 + R * 0.6) {
				if (vy <= 0 && prevY >= top - 0.05 && py <= top) {
					py = top;
					vy = 0;
					onGround = true;
				} else if (vy > 0 && prevY + H <= bot + 0.05 && py + H > bot) {
					py = bot - H;
					vy = 0;
				}
			}
		}
		if (onGround && !wasGround) {
			sinceLand = 0;
			if (pounding) {
				pounding = false;
				squash = 0.35;
			} else {
				squash = 0.15;
			}
		}
		if (onGround && len < 0.01 && sinceLand > 0.25) chain = 0;

		// ---- 横方向(壁の押し出し)
		px += vx * dt;
		pz += vz * dt;
		for (b in boxes) {
			var top = b.y + b.h / 2;
			var bot = b.y - b.h / 2;
			if (py + 0.1 >= top || py + H <= bot) continue;
			var hx = b.w / 2 + R;
			var hz = b.d / 2 + R;
			var dx = px - b.x;
			var dz = pz - b.z;
			if (Math.abs(dx) < hx && Math.abs(dz) < hz) {
				var ox = hx - Math.abs(dx);
				var oz = hz - Math.abs(dz);
				if (ox < oz) {
					px = b.x + (dx < 0 ? -hx : hx);
					vx = 0;
				} else {
					pz = b.z + (dz < 0 ? -hz : hz);
					vz = 0;
				}
			}
		}

		// 落下 -> リスポーン
		if (py < -25) respawn();

		// ---- 見た目
		squash *= Math.max(0, 1 - 10 * dt);
		player.position.set(px, py, pz);
		player.rotation.y = facing;
		player.scale.set(1 + squash, 1 - squash, 1 + squash);
		var gy = groundHeightAt(px, pz, py + 0.2);
		shadow.position.set(px, gy + 0.03, pz);
		var sh = Math.max(0.3, 1 - (py - gy) * 0.08);
		shadow.scale.set(sh, 1, sh);

		// コイン
		for (c in coins) {
			if (c.got) continue;
			c.m.rotation.y += 4 * dt;
			var dx = px - c.x;
			var dy = (py + 0.8) - c.y;
			var dz = pz - c.z;
			if (dx * dx + dy * dy + dz * dz < 1.0) {
				c.got = true;
				c.m.visible = false;
				coinCount++;
			}
		}

		// スター
		if (!starGot) {
			star.rotation.y += 2.5 * dt;
			star.position.y = starY + Math.sin(Browser.window.performance.now() / 300) * 0.2;
			var dx = px - starX;
			var dy = (py + 0.8) - starY;
			var dz = pz - starZ;
			if (dx * dx + dy * dy + dz * dz < 1.7) {
				starGot = true;
				star.visible = false;
				winTimer = 5;
				Browser.document.getElementById("msg").textContent = "★ STAR GET! ★";
			}
		} else {
			winTimer -= dt;
			if (winTimer <= 0) resetGame();
		}

		// カメラ追従
		var camDist = 9.0;
		var tx = px + Math.sin(camYaw) * camDist;
		var ty = py + 5.0;
		var tz = pz + Math.cos(camYaw) * camDist;
		var k = 1 - Math.exp(-6 * dt);
		camera.position.x += (tx - camera.position.x) * k;
		camera.position.y += (ty - camera.position.y) * k;
		camera.position.z += (tz - camera.position.z) * k;
		camera.lookAt(px, py + 1.2, pz);

		// HUD
		Browser.document.getElementById("hud").textContent = "COIN x " + coinCount + " / " + coins.length + "    STAR " + (starGot ? 1 : 0) + " / 1";
	}

	static function loop(t:Float) {
		var dt = Math.min((t - last) / 1000, 1 / 30);
		last = t;
		if (dt > 0) update(dt);
		renderer.render(scene, camera);
		Browser.window.requestAnimationFrame(loop);
	}

	// ---------------------------------------------------------------- main
	static function main() {
		var w = Browser.window.innerWidth;
		var h = Browser.window.innerHeight;

		scene = js.Syntax.code("new THREE.Scene()");
		scene.background = js.Syntax.code("new THREE.Color({0})", 0x7ec8ff);
		scene.fog = js.Syntax.code("new THREE.Fog({0},{1},{2})", 0x7ec8ff, 40, 130);

		camera = js.Syntax.code("new THREE.PerspectiveCamera({0},{1},{2},{3})", 60, w / h, 0.1, 400);
		camera.position.set(0, 6, 17);

		var opts:Dynamic = {antialias: true};
		renderer = js.Syntax.code("new THREE.WebGLRenderer({0})", opts);
		renderer.setSize(w, h);
		renderer.setPixelRatio(Math.min(2, Browser.window.devicePixelRatio));
		Browser.document.body.appendChild(renderer.domElement);

		scene.add(js.Syntax.code("new THREE.AmbientLight({0},{1})", 0xffffff, 0.65));
		var sun:Dynamic = js.Syntax.code("new THREE.DirectionalLight({0},{1})", 0xffffff, 0.8);
		sun.position.set(20, 40, 10);
		scene.add(sun);

		buildLevel();
		buildPlayer();
		respawn();

		Browser.window.addEventListener("resize", function(_) {
			var w2 = Browser.window.innerWidth;
			var h2 = Browser.window.innerHeight;
			renderer.setSize(w2, h2);
			camera.aspect = w2 / h2;
			camera.updateProjectionMatrix();
		});

		Browser.document.addEventListener("keydown", function(e:KeyboardEvent) {
			if (e.code == "Space" || e.code.indexOf("Arrow") == 0) e.preventDefault();
			if (!key(e.code)) {
				if (e.code == "Space") jumpBuf = 0.12;
				if ((e.code == "KeyC" || e.code == "ShiftLeft" || e.code == "ShiftRight") && !onGround && !pounding) {
					pounding = true;
					vy = -32;
				}
			}
			keys.set(e.code, true);
		});
		Browser.document.addEventListener("keyup", function(e:KeyboardEvent) {
			keys.set(e.code, false);
		});

		Browser.document.addEventListener("mousedown", function(_) dragging = true);
		Browser.document.addEventListener("mouseup", function(_) dragging = false);
		Browser.document.addEventListener("mousemove", function(e:MouseEvent) {
			if (dragging) camYaw -= e.movementX * 0.005;
		});

		Browser.window.requestAnimationFrame(loop);
	}
}
